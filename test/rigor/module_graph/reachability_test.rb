# frozen_string_literal: true

require_relative "../../test_helper"

class ReachabilityTest < Minitest::Test
  Reachability = Rigor::ModuleGraph::Reachability
  Edge = Rigor::ModuleGraph::Edge

  def edge(from, to, kind = "include")
    Edge.build(from: from, to: to, kind: kind)
  end

  def test_empty_roots_returns_input_unchanged
    edges = [edge("A", "B")]
    assert_equal edges, Reachability.filter(edges, roots: [])
    assert_equal edges, Reachability.filter(edges, roots: nil)
  end

  def test_filter_with_root_keeps_only_reachable_edges
    edges = [
      edge("A", "B"),
      edge("B", "C"),
      edge("X", "Y") # unrelated
    ]
    filtered = Reachability.filter(edges, roots: ["A"])
    assert_equal 2, filtered.size
    refute_includes filtered.map(&:from), "X"
  end

  def test_depth_limits_hops
    edges = [
      edge("A", "B"),
      edge("B", "C"),
      edge("C", "D")
    ]
    filtered = Reachability.filter(edges, roots: ["A"], depth: 1)
    # depth 1: A → B reachable, C not yet.
    assert_equal([%w[A B]], filtered.map { |e| [e.from, e.to] })
  end

  def test_direction_out_only_follows_outgoing
    edges = [
      edge("A", "B"),
      edge("X", "A"), # incoming to A
      edge("B", "C")
    ]
    filtered = Reachability.filter(edges, roots: ["A"], direction: :out)
    # We start at A, only follow outgoing → reach B, C; skip X.
    assert_equal %w[B C].sort,
                 (filtered.flat_map { |e| [e.from, e.to] } - ["A"]).uniq.sort
  end

  def test_direction_in_follows_backwards
    edges = [
      edge("A", "B"),
      edge("X", "A"), # incoming to A
      edge("B", "C")
    ]
    filtered = Reachability.filter(edges, roots: ["A"], direction: :in)
    # Following inbound edges from A: X depends on A → X is reachable.
    # Not B (A → B is outbound for A).
    targets = filtered.map { |e| [e.from, e.to] }
    assert_equal [%w[X A]], targets
  end

  def test_direction_both_unions_in_and_out
    edges = [
      edge("A", "B"),
      edge("X", "A"),
      edge("B", "C")
    ]
    filtered = Reachability.filter(edges, roots: ["A"], direction: :both)
    pairs = filtered.map { |e| [e.from, e.to] }.sort
    assert_equal [%w[A B], %w[B C], %w[X A]].sort, pairs
  end

  def test_multiple_roots_union
    edges = [
      edge("A", "B"),
      edge("X", "Y"),
      edge("M", "N")
    ]
    filtered = Reachability.filter(edges, roots: %w[A X])
    pairs = filtered.map { |e| [e.from, e.to] }.sort
    assert_equal [%w[A B], %w[X Y]].sort, pairs
  end

  def test_unknown_direction_raises
    assert_raises(ArgumentError) do
      Reachability.filter([edge("A", "B")], roots: ["A"], direction: :sideways)
    end
  end
end
