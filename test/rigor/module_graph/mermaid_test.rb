# frozen_string_literal: true

require_relative "../../test_helper"

class MermaidTest < Minitest::Test
  include SnapshotHelpers

  Mermaid = Rigor::ModuleGraph::Mermaid
  Edge = Rigor::ModuleGraph::Edge

  def test_renders_all_kinds
    edges = [
      Edge.build(from: "Billing::Invoice", to: "ApplicationRecord", kind: "inherits"),
      Edge.build(from: "Billing::Invoice", to: "Auditable", kind: "include"),
      Edge.build(from: "Billing::Invoice", to: "Tracked", kind: "prepend"),
      Edge.build(from: "Billing::Invoice", to: "Searchable", kind: "extend"),
      Edge.build(from: "Billing::Invoice", to: "Money", kind: "const_ref")
    ]
    assert_snapshot "mermaid/all_kinds", Mermaid.render(edges)
  end

  def test_dedupes_repeated_edges
    edges = [
      Edge.build(from: "A", to: "B", kind: "include"),
      Edge.build(from: "A", to: "B", kind: "include")
    ]
    assert_snapshot "mermaid/dedup", Mermaid.render(edges)
  end

  def test_collapse_wraps_namespace_in_subgraph
    edges = [
      Edge.build(from: "Billing::Invoice", to: "ApplicationRecord", kind: "inherits"),
      Edge.build(from: "Billing::Invoice", to: "Auditable", kind: "include"),
      Edge.build(from: "Billing::Payment", to: "ApplicationRecord", kind: "inherits"),
      Edge.build(from: "Billing::Payment", to: "Auditable", kind: "include")
    ]
    assert_snapshot "mermaid/collapse_billing", Mermaid.render(edges, collapse: ["Billing"])
  end

  def test_unresolved_edge_gets_unresolved_class
    edges = [
      Edge.build(from: "Foo", to: "some_variable", kind: "include", confidence: "unresolved")
    ]
    assert_snapshot "mermaid/unresolved", Mermaid.render(edges)
  end
end
