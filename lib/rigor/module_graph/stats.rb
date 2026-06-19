# frozen_string_literal: true

require "set"

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
        groups = group_nodes(edges, depth)
        nodes_per_group = Hash.new { |h, k| h[k] = Set.new }
        edges.each do |edge|
          # Normalise the raw name when counting unique nodes so
          # absolute (`::Foo::Bar`) and relative (`Foo::Bar`) forms
          # fold together — they refer to the same constant.
          nodes_per_group[groups.fetch(edge.from, TOP_LEVEL_BUCKET)] << normalise(edge.from)
          nodes_per_group[groups.fetch(edge.to, TOP_LEVEL_BUCKET)] << normalise(edge.to)
        end

        metrics = Hash.new do |h, k|
          h[k] = NamespaceMetrics.new(
            namespace: k, nodes: 0, fan_out: 0, fan_in: 0, internal: 0
          )
        end
        nodes_per_group.each do |group, nodes|
          metrics[group] = metrics[group].with(nodes: nodes.size)
        end

        edges.each do |edge|
          from_group = groups.fetch(edge.from, TOP_LEVEL_BUCKET)
          to_group = groups.fetch(edge.to, TOP_LEVEL_BUCKET)
          if from_group == to_group
            metrics[from_group] = metrics[from_group].with(
              internal: metrics[from_group].internal + 1
            )
          else
            metrics[from_group] = metrics[from_group].with(
              fan_out: metrics[from_group].fan_out + 1
            )
            metrics[to_group] = metrics[to_group].with(
              fan_in: metrics[to_group].fan_in + 1
            )
          end
        end

        metrics.values.sort_by { |m| [-m.fan_out, m.namespace] }
      end

      # Maps every node name in +edges+ to its grouping bucket.
      def group_nodes(edges, depth)
        names = edges.flat_map { |edge| [edge.from, edge.to] }.uniq
        names.to_h do |name|
          [name, bucket_for(name, depth)]
        end
      end

      def bucket_for(name, depth)
        parts = normalise(name).split("::")
        return TOP_LEVEL_BUCKET if parts.size <= depth

        parts.first(depth).join("::")
      end

      # Strip leading "::" so absolute and relative names share
      # the same bucket / node identity — they refer to the same
      # constant either way.
      def normalise(name)
        name.sub(/\A::/, "")
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
