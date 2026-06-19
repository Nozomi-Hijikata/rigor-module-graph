# frozen_string_literal: true

require "prism"
require_relative "constant_name"
require_relative "edge"

module Rigor
  module ModuleGraph
    # Per-node edge extractor. One instance per `node_rule`
    # invocation; the plugin builds it with the current path and
    # `NodeContext`, then asks for `*_edges(node)`.
    class Analyzer
      MIXIN_METHODS = %i[include prepend extend].freeze

      attr_reader :path, :context

      def initialize(path:, context:)
        @path = path
        @context = context
      end

      # Emits an `inherits` edge when the class declares a
      # superclass. The owner combines the lexical ancestor chain
      # with the class's own constant path (so `module A; class
      # B::C` resolves to `A::B::C`).
      def class_edges(node)
        owner = owner_for_decl(node)
        return [] unless owner

        superclass_name = ConstantName.render(node.superclass)
        return [] unless superclass_name

        [
          Edge.build(
            from: owner,
            to: superclass_name,
            kind: "inherits",
            path: path,
            line: line_of(node),
            column: column_of(node)
          )
        ]
      end

      # Modules don't introduce dependency edges by themselves —
      # the include/prepend/extend calls inside them do, and those
      # are caught by `Prism::CallNode`. Returns an empty array so
      # the plugin's `Prism::ModuleNode` rule can stay symmetric
      # with the class rule.
      def module_edges(_node)
        []
      end

      # Emits `include` / `prepend` / `extend` edges for a call
      # whose method name is one of `MIXIN_METHODS`. Skips the call
      # when no class/module encloses it (top-level `include` on
      # Object is rare and adds noise to the graph).
      def call_edges(node)
        return [] unless mixin_call?(node)

        owner = ConstantName.lexical_owner(context)
        return [] unless owner

        kind = node.name.to_s
        arguments_of(node).filter_map do |arg|
          target = ConstantName.render(arg)
          next unless target

          Edge.build(
            from: owner,
            to: target,
            kind: kind,
            path: path,
            line: line_of(node),
            column: column_of(node)
          )
        end
      end

      def mixin_call?(node)
        MIXIN_METHODS.include?(node.name) && node.receiver.nil?
      end

      def arguments_of(node)
        node.arguments ? node.arguments.arguments : []
      end

      def owner_for_decl(node)
        own = ConstantName.render(node.constant_path)
        ConstantName.lexical_owner_with(context, own)
      end

      def line_of(node)
        node.location&.start_line
      end

      def column_of(node)
        # Prism returns 0-based start_column; downstream tooling
        # and diagnostic JSON expect 1-based columns to match how
        # editors render positions.
        col = node.location&.start_column
        col.nil? ? nil : col + 1
      end
    end
  end
end
