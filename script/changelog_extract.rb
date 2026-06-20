#!/usr/bin/env ruby
# Extract a single version's section from a Keep-a-Changelog
# document and reflow it into single-line paragraphs.
#
# Why: GitHub Releases render their notes with the GFM line-break
# extension on, so a single newline inside a paragraph becomes a
# visible mid-sentence `<br>`. CHANGELOG.md keeps its column-70
# hard wrap for source readability and diff cleanliness; this
# script reflows on the way out so the release body looks right
# without changing the source style.
#
# CLI:
#   ruby script/changelog_extract.rb --version 0.1.1 CHANGELOG.md
#   cat CHANGELOG.md | ruby script/changelog_extract.rb --version 0.1.1
#
# Returns the reflowed section on stdout. Exit codes:
#   0 — section found and reflowed
#   1 — no `## [VERSION]` section, or section is whitespace-only

require "optparse"

module ChangelogExtract
  module_function

  # @param markdown [String] the full CHANGELOG content
  # @param version [String] the version slug between the brackets
  # @return [String, nil] the reflowed section, or nil if missing
  def call(markdown, version:)
    raw = slice_section(markdown, version)
    return nil if raw.nil?

    reflow(raw)
  end

  # Returns the lines between `## [VERSION]` and the next `## [`
  # heading, exclusive on both ends. The first blank line that
  # typically follows the heading is included so paragraphs that
  # start on the next non-blank line keep their leading space.
  def slice_section(markdown, version)
    header_prefix = "## [#{version}]"
    lines = markdown.lines.map(&:chomp)

    start_idx = lines.index { |line| line.start_with?(header_prefix) }
    return nil if start_idx.nil?

    body_offset = lines[(start_idx + 1)..].index { |line| line.start_with?("## [") }
    end_idx = body_offset.nil? ? lines.length : start_idx + 1 + body_offset

    lines[(start_idx + 1)...end_idx].join("\n")
  end

  # Reflow rules (each applied per line, top-down):
  #
  # - code fence (```) — flush buffer, pass the fence through,
  #   toggle the in-code flag. Code-block contents pass verbatim.
  # - blank line — paragraph separator. Flush + emit blank.
  # - heading (`#+ `) or table row (`|...`) — block element.
  #   Flush + emit verbatim.
  # - new list item (`- `, `* `, `+ ` with optional leading
  #   whitespace) — flush, then start a fresh buffer at this
  #   line (a list item may span several wrap-continuation
  #   lines).
  # - anything else — continuation. Strip its leading whitespace
  #   and join into the buffer with a single space.
  def reflow(text)
    out = []
    buf = String.new
    in_code = false

    text.lines.map(&:chomp).each do |line|
      if line.start_with?("```")
        flush(out, buf)
        buf = String.new
        out << line
        in_code = !in_code
        next
      end

      if in_code
        out << line
        next
      end

      if line.empty?
        flush(out, buf)
        buf = String.new
        out << ""
        next
      end

      if line.match?(/\A(#+ |\|)/)
        flush(out, buf)
        buf = String.new
        out << line
        next
      end

      if line.match?(/\A[ \t]*[-*+] /)
        flush(out, buf)
        buf = line.dup
        next
      end

      continuation = line.sub(/\A[ \t]+/, "")
      buf << (buf.empty? ? continuation : " #{continuation}")
    end

    flush(out, buf)
    out.join("\n")
  end

  def flush(out, buf)
    out << buf unless buf.empty?
  end
end

if __FILE__ == $PROGRAM_NAME
  version = nil
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: changelog_extract.rb --version X.Y.Z [PATH]"
    opts.on("--version VERSION", "Version to extract from CHANGELOG.md") do |v|
      version = v
    end
    opts.on("-h", "--help", "Show this help") do
      puts opts
      exit 0
    end
  end
  parser.parse!

  if version.nil? || version.empty?
    warn "missing --version"
    warn parser.help
    exit 1
  end

  source = ARGV.first ? File.read(ARGV.first) : $stdin.read
  result = ChangelogExtract.call(source, version: version)

  if result.nil?
    warn "no section found for version #{version.inspect}"
    exit 1
  end

  if result.strip.empty?
    warn "section for version #{version.inspect} is empty"
    exit 1
  end

  puts result
end
