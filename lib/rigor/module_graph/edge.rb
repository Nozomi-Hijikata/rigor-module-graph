# frozen_string_literal: true

require "json"

module Rigor
  module ModuleGraph
    # A single dependency edge between two constants.
    #
    # Two serialisation shapes:
    #
    # - `to_message_payload` — what the plugin embeds in a
    #   diagnostic's `message`. The collector reconstructs an
    #   Edge from it plus the diagnostic's own path/line/column,
    #   so payload omits those to keep the message compact.
    # - `to_h` — what the JSONL writer dumps to disk. Full row,
    #   path/line/column included.
    EDGE_KINDS = %w[inherits include prepend extend const_ref].freeze
    EDGE_CONFIDENCES = %w[syntax zeitwerk rigor_type unresolved].freeze

    Edge = Data.define(:from, :to, :kind, :path, :line, :column, :confidence, :raw) do
      KINDS = EDGE_KINDS
      CONFIDENCES = EDGE_CONFIDENCES

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

      def self.validate_kind!(kind)
        kind = kind.to_s
        return kind if KINDS.include?(kind)

        raise ArgumentError, "unknown edge kind #{kind.inspect}; expected one of #{KINDS.inspect}"
      end

      def self.validate_confidence!(confidence)
        confidence = confidence.to_s
        return confidence if CONFIDENCES.include?(confidence)

        raise ArgumentError, "unknown confidence #{confidence.inspect}; expected one of #{CONFIDENCES.inspect}"
      end

      def to_h
        h = { "from" => from, "to" => to, "kind" => kind }
        h["path"] = path if path
        h["line"] = line if line
        h["column"] = column if column
        h["confidence"] = confidence
        h["raw"] = raw if raw
        h
      end

      def to_message_payload
        h = { "from" => from, "to" => to, "kind" => kind, "confidence" => confidence }
        h["raw"] = raw if raw
        h
      end

      def to_json(*args)
        JSON.generate(to_h, *args)
      end

      # Key used to dedupe edges across files / rules. Path is
      # intentionally not part of the key so two `include Foo` in
      # the same class but in two files still collapse to one
      # logical edge — same for line numbers, which is how
      # plain re-runs are protected from output growth.
      def dedup_key
        [from, to, kind, confidence]
      end
    end

    # JSONL reader / writer for Edge rows.
    module EdgeIO
      module_function

      def write(edges, io)
        seen = {}
        edges.each do |edge|
          key = edge.dedup_key
          next if seen[key]

          seen[key] = true
          io.puts(JSON.generate(edge.to_h))
        end
      end

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
