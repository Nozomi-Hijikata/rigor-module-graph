# frozen_string_literal: true

require "erb"
require "json"

module Rigor
  module ModuleGraph
    # Interactive viewer that replaces the static-Mermaid HTML
    # for `view --output html`. The output is a self-contained
    # HTML file: vendored `cytoscape.min.js` is inlined alongside
    # our ~100-line init script and the node / edge dataset, so
    # the artefact opens in any browser without a network round
    # trip. See `docs/plan.md` "2D interactive viewer" for the
    # supply-chain rationale.
    module Viewer
      module Html
        module_function

        TEMPLATE_DIR = File.expand_path("../templates", __dir__)
        TEMPLATE_PATH = File.join(TEMPLATE_DIR, "viewer.html.erb")
        CSS_PATH = File.join(TEMPLATE_DIR, "viewer.css")
        VIEWER_JS_PATH = File.join(TEMPLATE_DIR, "viewer.js")
        CYTOSCAPE_JS_PATH = File.join(TEMPLATE_DIR, "vendor", "cytoscape.min.js")

        # Node kinds that map to top-level Cytoscape nodes.
        # Method / attribute nodes are out of scope for the graph
        # viewer (they belong to the class diagram, not the
        # dependency graph).
        CONSTANT_KINDS = %w[class module].freeze

        # @param edges [Array<Edge>] dependency edges
        # @param nodes [Array<Node>] node metadata (for click-through)
        # @param title [String] page title
        # @param subtitle [String, nil] optional subtitle line
        # @param path_mode [:relative, :absolute, :none]
        #   how `data.path` is reported to click handlers. `:none`
        #   strips it entirely so HTML shared externally doesn't
        #   leak filesystem layout.
        # @param open_with [Symbol, nil] when `:vscode`, node click
        #   opens `vscode://file/<path>:<line>` instead of writing
        #   to clipboard.
        # @param collapse [Array<String>] namespace prefixes to
        #   wrap as Cytoscape compound nodes. Same shape as the
        #   list `Mermaid.render` / `Dot.render` accept. Used by
        #   the auto-collapse heuristic in `View`.
        # @param groups [Hash{String=>String}, nil] explicit
        #   node-name → cluster-label mapping. Takes precedence
        #   over `collapse` when given. Drives the `--package`
        #   Packwerk overlay.
        # @return [String] complete HTML document
        def render(edges:, nodes:, title:, subtitle: nil,
                   path_mode: :relative, open_with: nil,
                   collapse: [], groups: nil)
          data = build_data(
            edges: edges, nodes: nodes,
            path_mode: path_mode, open_with: open_with,
            collapse: collapse, groups: groups
          )
          template = ERB.new(File.read(TEMPLATE_PATH), trim_mode: "-")
          template.result_with_hash(
            title: title,
            subtitle: subtitle,
            data_json: safe_json(data),
            css: File.read(CSS_PATH),
            cytoscape: File.read(CYTOSCAPE_JS_PATH),
            viewer: File.read(VIEWER_JS_PATH)
          )
        end

        # Builds the `{nodes:, edges:, options:}` payload the
        # inline init JS reads from
        # `<script type="application/json" id="rmg-data">`.
        def build_data(edges:, nodes:, path_mode:, open_with:,
                       collapse: [], groups: nil)
          # Decide each node's parent compound (if any) before
          # walking the node / edge sets, so member nodes can
          # have their visible label shortened to drop the
          # namespace prefix.
          parent_for = compute_parents(edges, nodes, collapse, groups)

          node_meta = build_node_meta(nodes, parent_for, path_mode)
          add_external_endpoints(node_meta, edges, parent_for)

          # Cytoscape treats any node referenced as a `parent` as
          # a compound (group) automatically. We still emit an
          # explicit entry per compound so it gets a label and
          # `kind: "compound"` styling — and so the JSON dataset
          # is self-contained for debugging.
          compound_nodes = parent_for.values.uniq.compact.map do |label|
            { data: { id: label, name: label, kind: "compound" } }
          end

          {
            # Compound nodes first so Cytoscape sees the parents
            # before their children during element registration.
            nodes: compound_nodes + node_meta.values.map { |n| { data: n } },
            edges: edges.each_with_index.map do |edge, i|
              {
                data: {
                  id: "e#{i}",
                  source: edge.from,
                  target: edge.to,
                  kind: edge.kind,
                  confidence: edge.confidence
                }
              }
            end,
            options: { open_with: open_with&.to_s }
          }
        end

        # Resolves the cluster (compound-node id) each node sits
        # in. `groups:` wins outright when given (Packwerk
        # overlay); otherwise `collapse:` prefix-matches against
        # every fully-qualified name, longest prefix first.
        def compute_parents(edges, nodes, collapse, groups)
          if groups && !groups.empty?
            groups.dup
          else
            prefixes = Array(collapse).map(&:to_s).reject(&:empty?).sort_by { |p| -p.length }
            return {} if prefixes.empty?

            all_names = collect_names(edges, nodes)
            parent_for = {}
            all_names.each do |name|
              match = prefixes.find { |p| name.start_with?("#{p}::") }
              parent_for[name] = match if match
            end
            parent_for
          end
        end

        def collect_names(edges, nodes)
          (edges.flat_map { |e| [e.from, e.to] } +
           nodes.flat_map { |n| CONSTANT_KINDS.include?(n.kind) ? [fully_qualified(n)] : [] }).uniq
        end

        def build_node_meta(nodes, parent_for, path_mode)
          meta = {}
          nodes.each do |node|
            next unless CONSTANT_KINDS.include?(node.kind)

            key = fully_qualified(node)
            # First definition wins; class re-opens still resolve
            # to one Cytoscape node, matching the dedup contract
            # in `Edge#dedup_key`.
            meta[key] ||= node_data(
              id: key, kind: node.kind,
              path: path_for(node.path, path_mode), line: node.line,
              parent_for: parent_for
            )
          end
          meta
        end

        # Every edge endpoint becomes a node, even when the
        # constant has no definition in the analysed paths
        # (e.g. `ApplicationRecord` from a Rails gem). External
        # endpoints are marked `kind: "external"` so the styling
        # can dim them.
        def add_external_endpoints(meta, edges, parent_for)
          edges.flat_map { |e| [e.from, e.to] }.uniq.each do |name|
            meta[name] ||= node_data(
              id: name, kind: "external", path: nil, line: nil,
              parent_for: parent_for
            )
          end
        end

        # Common shape: id (full constant name; Cytoscape uses
        # this to resolve edge endpoints), name (visible label,
        # stripped of the compound's namespace prefix), parent
        # (compound id, set only when grouped).
        def node_data(id:, kind:, path:, line:, parent_for:)
          parent = parent_for[id]
          data = {
            id: id,
            name: parent ? short_label(id, parent) : id,
            kind: kind,
            path: path,
            line: line
          }
          data[:parent] = parent if parent
          data
        end

        # Drop the `parent::` prefix from the visible label —
        # `Billing::Customer` inside a "Billing" compound shows
        # as just "Customer", matching how the Mermaid /
        # Graphviz cluster renderers already strip the prefix.
        def short_label(id, parent)
          id.sub(/\A#{Regexp.escape(parent)}::/, "")
        end

        def fully_qualified(node)
          owner = node.owner
          owner && !owner.empty? ? "#{owner}::#{node.name}" : node.name
        end

        def path_for(path, mode)
          return nil if path.nil? || mode == :none

          case mode
          when :absolute then File.expand_path(path)
          when :relative then path
          end
        end

        # JSON embedded in `<script>` must not contain `</` (would
        # break out of the surrounding tag). `JSON.generate` does
        # not escape it by default; rewriting the literal pair
        # `</` → `<\/` is the standard safety pass.
        def safe_json(value)
          JSON.generate(value).gsub("</", "<\\/")
        end
      end
    end
  end
end
