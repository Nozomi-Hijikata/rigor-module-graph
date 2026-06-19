# frozen_string_literal: true

require "prism"

module Rigor
  module ModuleGraph
    # Resolves a fully-qualified constant name from Prism AST nodes
    # and lexical ancestor chains.
    #
    # Three things this module handles that the bare Prism API does
    # not give you in one place:
    #
    # - Owner from lexical nesting. `node.constant_path.full_name`
    #   on a `class Billing::Invoice` only returns `"Invoice"`; the
    #   outer `module Billing` does not enter unless we walk
    #   ancestors ourselves.
    # - Absolute paths (`::Foo::Bar`). Prism encodes the leading
    #   `::` as an empty-symbol `:""` in `full_name_parts`; we
    #   render it as `"::Foo::Bar"`.
    # - Mixed AST shapes. `ClassNode#constant_path` is either a
    #   `ConstantReadNode` (single name) or a `ConstantPathNode`
    #   (dotted path); same for `superclass` and `include` args.
    module ConstantName
      module_function

      # Render a single Prism constant node into a string like
      # `"Foo"`, `"Foo::Bar"`, or `"::Foo::Bar"`. Returns nil when
      # the node is not a constant carrier (e.g. `include SOME_VAR`
      # where the arg is a `CallNode`).
      def render(node)
        case node
        when Prism::ConstantReadNode
          node.name.to_s
        when Prism::ConstantPathNode
          full_name_for_path(node)
        end
      end

      # Build the lexical-nesting owner string for a node, by
      # walking `context.ancestors` from outer to inner and joining
      # every enclosing `ClassNode`/`ModuleNode` constant path with
      # `::`. Returns nil when no class/module encloses the node.
      def lexical_owner(context)
        parts = lexical_parts(context.ancestors)
        return nil if parts.empty?

        parts.join("::")
      end

      # Same as `#lexical_owner`, but with `extra` appended as the
      # innermost element. Used to build the owner of a class or
      # module decl itself: pass `context.ancestors` (which does NOT
      # include the node itself) plus the node's own constant path.
      def lexical_owner_with(context, extra)
        parts = lexical_parts(context.ancestors)
        parts << extra unless extra.nil? || extra.empty?
        return nil if parts.empty?

        parts.join("::")
      end

      def lexical_parts(ancestors)
        ancestors.flat_map do |ancestor|
          case ancestor
          when Prism::ClassNode, Prism::ModuleNode
            name = render(ancestor.constant_path)
            name ? [name] : []
          else
            []
          end
        end
      end

      def full_name_for_path(node)
        parts = node.full_name_parts
        # Prism encodes a leading `::` as an empty-symbol first
        # part. Render it as a literal `"::"` prefix.
        if parts.first == :""
          "::" + parts.drop(1).join("::")
        else
          parts.join("::")
        end
      end
    end
  end
end
