# frozen_string_literal: true

module Rigor
  module ModuleGraph
    # Converts a Ruby source path into the fully-qualified constant
    # the Zeitwerk convention says it should define.
    #
    # Pure function, no I/O. The plugin instantiates one per run from
    # `.rigor.yml` config and asks for `resolve(path)` per file. Two
    # configuration knobs:
    #
    # - `autoload_paths`: roots stripped from the path before
    #   camelising. Defaults to the standard Rails layout.
    # - `concern_dirs`: directories that act as transparent
    #   namespaces under Zeitwerk (`app/models/concerns/auditable.rb`
    #   resolves to `Auditable`, not `Concerns::Auditable`).
    #
    # The resolver is order-sensitive: longer / more specific roots
    # MUST be tried before their parents so `app/models/concerns/foo.rb`
    # picks up the concern root, not `app/models`. We sort by length
    # descending at construction time, so config order does not matter.
    class ZeitwerkResolver
      DEFAULT_AUTOLOAD_PATHS = %w[
        app/models
        app/controllers
        app/services
        app/jobs
        app/mailers
        app/helpers
        app/channels
        app/workers
        lib
      ].freeze

      DEFAULT_CONCERN_DIRS = %w[
        app/models/concerns
        app/controllers/concerns
      ].freeze

      attr_reader :autoload_paths, :concern_dirs

      def initialize(autoload_paths: DEFAULT_AUTOLOAD_PATHS,
                     concern_dirs: DEFAULT_CONCERN_DIRS,
                     project_root: nil)
        @project_root = project_root && File.expand_path(project_root)
        @autoload_paths = normalise_roots(autoload_paths)
        @concern_dirs = normalise_roots(concern_dirs)
        @sorted_roots = (@concern_dirs + @autoload_paths).sort_by { |r| -r.length }.uniq
      end

      # @param path [String] either relative to the project root or
      #   absolute. Both `app/models/billing/invoice.rb` and the
      #   `realpath` form work.
      # @return [String, nil] the inferred constant name, or nil when
      #   the path is not under any configured root or has no .rb
      #   extension.
      def resolve(path)
        return nil unless path

        rel = relativise(path)
        return nil unless rel
        return nil unless rel.end_with?(".rb")

        root = @sorted_roots.find { |r| rel.start_with?(r + "/") }
        return nil unless root

        suffix = rel[(root.length + 1)..]
        camelise_path(suffix.delete_suffix(".rb"))
      end

      # True when `inferred` matches the (probably syntax-derived)
      # `actual` constant under Zeitwerk's conventions. We compare
      # ignoring leading "::" since absolute / relative are not a
      # meaningful distinction here.
      def matches?(actual, inferred)
        return false if actual.nil? || inferred.nil?

        strip_leading(actual) == strip_leading(inferred)
      end

      def relativise(path)
        absolute = File.expand_path(path)
        if @project_root && absolute.start_with?(@project_root + "/")
          absolute[(@project_root.length + 1)..]
        elsif path.start_with?("/")
          # Absolute path with no project root configured: try every
          # autoload root as a suffix match. Used by integration runs
          # where files live in a tmpdir.
          suffix = @sorted_roots.find { |r| absolute.include?("/" + r + "/") }
          if suffix
            idx = absolute.rindex("/" + suffix + "/")
            absolute[(idx + 1)..]
          end
        else
          path
        end
      end

      def normalise_roots(roots)
        Array(roots).map { |r| r.to_s.sub(%r{/+\z}, "") }.reject(&:empty?).freeze
      end

      def strip_leading(name)
        name.sub(/\A::/, "")
      end

      def camelise_path(rel_no_ext)
        rel_no_ext.split("/").map { |seg| camelise_segment(seg) }.join("::")
      end

      def camelise_segment(segment)
        segment.split("_").map(&:capitalize).join
      end
    end
  end
end
