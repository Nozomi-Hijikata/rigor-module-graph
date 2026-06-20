# frozen_string_literal: true

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

      EMPTY = [].freeze
      private_constant :EMPTY

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
          edges.select { |e| reachable.key?(e.from) && reachable.key?(e.to) }
        when :walk
          indexes = walked_edge_indexes(edges, roots, depth, direction)
          # `walked` is a Hash<edge_index, true>; filter by
          # membership keeping the original edge order.
          out = []
          edges.each_with_index do |e, i|
            out << e if indexes.key?(i)
          end
          out
        end
      end

      # BFS over the edge graph; returns a Hash<node_name, true>
      # whose keys are the reachable nodes. We use a Hash instead
      # of Set because Hash key lookup is faster on Ruby 4 and we
      # don't need Set's union/intersection methods here.
      def walk(edges, roots, depth, direction)
        forward, backward = build_adjacency(edges, direction)

        visited = {}
        frontier = []
        roots.each do |r|
          visited[r] = true
          frontier << r
        end
        hops = 0

        until frontier.empty?
          break if depth && hops >= depth

          next_frontier = []
          frontier.each do |node|
            each_neighbour(node, forward, backward, direction) do |n|
              next if visited.key?(n)

              visited[n] = true
              next_frontier << n
            end
          end
          frontier = next_frontier
          hops += 1
        end
        visited
      end

      # Returns a Hash<edge_index, true> for the edges actually
      # traversed by the BFS. `direction=both` runs the out-walk
      # and in-walk against separate adjacency tables so the
      # zigzag chain (+A <- X -> Y+ whose +X -> Y+ isn't on any
      # genuine path from the roots) stays excluded.
      def walked_edge_indexes(edges, roots, depth, direction)
        if direction == :both
          forward, backward = build_indexed_adjacencies(edges)
          walked = {}
          run_indexed_walk(forward, roots, depth, walked)
          run_indexed_walk(backward, roots, depth, walked)
          return walked
        end

        adjacency = build_indexed_adjacency(edges, direction)
        walked = {}
        run_indexed_walk(adjacency, roots, depth, walked)
        walked
      end

      # @api private
      def build_adjacency(edges, direction)
        # Build only the adjacency tables we actually need. The
        # caller asking for +:out+ never touches +backward+ etc.
        forward = direction == :in ? nil : Hash.new { |h, k| h[k] = [] }
        backward = direction == :out ? nil : Hash.new { |h, k| h[k] = [] }
        edges.each do |edge|
          forward[edge.from] << edge.to if forward
          backward[edge.to] << edge.from if backward
        end
        [forward, backward]
      end

      def each_neighbour(node, forward, backward, direction, &block)
        case direction
        when :out
          forward.fetch(node, EMPTY).each(&block)
        when :in
          backward.fetch(node, EMPTY).each(&block)
        when :both
          forward.fetch(node, EMPTY).each(&block)
          backward.fetch(node, EMPTY).each(&block)
        end
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

      def build_indexed_adjacencies(edges)
        forward = Hash.new { |h, k| h[k] = [] }
        backward = Hash.new { |h, k| h[k] = [] }
        edges.each_with_index do |edge, i|
          forward[edge.from] << [edge.to, i]
          backward[edge.to] << [edge.from, i]
        end
        [forward, backward]
      end

      def run_indexed_walk(adjacency, roots, depth, walked)
        visited = {}
        frontier = []
        roots.each do |r|
          visited[r] = true
          frontier << r
        end
        hops = 0
        until frontier.empty?
          break if depth && hops >= depth

          next_frontier = []
          frontier.each do |node|
            adjacency.fetch(node, EMPTY).each do |neighbour, edge_index|
              walked[edge_index] = true
              next if visited.key?(neighbour)

              visited[neighbour] = true
              next_frontier << neighbour
            end
          end
          frontier = next_frontier
          hops += 1
        end
      end
    end
  end
end
