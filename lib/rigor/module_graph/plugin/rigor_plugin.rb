# frozen_string_literal: true

require "json"
require "prism"

module Rigor
  module ModuleGraph
    # Rigor plugin: declares the node rules that emit class/module/
    # constant dependency edges as `:info` diagnostics. Loaded only
    # when `rigortype` is available (see `plugin.rb`).
    class Plugin < ::Rigor::Plugin::Base
      EDGE_RULE = "edge"
      private_constant :EDGE_RULE

      manifest(
        id: "module-graph",
        version: Rigor::ModuleGraph::VERSION,
        description: "Extract Ruby class/module/constant dependency graph as :info diagnostics."
      )

      node_rule Prism::ClassNode do |node, _scope, path, _file_context, context|
        edges = Analyzer.new(path: path, context: context).class_edges(node)
        edges.map { |edge| edge_diagnostic(edge, node) }
      end

      node_rule Prism::ModuleNode do |node, _scope, path, _file_context, context|
        edges = Analyzer.new(path: path, context: context).module_edges(node)
        edges.map { |edge| edge_diagnostic(edge, node) }
      end

      node_rule Prism::CallNode do |node, _scope, path, _file_context, context|
        edges = Analyzer.new(path: path, context: context).call_edges(node)
        edges.map { |edge| edge_diagnostic(edge, node) }
      end

      def edge_diagnostic(edge, node)
        diagnostic(
          node,
          path: edge.path,
          message: JSON.generate(edge.to_message_payload),
          severity: :info,
          rule: EDGE_RULE
        )
      end
    end

    ::Rigor::Plugin.register(Plugin)
  end
end
