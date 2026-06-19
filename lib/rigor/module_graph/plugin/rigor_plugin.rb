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
      NODE_RULE = "node"
      private_constant :EDGE_RULE, :NODE_RULE

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
          "include_constant_refs" => { kind: :boolean, default: false },
          "emit_node_metadata" => { kind: :boolean, default: true },
          "emit_associations" => { kind: :boolean, default: true }
        }
      )

      # Pre-walk each file once to record per-DefNode visibility.
      # Shared across all node_rule invocations for the same file.
      node_file_context do |root, _scope|
        VisibilityMap.build(root)
      end

      node_rule Prism::ClassNode do |node, scope, path, file_context, context|
        analyzer = analyzer_for(scope, path, context, file_context)
        diagnostics = analyzer.class_edges(node).map { |edge| edge_diagnostic(edge, node) }
        if config["emit_node_metadata"]
          if (meta = analyzer.class_node_metadata(node))
            diagnostics << node_diagnostic(meta, node)
          end
        end
        diagnostics
      end

      node_rule Prism::ModuleNode do |node, scope, path, file_context, context|
        analyzer = analyzer_for(scope, path, context, file_context)
        diagnostics = []
        if config["emit_node_metadata"]
          if (meta = analyzer.module_node_metadata(node))
            diagnostics << node_diagnostic(meta, node)
          end
        end
        diagnostics
      end

      node_rule Prism::CallNode do |node, scope, path, file_context, context|
        analyzer = analyzer_for(scope, path, context, file_context)
        diagnostics = analyzer.call_edges(node).map { |edge| edge_diagnostic(edge, node) }
        if config["emit_associations"]
          analyzer.association_edges(node).each do |edge|
            diagnostics << edge_diagnostic(edge, node)
          end
        end
        if config["emit_node_metadata"]
          analyzer.attribute_nodes(node).each do |meta|
            diagnostics << node_diagnostic(meta, node)
          end
        end
        diagnostics
      end

      node_rule Prism::DefNode do |node, scope, path, file_context, context|
        next [] unless config["emit_node_metadata"]

        analyzer = analyzer_for(scope, path, context, file_context)
        if (meta = analyzer.method_node_metadata(node))
          [node_diagnostic(meta, node)]
        else
          []
        end
      end

      node_rule Prism::ConstantReadNode do |node, scope, path, file_context, context|
        next [] unless config["include_constant_refs"]

        analyzer = analyzer_for(scope, path, context, file_context)
        analyzer.constant_read_edges(node).map { |edge| edge_diagnostic(edge, node) }
      end

      node_rule Prism::ConstantPathNode do |node, scope, path, file_context, context|
        next [] unless config["include_constant_refs"]

        analyzer = analyzer_for(scope, path, context, file_context)
        analyzer.constant_path_edges(node).map { |edge| edge_diagnostic(edge, node) }
      end

      def analyzer_for(scope, path, context, visibility_map)
        Analyzer.new(
          path: path,
          context: context,
          scope: scope,
          zeitwerk: zeitwerk_resolver,
          visibility_map: visibility_map
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

      def node_diagnostic(meta, ast_node)
        diagnostic(
          ast_node,
          path: meta.path,
          message: JSON.generate(meta.to_message_payload),
          severity: :info,
          rule: NODE_RULE
        )
      end
    end

    ::Rigor::Plugin.register(Plugin)
  end
end
