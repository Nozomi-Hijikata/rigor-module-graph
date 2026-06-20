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
      VALID_EDGE_SCOPES = %i[cluster walk].freeze

      # @param edges [Array<Edge>]
      # @param roots [Array<String>] node names to start from
      # @param depth [Integer, nil] hop limit, nil for unlimited
      # @param direction [Symbol] one of VALID_DIRECTIONS
      # @param edge_scope [Symbol] one of VALID_EDGE_SCOPES.
      #   +:cluster+ (default) keeps every edge whose endpoints
      #   both fall in the reachable node set — useful when you
      #   want the neighbourhood as a cluster. +:walk+ keeps only
      #   the edges the BFS itself traverses, so a
      #   +depth=1 --direction out+ walk from +Article+ returns
      #   exactly the edges whose +from+ is +Article+, never the
      #   sibling +inherits ApplicationRecord+ rows from the
      #   reached set.
      # @return [Array<Edge>] filtered edges with original order
      #   preserved.
      def filter(edges, roots:, depth: nil, direction: :both, edge_scope: :cluster)
        roots = Array(roots).map(&:to_s).reject(&:empty?)
        return edges if roots.empty?

        unless VALID_DIRECTIONS.include?(direction)
          raise ArgumentError, "unknown direction #{direction.inspect}; expected one of #{VALID_DIRECTIONS.inspect}"
        end
        unless VALID_EDGE_SCOPES.include?(edge_scope)
          raise ArgumentError, "unknown edge_scope #{edge_scope.inspect}; expected one of #{VALID_EDGE_SCOPES.inspect}"
        end

        case edge_scope
        when :cluster
          reachable = walk(edges, roots, depth, direction)
          edges.select { |e| reachable.include?(e.from) && reachable.include?(e.to) }
        when :walk
          indexes = walked_edge_indexes(edges, roots, depth, direction)
          edges.each_with_index.select { |(_e, i)| indexes.include?(i) }.map(&:first)
        end
      end

      # Returns the indexes of edges actually traversed by the BFS.
      # `direction=both` is the union of `:out` and `:in` walks —
      # explicitly *not* a forward/backward-mixed BFS, which would
      # admit zig-zag chains like +A <- X -> Y+ that aren't on any
      # genuine path from the roots.
      def walked_edge_indexes(edges, roots, depth, direction)
        if direction == :both
          return walked_edge_indexes(edges, roots, depth, :out) |
                 walked_edge_indexes(edges, roots, depth, :in)
        end

        adjacency = build_indexed_adjacency(edges, direction)
        visited = Set.new(roots)
        frontier = Set.new(roots)
        walked = Set.new
        hops = 0

        until frontier.empty?
          break if depth && hops >= depth

          next_frontier = Set.new
          frontier.each do |node|
            adjacency[node].each do |neighbour, edge_index|
              walked << edge_index
              next if visited.include?(neighbour)

              visited << neighbour
              next_frontier << neighbour
            end
          end
          frontier = next_frontier
          hops += 1
        end
        walked
      end

      def build_indexed_adjacency(edges, direction)
        adjacency = Hash.new { |h, k| h[k] = [] }
        edges.each_with_index do |edge, i|
          case direction
          when :out then adjacency[edge.from] << [edge.to, i]
          when :in then adjacency[edge.to] << [edge.from, i]
          end
        end
        adjacency
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
            neighbours = neighbours_for(node, forward, backward, direction) || []
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
