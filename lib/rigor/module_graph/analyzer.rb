# frozen_string_literal: true

require "prism"
require_relative "constant_name"
require_relative "edge"
require_relative "node"
require_relative "zeitwerk_resolver"
require_relative "inflector"

module Rigor
  module ModuleGraph
    # Per-node edge extractor. One instance per `node_rule`
    # invocation; the plugin builds it with the current path,
    # NodeContext, scope, and (optional) Zeitwerk resolver, then
    # asks for `*_edges(node)`.
    #
    # Confidence ladder per edge:
    #
    # - `zeitwerk` when the owner's lexical name matches the
    #   path-inferred name (Phase 2).
    # - `rigor_type` when a mixin arg is a non-constant whose
    #   `scope.type_of` is a Singleton — we read its `class_name`
    #   instead of dropping the edge (Phase 3).
    # - `unresolved` when scope.type_of declines but we still want
    #   to record that *something* was referenced.
    # - `syntax` otherwise.
    class Analyzer
      MIXIN_METHODS = %i[include prepend extend].freeze
      ATTR_METHODS = {
        attr_reader: "read",
        attr_writer: "write",
        attr_accessor: "accessor"
      }.freeze
      ASSOCIATION_METHODS = {
        has_many: "has_many",
        belongs_to: "belongs_to",
        has_one: "has_one",
        has_and_belongs_to_many: "has_and_belongs_to_many"
      }.freeze
      VISIBILITY_MARKERS = %i[public protected private].freeze

      attr_reader :path, :context, :scope, :zeitwerk, :visibility_map

      def initialize(path:, context:, scope: nil, zeitwerk: nil, visibility_map: nil)
        @path = path
        @context = context
        @scope = scope
        @zeitwerk = zeitwerk
        @visibility_map = visibility_map
      end

      # Emits an `inherits` edge when the class declares a
      # superclass. The owner combines the lexical ancestor chain
      # with the class's own constant path (so `module A; class
      # B::C` resolves to `A::B::C`). Confidence is elevated to
      # `zeitwerk` when the path-inferred name matches.
      def class_edges(node)
        owner = owner_for_decl(node)
        return [] unless owner

        superclass_name = ConstantName.render(node.superclass)
        return [] unless superclass_name

        [build_edge(
          from: owner, to: superclass_name, kind: "inherits", node: node
        )]
      end

      # Modules don't introduce dependency edges by themselves —
      # the include/prepend/extend calls inside them do, and those
      # are caught by `Prism::CallNode`. Returns an empty array so
      # the plugin's `Prism::ModuleNode` rule can stay symmetric
      # with the class rule.
      def module_edges(_node)
        []
      end

      # Phase 5a — a Node row for the class declaration itself.
      # Used by the plugin's +rule: "node"+ diagnostic emitter so
      # downstream tooling can list classes by file / line.
      def class_node_metadata(node)
        owner = owner_for_decl(node)
        return nil unless owner

        Node.build(
          kind: "class", name: owner,
          path: path, line: line_of(node), column: column_of(node)
        )
      end

      # Phase 5a — a Node row for the module declaration.
      def module_node_metadata(node)
        owner = owner_for_decl(node)
        return nil unless owner

        Node.build(
          kind: "module", name: owner,
          path: path, line: line_of(node), column: column_of(node)
        )
      end

      # Phase 5a — a Node row for a +def+ / +def self.+. Reads
      # visibility from the +VisibilityMap+ when one is wired in;
      # defaults to +public+ otherwise.
      def method_node_metadata(node)
        owner = ConstantName.lexical_owner(context)
        return nil unless owner

        Node.build(
          kind: node.receiver.nil? ? "instance_method" : "class_method",
          name: node.name.to_s,
          owner: owner,
          visibility: visibility_for(node),
          path: path, line: line_of(node), column: column_of(node)
        )
      end

      # Phase 5a — Node rows for +attr_reader+ / +attr_writer+ /
      # +attr_accessor+ calls. One Node per symbol argument.
      def attribute_nodes(node)
        access = ATTR_METHODS[node.name]
        return [] unless access
        return [] unless node.receiver.nil?

        owner = ConstantName.lexical_owner(context)
        return [] unless owner

        # Inside a class body the running visibility is what the
        # bare keyword markers set. We approximate by reading the
        # nearest enclosing def-or-attr-marker's visibility — but
        # attr_* calls are sibling statements, not nested defs, so
        # we fall back to public unless the class body's visibility
        # tracker covers them. For MVP we record public; the
        # filter side still excludes private nodes when callers
        # add visibility tracking later.
        attr_visibility = visibility_for(node) || "public"

        arguments_of(node).filter_map do |arg|
          name = symbol_name(arg)
          next unless name

          Node.build(
            kind: "attribute", name: name, owner: owner,
            visibility: attr_visibility, access: access,
            path: path, line: line_of(node), column: column_of(node)
          )
        end
      end

      # Phase 5b — Rails ActiveRecord association edges. For
      # +has_many :invoices+ we infer +Invoice+ via the bundled
      # Inflector; +class_name: "Foo"+ overrides win when present.
      def association_edges(node)
        kind = ASSOCIATION_METHODS[node.name]
        return [] unless kind
        return [] unless node.receiver.nil?

        owner = ConstantName.lexical_owner(context)
        return [] unless owner

        arguments_of(node).filter_map do |arg|
          next unless (sym = symbol_name(arg))

          target = class_name_from_options(node) ||
                   Inflector.class_name_for(sym)
          build_edge(
            from: owner, to: target, kind: kind, node: node,
            confidence: :syntax,
            raw: sym
          )
        end
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
        arguments_of(node).flat_map do |arg|
          build_mixin_edges(owner: owner, kind: kind, arg: arg, node: node)
        end
      end

      # Phase 2c: a `const_ref` edge for a bare constant read
      # inside a method body. The plugin gates on
      # `include_constant_refs`, so this method assumes the caller
      # already decided to look at constant nodes.
      def constant_read_edges(node)
        return [] unless emit_const_ref?(node)
        # The leftmost name of `Foo::Bar::Baz` is a
        # ConstantReadNode wrapped by the outer ConstantPathNode.
        # The path's own rule covers it, so we skip here.
        return [] if parent_is_constant_path?(node)

        owner = ConstantName.lexical_owner(context)
        return [] unless owner

        [build_edge(
          from: owner,
          to: node.name.to_s,
          kind: "const_ref",
          node: node
        )]
      end

      # Phase 2c: a `const_ref` edge for a `Foo::Bar` reference
      # inside a method body. We only fire on the outermost path
      # — Prism nests a `ConstantPathNode(:Bar)` inside `Foo`'s
      # own `ConstantPathNode`, and we'd double-count if we
      # emitted from both.
      def constant_path_edges(node)
        return [] unless emit_const_ref?(node)
        return [] if parent_is_constant_path?(node)

        owner = ConstantName.lexical_owner(context)
        return [] unless owner

        target = ConstantName.render(node)
        return [] unless target

        [build_edge(
          from: owner, to: target, kind: "const_ref", node: node
        )]
      end

      def build_mixin_edges(owner:, kind:, arg:, node:)
        if (target = ConstantName.render(arg))
          [build_edge(
            from: owner, to: target, kind: kind, node: node
          )]
        else
          resolved = resolve_via_scope(arg)
          if resolved
            [build_edge(
              from: owner, to: resolved, kind: kind, node: node,
              confidence: :rigor_type, raw: arg_source(arg)
            )]
          else
            unresolved_label = arg_source(arg)
            return [] unless unresolved_label

            [build_edge(
              from: owner,
              to: unresolved_label,
              kind: kind,
              node: node,
              confidence: :unresolved,
              raw: unresolved_label
            )]
          end
        end
      end

      def resolve_via_scope(arg)
        return nil unless scope.respond_to?(:type_of)

        type = scope.type_of(arg)
        return nil if type.nil?

        if defined?(::Rigor::Type::Singleton) && type.is_a?(::Rigor::Type::Singleton)
          type.class_name
        end
      rescue StandardError
        nil
      end

      def arg_source(arg)
        loc = arg.location
        return nil unless loc

        loc.slice
      rescue StandardError
        nil
      end

      def mixin_call?(node)
        MIXIN_METHODS.include?(node.name) && node.receiver.nil?
      end

      def symbol_name(arg)
        case arg
        when Prism::SymbolNode
          arg.value
        when Prism::StringNode
          arg.unescaped
        end
      end

      # Pulls +class_name: "Foo"+ (or +:Foo+) out of the keyword
      # arguments on an association call. Returns nil when absent.
      def class_name_from_options(node)
        args = arguments_of(node)
        keyword_hash = args.find { |a| a.is_a?(Prism::KeywordHashNode) || a.is_a?(Prism::HashNode) }
        return nil unless keyword_hash

        keyword_hash.elements.each do |elem|
          next unless elem.is_a?(Prism::AssocNode)

          key = elem.key
          next unless key.is_a?(Prism::SymbolNode) && key.value == "class_name"

          value = elem.value
          return value.unescaped if value.is_a?(Prism::StringNode)
          return value.value.to_s if value.is_a?(Prism::SymbolNode)
        end
        nil
      end

      def visibility_for(node)
        return nil unless visibility_map

        visibility_map.visibility_for(node)
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

      def build_edge(from:, to:, kind:, node:, confidence: :syntax, raw: nil)
        # Caller's confidence is the floor — we may bump it up
        # when Zeitwerk agrees with the owner's lexical name. We
        # never demote.
        effective = confidence == :syntax ? zeitwerk_confidence(from) : confidence
        Edge.build(
          from: from,
          to: to,
          kind: kind,
          path: path,
          line: line_of(node),
          column: column_of(node),
          confidence: effective.to_s,
          raw: raw
        )
      end

      # Returns :zeitwerk when the path-inferred constant for the
      # current file matches the lexical owner, :syntax otherwise.
      # The resolver is optional — when no Zeitwerk config is in
      # play we just stay at :syntax.
      def zeitwerk_confidence(owner)
        return :syntax unless zeitwerk
        return :syntax unless path

        inferred = zeitwerk.resolve(path)
        zeitwerk.matches?(owner, inferred) ? :zeitwerk : :syntax
      end

      def emit_const_ref?(node)
        return false unless context.respond_to?(:enclosing_def)
        return false if context.enclosing_def.nil?
        return false if inside_class_header?(node)
        return false if inside_mixin_args?(node)

        true
      end

      # Inside `class Foo < Bar; …`, Bar's ConstantReadNode is a
      # child of the ClassNode itself (constant_path / superclass
      # slots). We are walked AFTER `context.ancestors` has been
      # pushed, so the immediate parent here is the ClassNode.
      def inside_class_header?(node)
        parent = context.ancestors.last
        return false unless parent.is_a?(Prism::ClassNode) ||
                            parent.is_a?(Prism::ModuleNode)

        parent.constant_path.equal?(node) ||
          (parent.respond_to?(:superclass) && parent.superclass.equal?(node))
      end

      # `include Foo` / `prepend Foo` / `extend Foo` — Foo's
      # ConstantReadNode is reached after the include CallNode is
      # on the ancestor stack. Walk up looking for a recent mixin
      # CallNode where this node sits inside its arguments.
      def inside_mixin_args?(node)
        target = node
        context.ancestors.reverse_each do |ancestor|
          if ancestor.is_a?(Prism::CallNode) && mixin_call?(ancestor)
            args = arguments_of(ancestor)
            return true if args.any? { |a| contains_node?(a, target) }
          end
          # Stop at the first class / module / def boundary so we
          # don't accidentally bleed into a containing decl.
          break if ancestor.is_a?(Prism::ClassNode) ||
                   ancestor.is_a?(Prism::ModuleNode) ||
                   ancestor.is_a?(Prism::DefNode)
        end
        false
      end

      def contains_node?(haystack, needle)
        return true if haystack.equal?(needle)
        return false unless haystack.is_a?(Prism::Node)

        haystack.compact_child_nodes.any? { |child| contains_node?(child, needle) }
      end

      def parent_is_constant_path?(node)
        parent = context.ancestors.last
        parent.is_a?(Prism::ConstantPathNode) && parent.parent.equal?(node)
      end
    end
  end
end
