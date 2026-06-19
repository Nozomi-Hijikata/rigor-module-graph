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
end
