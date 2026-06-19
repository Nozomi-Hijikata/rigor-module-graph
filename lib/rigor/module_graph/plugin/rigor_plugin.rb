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
        description: "Extract Ruby class/module/constant dependency graph as :info diagnostics.",
        config_schema: {
          "autoload_paths" => {
            kind: :array,
            default: ZeitwerkResolver::DEFAULT_AUTOLOAD_PATHS
          },
          "concern_dirs" => {
            kind: :array,
            default: ZeitwerkResolver::DEFAULT_CONCERN_DIRS
          },
          "rails_zeitwerk" => { kind: :boolean, default: true },
          "include_constant_refs" => { kind: :boolean, default: false }
        }
      )

      node_rule Prism::ClassNode do |node, scope, path, _file_context, context|
        edges = analyzer_for(scope, path, context).class_edges(node)
        edges.map { |edge| edge_diagnostic(edge, node) }
      end

      node_rule Prism::ModuleNode do |node, scope, path, _file_context, context|
        edges = analyzer_for(scope, path, context).module_edges(node)
        edges.map { |edge| edge_diagnostic(edge, node) }
      end

      node_rule Prism::CallNode do |node, scope, path, _file_context, context|
        edges = analyzer_for(scope, path, context).call_edges(node)
        edges.map { |edge| edge_diagnostic(edge, node) }
      end

      node_rule Prism::ConstantReadNode do |node, scope, path, _file_context, context|
        next [] unless config["include_constant_refs"]

        edges = analyzer_for(scope, path, context).constant_read_edges(node)
        edges.map { |edge| edge_diagnostic(edge, node) }
      end

      node_rule Prism::ConstantPathNode do |node, scope, path, _file_context, context|
        next [] unless config["include_constant_refs"]

        edges = analyzer_for(scope, path, context).constant_path_edges(node)
        edges.map { |edge| edge_diagnostic(edge, node) }
      end

      def analyzer_for(scope, path, context)
        Analyzer.new(
          path: path,
          context: context,
          scope: scope,
          zeitwerk: zeitwerk_resolver
        )
      end

      def zeitwerk_resolver
        return @zeitwerk_resolver if defined?(@zeitwerk_resolver)

        @zeitwerk_resolver =
          if config["rails_zeitwerk"]
            ZeitwerkResolver.new(
              autoload_paths: config["autoload_paths"],
              concern_dirs: config["concern_dirs"]
            )
          end
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
