# frozen_string_literal: true

require_relative "../../test_helper"
require "rigor/module_graph/cli"
require "stringio"

class ViewTest < Minitest::Test
  CLI = Rigor::ModuleGraph::CLI
  Edge = Rigor::ModuleGraph::Edge

  def test_effective_collapse_picks_namespaces_with_enough_members
    edges = [
      Edge.build(from: "Billing::Invoice", to: "Auditable", kind: "include"),
      Edge.build(from: "Billing::Payment", to: "Auditable", kind: "include"),
      Edge.build(from: "Billing::Refund", to: "Auditable", kind: "include"),
      Edge.build(from: "Auth::User", to: "Concern", kind: "include"),
      Edge.build(from: "Auth::Session", to: "Concern", kind: "include"),
      Edge.build(from: "Toplevel", to: "ApplicationRecord", kind: "inherits")
    ]
    view = build_view
    # Billing has 3 members → collapsed. Auth has 2 → below the
    # default threshold of 3. Toplevel / ApplicationRecord /
    # Concern / Auditable have no `::` so they aren't candidates.
    assert_equal ["Billing"], view.effective_collapse(edges)
  end

  def test_effective_collapse_skips_absolute_path_empty_head
    # `::Foo` splits to ["", "Foo"] — without the empty-head
    # guard this would surface as a bogus "" collapse target.
    edges = [
      Edge.build(from: "::Foo", to: "Bar", kind: "inherits"),
      Edge.build(from: "::Foo", to: "Baz", kind: "include"),
      Edge.build(from: "::Foo", to: "Qux", kind: "include")
    ]
    view = build_view
    refute_includes view.effective_collapse(edges), ""
  end

  def test_effective_collapse_respects_explicit_override
    view = build_view(collapse: ["Custom"])
    assert_equal ["Custom"], view.effective_collapse([])
  end

  def test_effective_collapse_respects_no_collapse
    view = build_view(collapse: [])
    edges = [
      Edge.build(from: "Billing::Invoice", to: "Auditable", kind: "include"),
      Edge.build(from: "Billing::Payment", to: "Auditable", kind: "include")
    ]
    assert_equal [], view.effective_collapse(edges)
  end

  def test_effective_collapse_does_not_pick_deep_prefixes
    # `Billing::Invoice::Line` / Item / Foo all roll up to the
    # top-level `Billing` cluster — we never pick the intermediate
    # `Billing::Invoice` prefix because nested clusters compete.
    edges = [
      Edge.build(from: "Billing::Invoice::Line", to: "Auditable", kind: "include"),
      Edge.build(from: "Billing::Invoice::Item", to: "Auditable", kind: "include"),
      Edge.build(from: "Billing::Invoice::Foo", to: "Auditable", kind: "include")
    ]
    view = build_view
    assert_equal ["Billing"], view.effective_collapse(edges)
  end

  def test_render_subtitle_includes_collapse_when_present
    view = build_view
    edges = [Edge.build(from: "A", to: "B", kind: "include")]
    subtitle = view.render_subtitle(edges, ["Billing"], nil)
    assert_includes subtitle, "1 edge(s)"
    assert_includes subtitle, "collapsed: Billing"
  end

  def test_render_subtitle_truncates_long_collapse_lists
    view = build_view
    collapse = %w[A B C D E F G H I J]
    subtitle = view.render_subtitle([], collapse, nil)
    # Preview window is 6; the rest is summarised so the trailer
    # doesn't grow unbounded on a large project.
    assert_includes subtitle, "collapsed: A, B, C, D, E, F (+4 more)"
  end

  def test_render_subtitle_omits_collapse_when_empty
    view = build_view
    subtitle = view.render_subtitle([], [], nil)
    refute_includes subtitle, "collapsed:"
  end

  def test_render_subtitle_reports_packages_instead_of_collapse_when_groups_given
    view = build_view
    groups = {
      "Billing::Invoice" => "packages/billing",
      "Auth::User" => "packages/auth",
      "Billing::Payment" => "packages/billing"
    }
    subtitle = view.render_subtitle([], [], groups)
    refute_includes subtitle, "collapsed:"
    assert_includes subtitle, "packages: packages/auth, packages/billing"
  end

  def test_effective_output_path_for_html_defaults_to_well_known_location
    view = build_view
    view.instance_variable_get(:@options)[:format] = "html"
    assert_equal CLI::View::DEFAULT_HTML_OUTPUT, view.effective_output_path
  end

  def test_effective_output_path_for_non_html_is_nil_for_stdout
    view = build_view
    %w[mermaid dot svg class-diagram].each do |fmt|
      view.instance_variable_get(:@options)[:format] = fmt
      assert_nil view.effective_output_path,
                 "#{fmt} should stream to stdout when no -o given"
    end
  end

  def test_explicit_save_path_wins_over_default_for_every_format
    %w[html mermaid dot svg class-diagram].each do |fmt|
      view = build_view
      view.instance_variable_get(:@options)[:format] = fmt
      view.instance_variable_get(:@options)[:output] = "/tmp/out"
      assert_equal "/tmp/out", view.effective_output_path
    end
  end

  def build_view(collapse: nil)
    view = CLI::View.new(stdout: StringIO.new, stderr: StringIO.new)
    view.instance_variable_get(:@options)[:collapse] = collapse
    view
  end
end
