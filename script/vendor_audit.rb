require "digest"
require "net/http"
require "openssl"
require "stringio"
require "uri"
require "yaml"
require "zlib"

# 4-source cross-check for vendored third-party assets. For
# each entry in MANIFEST.yml, asserts that the local copy
# matches:
#
# 1. The npm registry's `dist.integrity` (sha512 over the
#    tarball as published).
# 2. The sha256 of the file extracted from inside that tarball
#    at `tarball_path`.
# 3. The sha256 of the file at the GitHub raw URL for the
#    pinned release tag.
# 4. The sha256 of every CDN mirror listed under `cdns:`.
#
# Network-using; not part of the regular CI pipeline. Run
# explicitly on bump PRs.
module VendorAudit
  PERMITTED_YAML_CLASSES = [Date, Time].freeze

  module_function

  def run(manifest_path:, vendor_dir:)
    abort "vendor:audit: #{manifest_path} not found" unless File.exist?(manifest_path)

    manifest = YAML.safe_load_file(manifest_path, permitted_classes: PERMITTED_YAML_CLASSES)
    failures = []

    Array(manifest["files"]).each do |entry|
      audit_entry(entry, vendor_dir: vendor_dir, failures: failures)
    end

    if failures.empty?
      puts "\nvendor:audit: all sources agree"
    else
      puts "\nvendor:audit: mismatch detected"
      failures.each { |f| puts f }
      abort
    end
  end

  def audit_entry(entry, vendor_dir:, failures:)
    filename = entry.fetch("filename")
    expected_sha256 = entry.fetch("sha256")
    puts "==> #{filename}"

    check_local(File.join(vendor_dir, filename), expected_sha256, failures)
    check_npm(entry.fetch("npm"), expected_sha256, failures)
    check_remote_sources(entry, expected_sha256, failures)
  end

  def check_local(path, expected_sha256, failures)
    actual = Digest::SHA256.file(path).hexdigest
    if actual == expected_sha256
      puts "  local                  sha256 OK"
    else
      failures << "  local: sha256 mismatch (got #{actual})"
    end
  end

  def check_npm(npm, expected_sha256, failures)
    tarball = http_get(npm.fetch("tarball_url"))

    integrity = "sha512-#{[OpenSSL::Digest::SHA512.digest(tarball)].pack("m0")}"
    if integrity == npm.fetch("integrity")
      puts "  npm tarball            integrity OK"
    else
      failures << "  npm tarball integrity mismatch (got #{integrity})"
    end

    inner_path = npm.fetch("tarball_path")
    inner = extract_from_tar_gz(tarball, inner_path)
    inner_sha = Digest::SHA256.hexdigest(inner)
    if inner_sha == expected_sha256
      puts "  npm tarball:#{inner_path}  sha256 OK"
    else
      failures << "  npm tarball:#{inner_path} sha256 mismatch (got #{inner_sha})"
    end
  end

  def check_remote_sources(entry, expected_sha256, failures)
    sources = [["github (raw)", entry.fetch("github_raw_url")]]
    Array(entry["cdns"]).each_with_index do |url, i|
      sources << ["cdn[#{i}]", url]
    end

    sources.each do |label, url|
      actual = Digest::SHA256.hexdigest(http_get(url))
      if actual == expected_sha256
        puts "  #{label.ljust(22)} sha256 OK"
      else
        failures << "  #{label}: sha256 mismatch (got #{actual}) — #{url}"
      end
    end
  end

  def http_get(url, limit: 5)
    raise "too many redirects" if limit <= 0

    uri = URI(url)
    response = Net::HTTP.start(uri.hostname, uri.port,
                               use_ssl: uri.scheme == "https",
                               open_timeout: 15, read_timeout: 60) do |http|
      http.get(uri.request_uri)
    end
    case response
    when Net::HTTPRedirection
      http_get(response["location"], limit: limit - 1)
    when Net::HTTPSuccess
      response.body
    else
      raise "http_get #{url}: #{response.code} #{response.message}"
    end
  end

  # Minimal tar.gz extractor: locates the requested member by
  # name and returns its content. No external `tar` binary
  # dependency.
  def extract_from_tar_gz(bytes, member_path)
    inflated = Zlib::GzipReader.new(StringIO.new(bytes)).read
    offset = 0
    while offset < inflated.bytesize
      header = inflated.byteslice(offset, 512)
      break if header.nil? || header.bytes.all?(&:zero?)

      name = header[0, 100].unpack1("Z*")
      size = header[124, 12].unpack1("Z*").to_i(8)
      data_start = offset + 512
      return inflated.byteslice(data_start, size) if name == member_path

      offset = data_start + (((size + 511) / 512) * 512)
    end
    raise "extract_from_tar_gz: #{member_path.inspect} not found in tarball"
  end
end
