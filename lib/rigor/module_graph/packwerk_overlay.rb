# frozen_string_literal: true

require "find"

module Rigor
  module ModuleGraph
    # Discovers Packwerk-style packages (`package.yml`) inside a
    # project tree and maps source file paths to their owning
    # package.
    #
    # Treats every directory that contains a +package.yml+ as a
    # package root. The package's name is its path relative to the
    # project root with a leading +./+ stripped — that's how
    # +packwerk+ itself reports them, and it's stable across
    # Packwerk versions which gives the renderer something to use
    # as the cluster label.
    #
    # Files map to the +deepest+ ancestor package — if a nested
    # `packages/billing/invoices/package.yml` lives under
    # `packages/billing/package.yml`, a file under the inner one
    # belongs to +packages/billing/invoices+, not +packages/billing+.
    class PackwerkOverlay
      Package = Data.define(:name, :root) do
        # Stable rendering for snapshot / debug output.
        def to_s
          "Package(#{name})"
        end
      end

      EXCLUDED_DIRS = %w[.git node_modules tmp log vendor].freeze
      private_constant :EXCLUDED_DIRS

      attr_reader :project_root, :packages

      # @param project_root [String] the project root the packages
      #   are reported relative to
      # @param packages [Array<Package>] frozen
      def initialize(project_root:, packages:)
        @project_root = realpath_or_expand(project_root)
        @packages = packages
                    .map { |pkg| Package.new(name: pkg.name, root: realpath_or_expand(pkg.root)) }
                    .sort_by { |p| -p.root.length }
                    .freeze
      end

      # @param project_root [String]
      # @return [PackwerkOverlay]
      def self.discover(project_root)
        root = File.expand_path(project_root)
        packages = []
        Find.find(root) do |path|
          base = File.basename(path)
          if File.directory?(path) && EXCLUDED_DIRS.include?(base) && path != root
            Find.prune
            next
          end
          next unless File.file?(path) && base == "package.yml"

          pkg_root = File.dirname(path)
          packages << Package.new(name: package_name(pkg_root, root), root: pkg_root)
        end
        new(project_root: root, packages: packages)
      end

      def self.package_name(pkg_root, project_root)
        # The root package (a `package.yml` at the project root) is
        # canonically called `.` in Packwerk output. Match that so
        # users see the familiar label.
        return "." if pkg_root == project_root

        rel = pkg_root.sub(/\A#{Regexp.escape(project_root)}\/?/, "")
        rel.empty? ? "." : rel
      end

      # @return [Boolean] true when at least one package.yml was
      #   found.
      def any?
        !@packages.empty?
      end

      # Find the deepest package whose root is an ancestor of
      # +path+. Returns nil when the path is outside every
      # package's root.
      #
      # Both sides are normalised through +realpath+ when
      # possible so a macOS +/tmp+ ↔ +/private/tmp+ symlink (or
      # any other symlink in the project root path) doesn't make
      # the comparison spuriously miss.
      def package_for(path)
        return nil if path.nil? || path.empty?

        absolute = realpath_of(File.expand_path(path, @project_root))
        @packages.find do |pkg|
          absolute == pkg.root || absolute.start_with?(pkg.root + "/")
        end
      end

      def realpath_or_expand(path)
        File.realpath(File.expand_path(path))
      rescue Errno::ENOENT
        File.expand_path(path)
      end

      def realpath_of(path)
        File.realpath(path)
      rescue Errno::ENOENT
        # Tests and synthetic edges may carry paths whose tail
        # doesn't exist on disk; walk up to the deepest existing
        # ancestor, realpath that, then reattach the missing tail.
        # That makes a macOS +/tmp+ ↔ +/private/tmp+ symlink
        # transparent even for synthetic paths.
        parent = path
        until parent == File.dirname(parent)
          parent = File.dirname(parent)
          if File.exist?(parent)
            return File.realpath(parent) + path[parent.length..]
          end
        end
        path
      end

      # Build a +{node_name => package_name}+ mapping from a list
      # of edges. We only attribute a node to a package when we
      # have evidence the node is *declared* under that package's
      # root — that is, the node appears as +edge.from+ for at
      # least one edge, and that edge's path lives under the
      # package. The +to+ side is just a reference; using it would
      # mis-attribute base classes (+ApplicationRecord+) and any
      # other external constant to whichever package happens to
      # reference them first.
      def groups_for(edges)
        node_paths = {}
        edges.each do |edge|
          node_paths[edge.from] ||= edge.path
        end
        node_paths.each_with_object({}) do |(name, path), acc|
          pkg = package_for(path)
          acc[name] = pkg.name if pkg
        end
      end
    end
  end
end
