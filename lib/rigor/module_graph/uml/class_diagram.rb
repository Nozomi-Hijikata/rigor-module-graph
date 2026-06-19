# frozen_string_literal: true

module Rigor
  module ModuleGraph
    module Uml
      # Renders a +classDiagram+ Mermaid document from a list of
      # edges plus a list of node metadata rows (the +nodes.jsonl+
      # the collector writes alongside +edges.jsonl+).
      #
      # Differences from the +flowchart+ renderer:
      #
      # * Each class / module gets a body block listing its
      #   instance methods, class methods, and attributes, with the
      #   standard UML visibility glyphs (+, -, #).
      # * Modules are annotated +<<module>>+ so a Ruby module is
      #   visually distinct from a class.
      # * +inherits+ uses +--|>+, mixin uses +..|>+, +const_ref+
      #   uses +..>+, ActiveRecord associations carry cardinality
      #   pairs ("1" / "*") as edge endpoints.
      # * Mermaid disallows +::+ in class identifiers; we sanitise
      #   to +__+ and keep the original as the label only.
      #
      # Filtering knobs:
      #
      # * +include_methods:+ (default true) — show methods inside
      #   class bodies.
      # * +include_attributes:+ (default true) — show attributes.
      # * +visibilities:+ — array subset of +%w[public protected
      #   private]+, default all.
      module ClassDiagram
        module_function

        VISIBILITY_GLYPH = {
          "public" => "+",
          "protected" => "#",
          "private" => "-"
        }.freeze

        ARROW_FOR_KIND = {
          "inherits" => "<|--",
          "include" => "<|..",
          "prepend" => "<|..",
          "extend" => "<|..",
          "const_ref" => "<.."
        }.freeze

        CARDINALITY = {
          "has_many" => ['"1"', '"*"'],
          "belongs_to" => ['"*"', '"1"'],
          "has_one" => ['"1"', '"1"'],
          "has_and_belongs_to_many" => ['"*"', '"*"']
        }.freeze

        def render(edges, nodes,
                   include_methods: true,
                   include_attributes: true,
                   visibilities: %w[public protected private])
          declarations = node_declarations(nodes)
          members = node_members(nodes, include_methods, include_attributes, visibilities)

          out = +"classDiagram\n"
          render_classes(out, declarations, members, edges)
          render_edges(out, dedup(edges))
          out
        end

        # +Foo::Bar+ can't be a Mermaid identifier; coerce to a
        # safe form. The label always carries the original.
        def safe_id(name)
          name.gsub(/[^A-Za-z0-9_]+/, "__")
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

        # Build a +{name => "class"|"module"}+ table from the
        # node-declaration rows.
        def node_declarations(nodes)
          decl = {}
          nodes.each do |row|
            case row.kind
            when "class", "module"
              # Re-opens may set the same row multiple times —
              # whichever wins doesn't matter because the kind is
              # the same.
              decl[row.name] = row.kind
            end
          end
          decl
        end

        # Build a +{owner_name => [{glyph, name, label}, ...]}+
        # table covering the displayable members for every owner.
        def node_members(nodes, include_methods, include_attributes, visibilities)
          members = Hash.new { |h, k| h[k] = [] }
          nodes.each do |row|
            owner = row.owner
            next if owner.nil?
            visibility = row.visibility || "public"
            next unless visibilities.include?(visibility)

            glyph = VISIBILITY_GLYPH.fetch(visibility, "+")

            case row.kind
            when "instance_method", "class_method"
              next unless include_methods

              suffix = row.kind == "class_method" ? "$ " : ""
              members[owner] << "#{glyph}#{row.name}() #{suffix}".strip
            when "attribute"
              next unless include_attributes

              # access (read/write/accessor) hints at getter/setter
              # presence; we annotate it after the name.
              members[owner] << "#{glyph}#{row.name} : #{row.access}"
            end
          end
          members
        end

        # Emit one +class Foo+ line per node, plus a body block of
        # methods / attributes when we have any.
        #
        # We intentionally do NOT emit the UML +<<module>>+
        # annotation: Mermaid 10.x's classDiagram parser silently
        # rejects the document when an annotation co-exists with
        # the +class Foo["Label"]+ form we need for namespaced
        # constants, and rejecting the namespace label is worse for
        # a Ruby graph than losing the module marker. The module
        # vs class distinction is therefore encoded as a +" (mod)"+
        # label suffix for module nodes — it is rendered inside the
        # box where every Mermaid renderer surfaces it.
        #
        # Any class that appears only in an edge keeps its bare
        # +class Foo+ line so the arrow has a target.
        def render_classes(out, declarations, members, edges)
          known = Set.new(declarations.keys)
          edges.each do |edge|
            known << edge.from << edge.to
          end
          known.sort.each do |name|
            id = safe_id(name)
            kind = declarations[name]
            label = label_for(name, kind)
            label_suffix = (label == id ? "" : "[\"#{label}\"]")
            out << "  class #{id}#{label_suffix}\n"

            owner_members = members[name]
            next if owner_members.nil? || owner_members.empty?

            out << "  class #{id} {\n"
            owner_members.each do |line|
              out << "    #{line}\n"
            end
            out << "  }\n"
          end
        end

        def label_for(name, kind)
          if kind == "module"
            "#{name} «module»"
          else
            name
          end
        end

        def render_edges(out, edges)
          out << "\n" unless edges.empty?
          edges.each do |edge|
            from_id = safe_id(edge.from)
            to_id = safe_id(edge.to)
            if (cardinality = CARDINALITY[edge.kind])
              left, right = cardinality
              # `from --> to : has_many` — Mermaid renders this as
              # an association arrow with the kind label.
              out << "  #{to_id} #{left} -- #{right} #{from_id} : #{edge.kind}\n"
            elsif (arrow = ARROW_FOR_KIND[edge.kind])
              out << "  #{to_id} #{arrow} #{from_id} : #{edge.kind}\n"
            else
              out << "  #{to_id} <-- #{from_id} : #{edge.kind}\n"
            end
          end
        end
      end
    end
  end
end
