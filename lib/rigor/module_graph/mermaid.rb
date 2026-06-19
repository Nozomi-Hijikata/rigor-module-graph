# frozen_string_literal: true

module Rigor
  module ModuleGraph
    # Renders edges as a Mermaid flowchart.
    #
    # Mermaid does not have per-edge style classes the way DOT does;
    # we use distinct arrow heads per kind (`==>`, `-->`, `-.->`)
    # plus an `:::kind` classDef on the target node so the legend is
    # readable in any Mermaid renderer.
    #
    # When `collapse:` is given, every node whose name sits under one
    # of the listed prefixes is wrapped in a `subgraph <prefix>`
    # block, with the prefix stripped from the visible label.
    module Mermaid
      module_function

      ARROW_FOR_KIND = {
        "inherits" => "==>",
        "include" => "-->",
        "prepend" => "-->",
        "extend" => "-.->",
        "const_ref" => "-.->"
      }.freeze

      CLASS_DEFS = <<~MERMAID
        classDef inherits fill:#0f172a,color:#fff,stroke:#0f172a;
        classDef include fill:#1d4ed8,color:#fff,stroke:#1d4ed8;
        classDef prepend fill:#9333ea,color:#fff,stroke:#9333ea;
        classDef extend fill:#0f766e,color:#fff,stroke:#0f766e;
        classDef const_ref fill:#cbd5e1,color:#0f172a,stroke:#94a3b8;
        classDef unresolved fill:#fef3c7,color:#0f172a,stroke:#d97706,stroke-dasharray: 4 4;
      MERMAID

      # @param edges [Array<Edge>]
      # @param collapse [Array<String>] namespace prefixes to fold
      #   into subgraphs (mutually exclusive with +groups+)
      # @param groups [Hash{String=>String}, nil] explicit
      #   +{node_name => cluster_label}+ mapping. Takes precedence
      #   over +collapse+ when given.
      def render(edges, collapse: [], groups: nil)
        edges = dedup(edges)
        node_ids = assign_node_ids(edges)
        clusters, ungrouped = build_groups(node_ids.keys.sort, collapse, groups)

        out = +"flowchart LR\n"
        clusters.each do |label, members|
          out << render_cluster(label, members, node_ids, use_namespace_prefix: groups.nil?)
        end
        ungrouped.each do |name|
          out << "  #{node_ids[name]}[\"#{escape_label(name)}\"]\n"
        end
        out << "\n" unless node_ids.empty?
        edges.each do |edge|
          arrow = ARROW_FOR_KIND.fetch(edge.kind, "-->")
          out << "  #{node_ids[edge.from]} #{arrow}|#{edge.kind}| #{node_ids[edge.to]}\n"
        end
        out << "\n"
        out << CLASS_DEFS
        # One class assignment per node id. Mermaid silently keeps
        # the last assignment but starts to error out when the same
        # `class N kind;` line repeats many hundreds of times in a
        # large graph, so we dedupe and pick the most structural
        # kind per node (inherits > include > prepend > extend >
        # const_ref) so the resulting colour conveys intent.
        out << render_class_assignments(edges, node_ids)
        out
      end

      KIND_PRIORITY = {
        "inherits" => 0,
        "include" => 1,
        "prepend" => 2,
        "extend" => 3,
        "const_ref" => 4
      }.freeze

      def render_class_assignments(edges, node_ids)
        per_node = {}
        edges.each do |edge|
          id = node_ids[edge.to]
          tag = edge.confidence == "unresolved" ? "unresolved" : edge.kind
          current = per_node[id]
          if current.nil? || better_tag?(tag, current)
            per_node[id] = tag
          end
        end
        per_node.map { |id, tag| "  class #{id} #{tag};\n" }.join
      end

      def better_tag?(candidate, current)
        return false if current == "unresolved"
        return true if candidate == "unresolved"

        (KIND_PRIORITY[candidate] || 99) < (KIND_PRIORITY[current] || 99)
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

      def assign_node_ids(edges)
        names = edges.flat_map { |edge| [edge.from, edge.to] }.uniq.sort
        names.each_with_index.to_h { |name, idx| [name, "n#{idx}"] }
      end

      def build_groups(names, collapse, groups)
        if groups && !groups.empty?
          clusters = Hash.new { |h, k| h[k] = [] }
          ungrouped = []
          names.each do |name|
            if (label = groups[name])
              clusters[label] << name
            else
              ungrouped << name
            end
          end
          [clusters, ungrouped]
        else
          group_by_prefix(names, collapse)
        end
      end

      def group_by_prefix(names, collapse)
        prefixes = Array(collapse).map(&:to_s).reject(&:empty?)
        return [{}, names] if prefixes.empty?

        sorted = prefixes.sort_by { |p| -p.length }
        clusters = Hash.new { |h, k| h[k] = [] }
        ungrouped = []
        names.each do |name|
          match = sorted.find { |p| name.start_with?(p + "::") }
          if match
            clusters[match] << name
          else
            ungrouped << name
          end
        end
        [clusters, ungrouped]
      end

      def render_cluster(label, members, node_ids, use_namespace_prefix: true)
        out = +"  subgraph #{cluster_id(label)} [\"#{escape_label(label)}\"]\n"
        members.each do |name|
          short = use_namespace_prefix ? name.sub(/\A#{Regexp.escape(label)}::/, "") : name
          out << "    #{node_ids[name]}[\"#{escape_label(short)}\"]\n"
        end
        out << "  end\n"
      end

      # Mermaid subgraph ids must be plain identifiers; anything
      # else breaks the parser silently. Coerce non-alnum
      # characters to `_` so `packages/billing` ends up as
      # `sg_packages_billing` and stays unambiguous.
      def cluster_id(prefix)
        "sg_#{prefix.gsub(/[^A-Za-z0-9_]+/, "_")}"
      end

      def escape_label(name)
        name.gsub('"', '#quot;')
      end
    end
  end
end
