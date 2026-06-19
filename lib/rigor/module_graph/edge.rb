# frozen_string_literal: true

require "json"

module Rigor
  module ModuleGraph
    # The list of valid +kind+ values for an Edge.
    EDGE_KINDS = %w[inherits include prepend extend const_ref].freeze

    # The list of valid +confidence+ values for an Edge.
    EDGE_CONFIDENCES = %w[syntax zeitwerk rigor_type unresolved].freeze

    # A single dependency edge between two constants.
    #
    # Carries the dependency itself (+from+, +to+, +kind+,
    # +confidence+), the source position it was extracted from
    # (+path+, +line+, +column+), and the raw source slice (+raw+)
    # when the resolution went through a fallback path. Edge is a
    # +Data+ subclass — every instance is immutable.
    #
    # == Two serialisation shapes
    #
    # +to_message_payload+::
    #   What the plugin embeds in a diagnostic's +message+ field.
    #   The collector reconstructs an Edge from this payload plus
    #   the diagnostic's own +path+/+line+/+column+, so the payload
    #   omits position to keep the message compact.
    # +to_h+::
    #   What the JSONL writer dumps to disk. Full row, with
    #   +path+/+line+/+column+ included.
    #
    # == Dedup key
    #
    # +dedup_key+ ignores +path+ and +line+ so the same logical
    # edge declared in two files (or surfaced by two re-runs of
    # +rigor check+) collapses to one row.
    class Edge < Data.define(:from, :to, :kind, :path, :line, :column, :confidence, :raw)
      # Same as Rigor::ModuleGraph::EDGE_KINDS; exposed on the
      # class so callers can write +Edge::KINDS+.
      KINDS = EDGE_KINDS

      # Same as Rigor::ModuleGraph::EDGE_CONFIDENCES; exposed on
      # the class so callers can write +Edge::CONFIDENCES+.
      CONFIDENCES = EDGE_CONFIDENCES

      # Build an Edge, validating +kind+ and +confidence+ against
      # the canonical lists and frozen-stringifying +from+ / +to+.
      # Raises +ArgumentError+ on unknown values.
      def self.build(from:, to:, kind:, path: nil, line: nil, column: nil, confidence: "syntax", raw: nil)
        new(
          from: from.to_s.freeze,
          to: to.to_s.freeze,
          kind: validate_kind!(kind),
          path: path,
          line: line,
          column: column,
          confidence: validate_confidence!(confidence),
          raw: raw
        )
      end

      def self.validate_kind!(kind) # :nodoc:
        kind = kind.to_s
        return kind if KINDS.include?(kind)

        raise ArgumentError, "unknown edge kind #{kind.inspect}; expected one of #{KINDS.inspect}"
      end

      def self.validate_confidence!(confidence) # :nodoc:
        confidence = confidence.to_s
        return confidence if CONFIDENCES.include?(confidence)

        raise ArgumentError, "unknown confidence #{confidence.inspect}; expected one of #{CONFIDENCES.inspect}"
      end

      # The on-disk JSONL row. Nil-valued positional fields are
      # omitted so a stand-alone edge (e.g. constructed in a test
      # without a path) does not leak +"path":null+ noise.
      def to_h
        h = { "from" => from, "to" => to, "kind" => kind }
        h["path"] = path if path
        h["line"] = line if line
        h["column"] = column if column
        h["confidence"] = confidence
        h["raw"] = raw if raw
        h
      end

      # The payload embedded in a +:info+ diagnostic's message.
      # Position is intentionally absent — the diagnostic carries
      # its own +path+/+line+/+column+, so duplicating them here
      # would just bloat output.
      def to_message_payload
        h = { "from" => from, "to" => to, "kind" => kind, "confidence" => confidence }
        h["raw"] = raw if raw
        h
      end

      def to_json(*args)
        JSON.generate(to_h, *args)
      end

      # The key used to dedupe edges. +path+ and +line+ are
      # intentionally excluded so two +include Foo+ in the same
      # class across two files (or two re-runs of the same file)
      # collapse to one logical edge.
      def dedup_key
        [from, to, kind, confidence]
      end
    end

    # JSONL reader / writer for Edge rows. Used by the plugin
    # collector and the +rigor-module-graph+ renderer subcommands.
    module EdgeIO
      module_function

      # Stream +edges+ to +io+ as JSONL, deduping by Edge#dedup_key
      # so re-runs don't accumulate duplicate rows.
      def write(edges, io)
        seen = {}
        edges.each do |edge|
          key = edge.dedup_key
          next if seen[key]

          seen[key] = true
          io.puts(JSON.generate(edge.to_h))
        end
      end

      # Parse JSONL from +io+ into Edge instances. Blank lines are
      # skipped. Missing +confidence+ defaults to +"syntax"+ so the
      # format stays backwards-compatible with earlier outputs.
      def read(io)
        edges = []
        io.each_line do |line|
          line = line.strip
          next if line.empty?

          row = JSON.parse(line)
          edges << Edge.build(
            from: row.fetch("from"),
            to: row.fetch("to"),
            kind: row.fetch("kind"),
            path: row["path"],
            line: row["line"],
            column: row["column"],
            confidence: row.fetch("confidence", "syntax"),
            raw: row["raw"]
          )
        end
        edges
      end
    end
  end
end
