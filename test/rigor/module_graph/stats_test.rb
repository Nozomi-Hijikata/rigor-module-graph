# frozen_string_literal: true

require_relative "../../test_helper"

class StatsTest < Minitest::Test
  Stats = Rigor::ModuleGraph::Stats
  Edge = Rigor::ModuleGraph::Edge

  def edge(from, to, kind = "include")
    Edge.build(from: from, to: to, kind: kind)
  end

  def test_empty_edges_returns_empty
    assert_empty Stats.compute([])
  end

  def test_internal_edge_does_not_count_as_fan_out
    edges = [
      edge("Billing::Invoice", "Billing::Payment")
    ]
    result = Stats.compute(edges)
    billing = result.first
    assert_equal "Billing", billing.namespace
    assert_equal 2, billing.nodes
    assert_equal 0, billing.fan_out
    assert_equal 0, billing.fan_in
    assert_equal 1, billing.internal
  end

  def test_fan_out_to_external_namespace
    edges = [
      edge("Billing::Invoice", "Auth::User"),
      edge("Billing::Payment", "Auth::User")
    ]
    result = Stats.compute(edges)
    billing = result.find { |m| m.namespace == "Billing" }
    auth = result.find { |m| m.namespace == "Auth" }
    assert_equal 2, billing.fan_out
    assert_equal 0, billing.fan_in
    assert_equal 0, auth.fan_out
    assert_equal 2, auth.fan_in
  end

  def test_top_level_constants_bucket_into_top_level
    edges = [
      edge("Foo", "Bar"),
      edge("Billing::Invoice", "Bar")
    ]
    result = Stats.compute(edges)
    top = result.find { |m| m.namespace == "(top-level)" }
    refute_nil top
    # Foo and Bar live at the top level.
    assert_equal 2, top.nodes
    # Foo -> Bar is internal to the top-level bucket.
    assert_equal 1, top.internal
    # Billing::Invoice -> Bar is fan_in for (top-level).
    assert_equal 1, top.fan_in
  end

  def test_depth_2_grouping_splits_inner_namespaces
    edges = [
      edge("Billing::Invoice::Line", "Billing::Payment::Receipt"),
      edge("Billing::Invoice::Line", "Billing::Invoice::Item")
    ]
    result = Stats.compute(edges, depth: 2)
    namespaces = result.map(&:namespace).sort
    assert_equal ["Billing::Invoice", "Billing::Payment"], namespaces
    invoice = result.find { |m| m.namespace == "Billing::Invoice" }
    assert_equal 1, invoice.fan_out   # Line -> Payment::Receipt
    assert_equal 1, invoice.internal  # Line -> Item
  end

  def test_absolute_path_collapses_with_relative
    edges = [
      edge("::Billing::Invoice", "Billing::Payment"),
      edge("Billing::Invoice", "Billing::Refund")
    ]
    result = Stats.compute(edges)
    billing = result.first
    # The two `Billing::Invoice` mentions (one with leading
    # `::`) should count as one node, not two.
    assert_equal 3, billing.nodes # Invoice, Payment, Refund
    assert_equal 2, billing.internal
  end

  def test_sort_order_is_fan_out_desc_then_namespace_asc
    edges = [
      edge("Z::A", "External"),
      edge("Y::A", "External"),
      edge("Y::B", "External"),
      edge("Y::C", "External"),
      edge("X::A", "External"),
      edge("X::B", "External")
    ]
    result = Stats.compute(edges)
    # Y has 3 fan-out, X has 2, Z has 1. (top-level) has 0.
    assert_equal %w[Y X Z (top-level)], result.map(&:namespace)
  end

  def test_metrics_total_equals_fan_out_plus_internal
    edges = [
      edge("Billing::Invoice", "Billing::Payment"),
      edge("Billing::Invoice", "Auth::User")
    ]
    billing = Stats.compute(edges).find { |m| m.namespace == "Billing" }
    assert_equal billing.fan_out + billing.internal, billing.total
  end

  def test_metrics_round_trip_to_hash
    edges = [edge("A::B", "A::C")]
    billing = Stats.compute(edges).first
    h = billing.to_h
    assert_equal "A", h["namespace"]
    assert_equal 2, h["nodes"]
    assert_equal 1, h["internal"]
    assert_includes h.keys, "total"
  end
end
