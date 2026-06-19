# frozen_string_literal: true

require_relative "../../test_helper"

class AnalyzerTest < Minitest::Test
  Analyzer = Rigor::ModuleGraph::Analyzer

  def test_class_inherits_with_lexical_owner
    edges = analyze(<<~RUBY)
      module Billing
        class Invoice < ApplicationRecord
        end
      end
    RUBY
    inherits = edges.select { |e| e.kind == "inherits" }
    assert_equal 1, inherits.size
    assert_equal "Billing::Invoice", inherits.first.from
    assert_equal "ApplicationRecord", inherits.first.to
  end

  def test_class_with_explicit_namespace_path_still_includes_outer_module
    edges = analyze(<<~RUBY)
      module Billing
        class Invoice::Line < ApplicationRecord
        end
      end
    RUBY
    inherits = edges.select { |e| e.kind == "inherits" }
    assert_equal "Billing::Invoice::Line", inherits.first.from
  end

  def test_class_without_superclass_emits_no_inherits_edge
    edges = analyze(<<~RUBY)
      class Foo
      end
    RUBY
    assert_empty edges.select { |e| e.kind == "inherits" }
  end

  def test_include_prepend_extend_edges
    edges = analyze(<<~RUBY)
      class Foo
        include Bar
        prepend Baz
        extend Qux
      end
    RUBY
    kinds = edges.map(&:kind).sort
    assert_equal %w[extend include prepend], kinds
    edges.each do |edge|
      assert_equal "Foo", edge.from
    end
    assert_equal "Bar", edges.find { |e| e.kind == "include" }.to
    assert_equal "Baz", edges.find { |e| e.kind == "prepend" }.to
    assert_equal "Qux", edges.find { |e| e.kind == "extend" }.to
  end

  def test_multi_arg_include
    edges = analyze(<<~RUBY)
      class Foo
        include Bar, Baz::Qux
      end
    RUBY
    targets = edges.select { |e| e.kind == "include" }.map(&:to).sort
    assert_equal ["Bar", "Baz::Qux"], targets
  end

  def test_skips_mixin_call_with_explicit_receiver
    # `self.include Foo` and `Other.include Foo` look like mixin
    # calls but are routed through a different receiver and should
    # not contribute to the module's own include chain.
    edges = analyze(<<~RUBY)
      class Foo
        self.include Bar
        Other.include Baz
      end
    RUBY
    assert_empty edges
  end

  def test_skips_mixin_call_at_top_level
    edges = analyze(<<~RUBY)
      include Foo
    RUBY
    assert_empty edges
  end

  def test_indirect_mixin_argument_emits_unresolved_edge
    # `include some_variable` has no constant carrier and (in
    # unit tests) no Rigor scope to consult — we record the call
    # as an `unresolved` edge so the graph still shows the
    # reference, with `raw` preserving the source slice.
    edges = analyze(<<~RUBY)
      class Foo
        include some_variable
      end
    RUBY
    assert_equal 1, edges.size
    edge = edges.first
    assert_equal "Foo", edge.from
    assert_equal "some_variable", edge.to
    assert_equal "include", edge.kind
    assert_equal "unresolved", edge.confidence
    assert_equal "some_variable", edge.raw
  end

  def test_const_ref_inside_def_body
    edges = analyze_with_const_refs(<<~RUBY)
      class Invoice
        def total
          Money.new(0)
        end
      end
    RUBY
    refs = edges.select { |e| e.kind == "const_ref" }
    assert_equal 1, refs.size
    assert_equal "Invoice", refs.first.from
    assert_equal "Money", refs.first.to
  end

  def test_const_ref_path_emits_once_outer_only
    # `Foo::Bar::Baz` is one ConstantPathNode wrapping nested
    # ConstantPathNodes. Only the outer one should fire so we
    # don't multi-count `Foo::Bar` and `Foo` as separate refs.
    edges = analyze_with_const_refs(<<~RUBY)
      class Invoice
        def lookup
          Foo::Bar::Baz
        end
      end
    RUBY
    refs = edges.select { |e| e.kind == "const_ref" }
    assert_equal 1, refs.size
    assert_equal "Foo::Bar::Baz", refs.first.to
  end

  def test_const_ref_skips_class_header_constants
    # ApplicationRecord and Auditable in the header positions
    # already produce inherits / include edges; const_ref must
    # not double-count them.
    edges = analyze_with_const_refs(<<~RUBY)
      class Invoice < ApplicationRecord
        include Auditable

        def total
          Money.new
        end
      end
    RUBY
    refs = edges.select { |e| e.kind == "const_ref" }
    assert_equal ["Money"], refs.map(&:to)
  end

  def test_const_ref_skips_top_level_refs
    edges = analyze_with_const_refs(<<~RUBY)
      module Toplevel
        CONST = SomeOther
      end
    RUBY
    refs = edges.select { |e| e.kind == "const_ref" }
    # Top-level (not inside def): skipped to avoid noise from DSL
    # config blocks.
    assert_empty refs
  end

  def analyze(source, path: "test.rb")
    analyze_inner(source, path: path, include_constant_refs: false)
  end

  def analyze_with_const_refs(source, path: "test.rb")
    analyze_inner(source, path: path, include_constant_refs: true)
  end

  def analyze_inner(source, path:, include_constant_refs:)
    results = []
    PrismAncestors.each_node(source) do |node, ancestors|
      analyzer = Analyzer.new(path: path, context: FakeNodeContext.new(ancestors))
      results.concat(analyzer.class_edges(node)) if node.is_a?(Prism::ClassNode)
      results.concat(analyzer.module_edges(node)) if node.is_a?(Prism::ModuleNode)
      results.concat(analyzer.call_edges(node)) if node.is_a?(Prism::CallNode)
      if include_constant_refs
        results.concat(analyzer.constant_read_edges(node)) if node.is_a?(Prism::ConstantReadNode)
        results.concat(analyzer.constant_path_edges(node)) if node.is_a?(Prism::ConstantPathNode)
      end
    end
    results
  end
end
