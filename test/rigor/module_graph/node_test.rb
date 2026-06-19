# frozen_string_literal: true

require_relative "../../test_helper"
require "stringio"

class NodeTest < Minitest::Test
  Node = Rigor::ModuleGraph::Node
  NodeIO = Rigor::ModuleGraph::NodeIO

  def test_build_validates_kind
    assert_raises(ArgumentError) { Node.build(kind: "weird", name: "Foo") }
  end

  def test_build_validates_visibility
    assert_raises(ArgumentError) do
      Node.build(kind: "instance_method", name: "foo", owner: "Bar", visibility: "weird")
    end
  end

  def test_build_validates_access
    assert_raises(ArgumentError) do
      Node.build(kind: "attribute", name: "foo", owner: "Bar", access: "weird")
    end
  end

  def test_to_h_omits_nil_optionals
    node = Node.build(kind: "class", name: "Foo")
    assert_equal({ "kind" => "class", "name" => "Foo" }, node.to_h)
  end

  def test_dedup_key_collapses_method_redefinitions
    a = Node.build(kind: "instance_method", name: "save", owner: "Invoice", line: 1)
    b = Node.build(kind: "instance_method", name: "save", owner: "Invoice", line: 99)
    assert_equal a.dedup_key, b.dedup_key
  end

  def test_io_round_trip_with_dedup
    nodes = [
      Node.build(kind: "class", name: "Invoice"),
      Node.build(kind: "class", name: "Invoice"), # dup
      Node.build(kind: "instance_method", name: "total", owner: "Invoice", visibility: "public")
    ]
    io = StringIO.new
    NodeIO.write(nodes, io)
    io.rewind
    read = NodeIO.read(io)
    assert_equal 2, read.size
    assert_equal "Invoice", read[0].name
    assert_equal "total", read[1].name
  end
end
