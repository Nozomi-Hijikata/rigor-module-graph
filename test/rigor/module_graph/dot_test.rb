# frozen_string_literal: true

require_relative "../../test_helper"

class DotTest < Minitest::Test
  include SnapshotHelpers

  Dot = Rigor::ModuleGraph::Dot
  Edge = Rigor::ModuleGraph::Edge

  def test_renders_empty_edge_list
    assert_snapshot "dot/empty", Dot.render([])
  end

  def test_renders_all_kinds
    edges = [
      Edge.build(from: "Billing::Invoice", to: "ApplicationRecord", kind: "inherits"),
      Edge.build(from: "Billing::Invoice", to: "Auditable", kind: "include"),
      Edge.build(from: "Billing::Invoice", to: "Tracked", kind: "prepend"),
      Edge.build(from: "Billing::Invoice", to: "Searchable", kind: "extend"),
      Edge.build(from: "Billing::Invoice", to: "Money", kind: "const_ref")
    ]
    assert_snapshot "dot/all_kinds", Dot.render(edges)
  end

  def test_dedupes_repeated_edges
    edges = [
      Edge.build(from: "A", to: "B", kind: "include"),
      Edge.build(from: "A", to: "B", kind: "include", path: "elsewhere.rb")
    ]
    assert_snapshot "dot/dedup", Dot.render(edges)
  end

  def test_collapse_wraps_namespace_in_subgraph_cluster
    edges = [
      Edge.build(from: "Billing::Invoice", to: "ApplicationRecord", kind: "inherits"),
      Edge.build(from: "Billing::Invoice", to: "Auditable", kind: "include"),
      Edge.build(from: "Billing::Payment", to: "ApplicationRecord", kind: "inherits"),
      Edge.build(from: "Billing::Payment", to: "Auditable", kind: "include")
    ]
    assert_snapshot "dot/collapse_billing", Dot.render(edges, collapse: ["Billing"])
  end

  def test_unresolved_edge_uses_dashed_style
    edges = [
      Edge.build(from: "Foo", to: "some_variable", kind: "include", confidence: "unresolved")
    ]
    assert_snapshot "dot/unresolved", Dot.render(edges)
  end
end
