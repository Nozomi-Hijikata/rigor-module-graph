#!/usr/bin/env ruby

# Regenerate the billing example's committed artefacts:
# graph.svg (Graphviz) and index.html (the standalone Mermaid
# viewer). The intermediate edges.jsonl / nodes.jsonl live under
# .rigor/ and are gitignored.
#
# Run from any working directory:
#
#   ruby examples/billing/build.rb
#   bundle exec ruby examples/billing/build.rb
#
# Day-to-day, prefer `rigor-module-graph view --output <fmt>`
# directly. This script exists so the repo stays self-contained
# for GitHub viewers.

require "fileutils"

HERE = File.expand_path(__dir__)
GEM_ROOT = File.expand_path("../..", HERE)
EXE = File.join(GEM_ROOT, "exe/rigor-module-graph")
ENV["BUNDLE_GEMFILE"] = File.join(GEM_ROOT, "Gemfile")

Dir.chdir(HERE)

def step(label)
  warn "==> #{label}"
  yield
end

def view!(format, save:, extra: [])
  system(
    "bundle", "exec", EXE, "view",
    "--no-open",
    "--output", format,
    "--collapse", "Billing",
    "-o", save,
    *extra,
    exception: true
  )
end

step "html viewer → index.html" do
  view!("html", save: "index.html")
end

step "graphviz svg → graph.svg" do
  # `command` is a shell builtin on most systems, not an
  # executable — Ruby's backticks for `command -v dot` fork-execs
  # it directly and dies with ENOENT (CI surfaced this against
  # an Ubuntu runner where dot was installed but the shell-only
  # probe still aborted the build). Walk PATH ourselves; no
  # shell involved.
  on_path = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
    File.executable?(File.join(dir, "dot"))
  end
  if on_path
    view!("svg", save: "graph.svg")
  else
    warn "    skip (graphviz `dot` not on PATH)"
  end
end

step "mermaid class diagram → class-diagram.html (embedded)" do
  # Wraps the same standalone HTML shell HtmlView uses, just with
  # the classDiagram body — keeps the file directly openable.
  $LOAD_PATH.unshift File.join(GEM_ROOT, "lib")
  require "rigor/module_graph/html_view"
  require "open3"

  mmd, _stderr, status = Open3.capture3(
    "bundle", "exec", EXE, "view",
    "--no-open", "--output", "class-diagram",
    "--collapse", "Billing"
  )
  raise "class-diagram render failed" unless status.success?

  html = Rigor::ModuleGraph::HtmlView.render(
    title: "rigor-module-graph: billing class diagram",
    subtitle: "Generated from examples/billing/app",
    mermaid_source: mmd
  )
  File.write("class-diagram.html", html)
end

warn "==> done. open #{File.join(HERE, "index.html")} in a browser."
