# frozen_string_literal: true

require "erb"

module Rigor
  module ModuleGraph
    # Self-contained HTML document that embeds Mermaid output
    # inline so it renders without any local server (works over
    # +file://+, no fetch).
    #
    # The view loads +mermaid@10+ from a CDN at render time. The
    # only network access is that one CDN URL; if a project needs
    # to ship a fully offline page, render the SVG via Graphviz
    # and embed that instead.
    #
    # The HTML body lives in
    # +lib/rigor/module_graph/templates/view.html.erb+; bumping
    # styling or Mermaid init options is an edit of that file
    # alone.
    module HtmlView
      module_function

      TEMPLATE_PATH = File.expand_path("templates/view.html.erb", __dir__)

      # @param title [String] page <title> and <h1> text
      # @param mermaid_source [String] the mermaid flowchart body
      # @param subtitle [String, nil] one-line caption under the H1
      # @return [String] the rendered HTML document
      def render(title:, mermaid_source:, subtitle: nil)
        indented = mermaid_source.strip.gsub("\n", "\n  ")
        template.result_with_hash(
          title: title,
          subtitle: subtitle,
          indented_mermaid: indented
        )
      end

      def template
        @template ||= ERB.new(File.read(TEMPLATE_PATH), trim_mode: "-")
      end
    end
  end
end
