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

      def render(edges, collapse: [])
        edges = dedup(edges)
        node_ids = assign_node_ids(edges)
        clusters, ungrouped = group_nodes(node_ids.keys.sort, collapse)

        out = +"flowchart LR\n"
        clusters.each do |prefix, members|
          out << render_cluster(prefix, members, node_ids)
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

      def group_nodes(names, collapse)
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

      def render_cluster(prefix, members, node_ids)
        out = +"  subgraph #{cluster_id(prefix)} [\"#{escape_label(prefix)}\"]\n"
        members.each do |name|
          short = name.sub(/\A#{Regexp.escape(prefix)}::/, "")
          out << "    #{node_ids[name]}[\"#{escape_label(short)}\"]\n"
        end
        out << "  end\n"
      end

      def cluster_id(prefix)
        "sg_#{prefix.gsub("::", "_")}"
      end

      def escape_label(name)
        name.gsub('"', '#quot;')
      end
    end
  end
end
