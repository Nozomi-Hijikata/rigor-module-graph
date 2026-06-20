require "digest"

# Re-computes sha256 for every line in `vendor/CHECKSUMS` and
# aborts on mismatch. Backing implementation for `rake
# vendor:verify`; pre-commit and CI both run that task.
module VendorVerify
  module_function

  def run(checksums_path:, vendor_dir:)
    unless File.exist?(checksums_path)
      abort "vendor:verify: #{checksums_path} not found"
    end

    failures = []
    seen = 0
    File.foreach(checksums_path) do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")

      expected, filename = line.split(/\s+/, 2)
      unless expected && filename
        failures << "  malformed line: #{line.inspect}"
        next
      end

      path = File.join(vendor_dir, filename)
      unless File.exist?(path)
        failures << "  #{filename}: file missing"
        next
      end

      actual = Digest::SHA256.file(path).hexdigest
      if actual == expected
        seen += 1
      else
        failures << "  #{filename}: expected #{expected}, got #{actual}"
      end
    end

    if failures.empty?
      puts "vendor:verify: #{seen} file(s) match CHECKSUMS"
    else
      puts "vendor:verify: mismatch detected"
      failures.each { |line| puts line }
      abort
    end
  end
end
