# frozen_string_literal: true

require "prism"

module Rigor
  module ModuleGraph
    # Pre-walks a Prism tree once and records each +DefNode+'s
    # effective visibility based on the running +public+ /
    # +protected+ / +private+ marker calls inside its enclosing
    # class / module body.
    #
    # The Analyzer's per-node rules can then look up a visibility
    # in O(1) without re-walking the surrounding body. Built once
    # per file by the plugin's +node_file_context+ hook.
    #
    # Limitations (acknowledged):
    #
    # * +private :foo+ (explicit symbol form) is ignored; only the
    #   bare keyword that flips the running visibility is honoured.
    #   The bare form covers ~90% of Ruby; the symbol form mostly
    #   shows up in DSL-generated method blocks.
    # * +private_class_method+ and singleton-class blocks
    #   (+class << self+) are not interpreted.
    # * Methods inside a +class+ inside a method body (rare) stay
    #   at +public+.
    class VisibilityMap
      VISIBILITY_MARKERS = %i[public protected private].freeze

      def initialize
        @table = {}.compare_by_identity
      end

      # @param root [Prism::Node]
      # @return [VisibilityMap]
      def self.build(root)
        map = new
        walk_top_level(root, map) if root
        map
      end

      def visibility_for(node)
        @table[node]
      end

      def self.walk_top_level(node, map)
        return unless node.is_a?(Prism::Node)

        # The top level is a module-like scope; defs there read as
        # public. Modules nested below get their own pass with the
        # visibility reset to public.
        case node
        when Prism::ProgramNode
          walk_top_level(node.statements, map)
        when Prism::StatementsNode
          node.body.each { |child| walk_top_level(child, map) }
        when Prism::ClassNode, Prism::ModuleNode
          walk_body(node, map)
        end
      end

      def self.walk_body(class_or_module, map)
        body = class_or_module.body
        statements = body.respond_to?(:body) ? Array(body.body) : []
        current = "public"

        statements.each do |stmt|
          case stmt
          when Prism::CallNode
            if VISIBILITY_MARKERS.include?(stmt.name) && bare_marker?(stmt)
              current = stmt.name.to_s
            end
          when Prism::DefNode
            map.record(stmt, current)
          when Prism::ClassNode, Prism::ModuleNode
            walk_body(stmt, map)
          end
        end
      end

      def self.bare_marker?(call_node)
        call_node.receiver.nil? &&
          (call_node.arguments.nil? || call_node.arguments.arguments.empty?)
      end

      def record(node, visibility)
        @table[node] = visibility
      end
    end
  end
end
