# frozen_string_literal: true

require "set"

module Rigor
  module ModuleGraph
    # Restricts an edge list to the subgraph reachable from a set
    # of root nodes within a hop limit.
    #
    # Used by the +--from+ / +--depth+ CLI flags to make a graph
    # focused on one or a few constants tractable to look at on a
    # large project (where dumping every edge produces 1000+-node
    # Mermaid output that browsers refuse to render).
    #
    # Direction is configurable:
    #
    # +:out+::   follow edges in the natural direction
    #            (depends-on)
    # +:in+::    follow edges backwards (depended-on-by)
    # +:both+::  union of the two (the default — usually what
    #            "what's around Article?" means)
    module Reachability
      module_function

      VALID_DIRECTIONS = %i[out in both].freeze

      # @param edges [Array<Edge>]
      # @param roots [Array<String>] node names to start from
      # @param depth [Integer, nil] hop limit, nil for unlimited
      # @param direction [Symbol] one of VALID_DIRECTIONS
      # @return [Array<Edge>] the edges with both endpoints in the
      #   reachable set; original order preserved.
      def filter(edges, roots:, depth: nil, direction: :both)
        roots = Array(roots).map(&:to_s).reject(&:empty?)
        return edges if roots.empty?

        unless VALID_DIRECTIONS.include?(direction)
          raise ArgumentError, "unknown direction #{direction.inspect}; expected one of #{VALID_DIRECTIONS.inspect}"
        end

        reachable = walk(edges, roots, depth, direction)
        edges.select { |e| reachable.include?(e.from) && reachable.include?(e.to) }
      end

      def walk(edges, roots, depth, direction)
        forward = Hash.new { |h, k| h[k] = Set.new }
        backward = Hash.new { |h, k| h[k] = Set.new }
        edges.each do |edge|
          forward[edge.from] << edge.to
          backward[edge.to] << edge.from
        end

        reachable = Set.new(roots)
        frontier = Set.new(roots)
        hops = 0
        until frontier.empty?
          break if depth && hops >= depth

          next_frontier = Set.new
          frontier.each do |node|
            neighbours = neighbours_for(node, forward, backward, direction)
            neighbours.each do |n|
              next if reachable.include?(n)

              reachable << n
              next_frontier << n
            end
          end
          frontier = next_frontier
          hops += 1
        end
        reachable
      end

      def neighbours_for(node, forward, backward, direction)
        case direction
        when :out then forward[node]
        when :in then backward[node]
        when :both then forward[node] + backward[node]
        end
      end
    end
  end
end
