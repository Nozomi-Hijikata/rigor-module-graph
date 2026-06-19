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

  def test_indirect_mixin_argument_is_ignored
    # `include some_variable` has no constant carrier; we drop it
    # rather than emit an unresolved edge in MVP. Phase 3 may
    # promote this through scope.type_of.
    edges = analyze(<<~RUBY)
      class Foo
        include some_variable
      end
    RUBY
    assert_empty edges
  end

  def analyze(source, path: "test.rb")
    results = []
    PrismAncestors.each_node(source) do |node, ancestors|
      analyzer = Analyzer.new(path: path, context: FakeNodeContext.new(ancestors))
      results.concat(analyzer.class_edges(node)) if node.is_a?(Prism::ClassNode)
      results.concat(analyzer.module_edges(node)) if node.is_a?(Prism::ModuleNode)
      results.concat(analyzer.call_edges(node)) if node.is_a?(Prism::CallNode)
    end
    results
  end
end
