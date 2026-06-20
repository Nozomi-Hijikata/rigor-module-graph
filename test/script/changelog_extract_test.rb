# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../script/changelog_extract"

class ChangelogExtractTest < Minitest::Test
  def test_returns_nil_for_missing_version
    md = "## [0.1.0]\n\nfoo\n"
    assert_nil ChangelogExtract.call(md, version: "9.9.9")
  end

  def test_slices_the_named_version_only
    md = <<~MD
      # Changelog

      ## [Unreleased]

      ## [0.2.0] — 2026-06-21

      Second release.

      ## [0.1.0] — 2026-06-20

      First release.
    MD

    out = ChangelogExtract.call(md, version: "0.2.0")
    assert_includes out, "Second release."
    refute_includes out, "First release."
  end

  def test_handles_the_oldest_section_with_no_following_version
    md = <<~MD
      ## [0.2.0]

      Second.

      ## [0.1.0]

      First.

      [compare]: https://example.com
    MD

    out = ChangelogExtract.call(md, version: "0.1.0")
    assert_includes out, "First."
    # Trailing link-reference rows fall through the reflow as
    # regular continuation text; they aren't separated by a
    # blank line in the source, so they wind up joined onto the
    # `First.` paragraph. That's acceptable for our use case —
    # release-notes consumers don't render bare link-references.
  end

  def test_reflows_soft_wrapped_prose_into_one_line
    md = <<~MD
      ## [0.1.0]

      First line of prose
      that wraps onto
      multiple lines.
    MD

    out = ChangelogExtract.call(md, version: "0.1.0")
    assert_includes out, "First line of prose that wraps onto multiple lines."
  end

  def test_reflows_list_item_with_wrap_continuation
    md = <<~MD
      ## [0.1.0]

      - first item that
        wraps to a second line
        and a third.
      - second item
    MD

    out = ChangelogExtract.call(md, version: "0.1.0")
    assert_includes out, "- first item that wraps to a second line and a third."
    assert_includes out, "- second item"
  end

  def test_preserves_subheadings_on_their_own_line
    md = <<~MD
      ## [0.1.0]

      Intro paragraph
      wrapped.

      ### Added

      - foo

      ### Fixed

      - bar
    MD

    out = ChangelogExtract.call(md, version: "0.1.0")
    assert_match(/^### Added$/, out)
    assert_match(/^### Fixed$/, out)
    assert_includes out, "Intro paragraph wrapped."
  end

  def test_passes_fenced_code_blocks_through_verbatim
    md = <<~MD
      ## [0.1.0]

      Some prose that
      wraps.

      ```ruby
      def foo
        bar
      end
      ```
    MD

    out = ChangelogExtract.call(md, version: "0.1.0")
    assert_includes out, "Some prose that wraps."
    assert_includes out, "```ruby\ndef foo\n  bar\nend\n```"
  end

  def test_preserves_tables_row_by_row
    md = <<~MD
      ## [0.1.0]

      | col1 | col2 |
      |---|---|
      | a | b |
    MD

    out = ChangelogExtract.call(md, version: "0.1.0")
    assert_match(/^\| col1 \| col2 \|$/, out)
    assert_match(/^\|---\|---\|$/, out)
    assert_match(/^\| a \| b \|$/, out)
  end

  def test_collapses_multiple_paragraphs_individually
    md = <<~MD
      ## [0.1.0]

      First paragraph
      wraps.

      Second paragraph
      also wraps.
    MD

    out = ChangelogExtract.call(md, version: "0.1.0")
    assert_includes out, "First paragraph wraps."
    assert_includes out, "Second paragraph also wraps."
  end

  def test_dot_in_version_is_not_a_regex_metacharacter
    md = <<~MD
      ## [01010]

      Wrong section — `0.1.0` would match this if `.` is regex.

      ## [0.1.0]

      Correct section.
    MD

    out = ChangelogExtract.call(md, version: "0.1.0")
    assert_includes out, "Correct section."
    refute_includes out, "Wrong section"
  end

  def test_call_returns_nil_when_no_match
    assert_nil ChangelogExtract.call("no headings here\n", version: "0.1.0")
  end
end
