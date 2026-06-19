# frozen_string_literal: true

require "json"

module Rigor
  module ModuleGraph
    # Kinds of node metadata the plugin emits. Class and module
    # declarations carry the class itself; the remaining kinds are
    # children of one — methods and attributes.
    NODE_KINDS = %w[
      class
      module
      instance_method
      class_method
      attribute
    ].freeze

    # Visibility values for a method / attribute. Matches the Ruby
    # access modifiers.
    NODE_VISIBILITIES = %w[public protected private].freeze

    # Access flavours for an +attr_*+ macro. Used to label
    # attribute glyphs in a class diagram and nothing else.
    NODE_ACCESSES = %w[read write accessor].freeze

    # A piece of node metadata extracted from a source file.
    #
    # Three flavours, distinguished by +kind+:
    #
    # * +class+ / +module+ — a constant declaration. Carries
    #   +name+, +path+, +line+, +column+. +owner+/+visibility+/
    #   +access+ are nil.
    # * +instance_method+ / +class_method+ — a method definition.
    #   Carries +name+, +owner+ (the enclosing class/module),
    #   +visibility+, +path+, +line+, +column+.
    # * +attribute+ — an +attr_reader+ / +attr_writer+ /
    #   +attr_accessor+ symbol. Carries +name+, +owner+,
    #   +visibility+, +access+, +path+, +line+, +column+.
    class Node < Data.define(:kind, :name, :owner, :path, :line, :column, :visibility, :access)
      KINDS = NODE_KINDS
      VISIBILITIES = NODE_VISIBILITIES
      ACCESSES = NODE_ACCESSES

      def self.build(kind:, name:, owner: nil, path: nil, line: nil, column: nil,
                     visibility: nil, access: nil)
        new(
          kind: validate_kind!(kind),
          name: name.to_s.freeze,
          owner: owner && owner.to_s.freeze,
          path: path,
          line: line,
          column: column,
          visibility: visibility && validate_visibility!(visibility),
          access: access && validate_access!(access)
        )
      end

      def self.validate_kind!(kind) # :nodoc:
        kind = kind.to_s
        return kind if KINDS.include?(kind)

        raise ArgumentError, "unknown node kind #{kind.inspect}; expected one of #{KINDS.inspect}"
      end

      def self.validate_visibility!(visibility) # :nodoc:
        visibility = visibility.to_s
        return visibility if VISIBILITIES.include?(visibility)

        raise ArgumentError, "unknown visibility #{visibility.inspect}; expected one of #{VISIBILITIES.inspect}"
      end

      def self.validate_access!(access) # :nodoc:
        access = access.to_s
        return access if ACCESSES.include?(access)

        raise ArgumentError, "unknown access #{access.inspect}; expected one of #{ACCESSES.inspect}"
      end

      def to_h
        h = { "kind" => kind, "name" => name }
        h["owner"] = owner if owner
        h["path"] = path if path
        h["line"] = line if line
        h["column"] = column if column
        h["visibility"] = visibility if visibility
        h["access"] = access if access
        h
      end

      # The payload embedded in the plugin's +:info+ diagnostic
      # message. Position is intentionally absent — the diagnostic
      # row carries +path+/+line+/+column+ on its own.
      def to_message_payload
        h = { "kind" => kind, "name" => name }
        h["owner"] = owner if owner
        h["visibility"] = visibility if visibility
        h["access"] = access if access
        h
      end

      # Key used to dedupe node rows. Two declarations of the same
      # method on the same owner collapse to one row; class re-opens
      # collapse to one class node.
      def dedup_key
        [kind, owner, name]
      end
    end

    # JSONL reader / writer for Node rows.
    module NodeIO
      module_function

      def write(nodes, io)
        seen = {}
        nodes.each do |node|
          key = node.dedup_key
          next if seen[key]

          seen[key] = true
          io.puts(JSON.generate(node.to_h))
        end
      end

      def read(io)
        nodes = []
        io.each_line do |line|
          line = line.strip
          next if line.empty?

          row = JSON.parse(line)
          nodes << Node.build(
            kind: row.fetch("kind"),
            name: row.fetch("name"),
            owner: row["owner"],
            path: row["path"],
            line: row["line"],
            column: row["column"],
            visibility: row["visibility"],
            access: row["access"]
          )
        end
        nodes
      end
    end
  end
end
