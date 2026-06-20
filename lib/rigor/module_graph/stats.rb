# frozen_string_literal: true

module Rigor
  module ModuleGraph
    # Computes per-namespace dependency metrics over an edge list.
    #
    # Five numbers per namespace:
    #
    # +nodes+::      number of distinct constants in the namespace
    # +fan_out+::    edges whose +from+ is in the namespace and
    #                +to+ is outside it
    # +fan_in+::     edges whose +to+ is in the namespace and
    #                +from+ is outside it
    # +internal+::   edges where both endpoints sit in the namespace
    # +total+::      +fan_out+ + +internal+ — every edge originating
    #                in the namespace
    #
    # Grouping is by top-level namespace by default
    # (+Billing::Invoice+ → +Billing+). Pass +depth: N+ for a
    # deeper split (+Billing::Invoice::Line+ at depth 2 →
    # +Billing::Invoice+). Names without enough segments at the
    # requested depth bucket under the special label
    # +"(top-level)"+ so they stay visible in the report.
    module Stats
      module_function

      TOP_LEVEL_BUCKET = "(top-level)"

      # @param edges [Array<Edge>]
      # @param depth [Integer] number of leading +::+ segments to
      #   keep when grouping
      # @return [Array<NamespaceMetrics>] sorted by fan_out desc,
      #   then namespace asc; deterministic output.
      def compute(edges, depth: 1)
        # Single pass over edges. For each edge we resolve both
        # endpoints to a normalised name (cached), then to a
        # bucket (cached), then update the bucket's mutable
        # `[nodes_set, fan_out, fan_in, internal]` counter array.
        # Allocating one immutable `NamespaceMetrics` per edge via
        # `Data#with` is what made the old implementation slow.
        normalised = {}
        groups = {}
        counters = Hash.new { |h, k| h[k] = [{}, 0, 0, 0] }

        edges.each do |edge|
          from = (normalised[edge.from] ||= fast_normalise(edge.from))
          to = (normalised[edge.to] ||= fast_normalise(edge.to))

          from_group = (groups[from] ||= bucket_for_normalised(from, depth))
          to_group = (groups[to] ||= bucket_for_normalised(to, depth))

          from_counter = counters[from_group]
          to_counter = counters[to_group]
          from_counter[0][from] = true
          to_counter[0][to] = true

          if from_group == to_group
            from_counter[3] += 1
          else
            from_counter[1] += 1
            to_counter[2] += 1
          end
        end

        metrics = counters.map do |namespace, counter|
          NamespaceMetrics.new(
            namespace: namespace,
            nodes: counter[0].size,
            fan_out: counter[1],
            fan_in: counter[2],
            internal: counter[3]
          )
        end
        metrics.sort_by { |m| [-m.fan_out, m.namespace] }
      end

      # Strip leading "::" so absolute and relative names share
      # the same bucket / node identity — they refer to the same
      # constant either way.
      def fast_normalise(name)
        name.start_with?("::") ? name[2..] : name
      end

      # Like +bucket_for+, but skips the +split+ allocation when
      # the name has more segments than +depth+. Walks +index+
      # once per +::+ separator and slices once at the boundary.
      def bucket_for_normalised(name, depth)
        cursor = -2
        depth.times do
          cursor = name.index("::", cursor + 2)
          return TOP_LEVEL_BUCKET unless cursor
        end
        name[0...cursor]
      end

      # The five numbers for one namespace, exposed as a Data
      # value so callers can treat the result like a row of a
      # table.
      NamespaceMetrics = Data.define(:namespace, :nodes, :fan_out, :fan_in, :internal) do
        # Sum of edges originating in the namespace
        # (fan_out + internal).
        def total
          fan_out + internal
        end

        def to_h
          {
            "namespace" => namespace,
            "nodes" => nodes,
            "fan_out" => fan_out,
            "fan_in" => fan_in,
            "internal" => internal,
            "total" => total
          }
        end
      end
    end
  end
end
