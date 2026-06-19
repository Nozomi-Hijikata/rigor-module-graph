# frozen_string_literal: true

module Rigor
  module ModuleGraph
    # Renders an array of Edges as a Graphviz DOT document.
    #
    # Style decisions (per plan.md "グラフモデル"):
    # - rankdir=LR for readability of inheritance towers
    # - inherits: thick solid
    # - include: solid
    # - prepend: solid, distinct color
    # - extend: dashed
    # - const_ref: faded dotted
    #
    # When `collapse:` is given, every node whose fully-qualified
    # name sits under one of the listed prefixes is wrapped in a
    # `subgraph cluster_<prefix>` block, and the prefix is stripped
    # from the visible label. Edges across clusters render normally;
    # Graphviz routes them between the cluster boundaries.
    module Dot
      module_function

      KIND_STYLE = {
        "inherits" => 'color="#0f172a", penwidth=2.0',
        "include" => 'color="#1d4ed8"',
        "prepend" => 'color="#9333ea"',
        "extend" => 'color="#0f766e", style="dashed"',
        "const_ref" => 'color="#94a3b8", style="dotted"'
      }.freeze

      CONFIDENCE_STYLE = {
        "unresolved" => 'style="dashed", color="#94a3b8"'
      }.freeze

      HEADER = <<~DOT
        digraph ruby_modules {
          rankdir=LR;
          graph [compound=true, overlap=false, splines=true];
          node [shape=box, style="rounded,filled", fillcolor="#f8fafc", color="#94a3b8", fontname="Helvetica"];
          edge [color="#64748b", arrowsize=0.7, fontname="Helvetica"];
      DOT

      def render(edges, collapse: [])
        edges = dedup(edges)
        nodes = collect_nodes(edges)
        clusters, ungrouped = group_nodes(nodes, collapse)

        out = +HEADER
        clusters.each do |prefix, members|
          out << render_cluster(prefix, members)
        end
        ungrouped.each do |name|
          out << "  #{quote(name)};\n"
        end
        out << "\n" unless nodes.empty?
        edges.each do |edge|
          out << render_edge(edge)
        end
        out << "}\n"
      end

      def dedup(edges)
        seen = {}
        edges.each_with_object([]) do |edge, acc|
          key = edge.dedup_key
          next if seen[key]

          seen[key] = true
          acc << edge
        end
      end

      def collect_nodes(edges)
        names = edges.flat_map { |edge| [edge.from, edge.to] }
        names.uniq.sort
      end

      # Partition nodes into clusters keyed by the matched prefix,
      # plus a list of names that didn't match any prefix.
      def group_nodes(nodes, collapse)
        prefixes = Array(collapse).map(&:to_s).reject(&:empty?)
        return [{}, nodes] if prefixes.empty?

        sorted = prefixes.sort_by { |p| -p.length }
        clusters = Hash.new { |h, k| h[k] = [] }
        ungrouped = []
        nodes.each do |name|
          match = sorted.find { |p| name.start_with?(p + "::") }
          if match
            clusters[match] << name
          else
            ungrouped << name
          end
        end
        [clusters, ungrouped]
      end

      def render_cluster(prefix, members)
        out = +"  subgraph #{quote("cluster_" + cluster_id(prefix))} {\n"
        out << "    label=#{quote(prefix)};\n"
        out << "    style=\"rounded,filled\";\n"
        out << "    color=\"#cbd5e1\";\n"
        out << "    fillcolor=\"#f1f5f9\";\n"
        members.each do |name|
          short = name.sub(/\A#{Regexp.escape(prefix)}::/, "")
          out << "    #{quote(name)} [label=#{quote(short)}];\n"
        end
        out << "  }\n"
      end

      def cluster_id(prefix)
        prefix.gsub("::", "_")
      end

      def render_edge(edge)
        attrs = +"label=\"#{edge.kind}\""
        if (style = KIND_STYLE[edge.kind])
          attrs << ", " << style
        end
        if (style = CONFIDENCE_STYLE[edge.confidence])
          attrs << ", " << style
        end
        "  #{quote(edge.from)} -> #{quote(edge.to)} [#{attrs}];\n"
      end

      def quote(name)
        # DOT identifiers that contain `::` or quotes must be
        # double-quoted; escape embedded double quotes.
        '"' + name.gsub('"', '\"') + '"'
      end
    end
  end
end
