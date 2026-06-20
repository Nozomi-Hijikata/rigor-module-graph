#!/usr/bin/env ruby
# Micro-benchmark for the hot loops (Reachability, Stats,
# CycleDetector, Dot / Mermaid render).
#
# Usage:
#
#   bundle exec ruby script/perf-bench.rb [PATH/TO/edges.jsonl]
#
# When no path is given we look for `.rigor/module_graph/
# edges.jsonl` under the current directory. Run with the project
# Gemfile so the `benchmark` gem resolves on Ruby 4.0:
#
#   BUNDLE_GEMFILE=$PWD/Gemfile ruby --yjit script/perf-bench.rb
#
# Add the gem to Gemfile (group :development) and bundle install
# if `benchmark` isn't available.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rigor-module-graph"
require "benchmark"
require "json"

edges_path = ARGV[0] || ".rigor/module_graph/edges.jsonl"
unless File.exist?(edges_path)
  warn "No edges file at #{edges_path}. Run `rigor-module-graph collect` first " \
       "or pass a path."
  exit 1
end

edges = []
File.foreach(edges_path) do |line|
  row = JSON.parse(line)
  edges << Rigor::ModuleGraph::Edge.build(
    from: row["from"], to: row["to"], kind: row["kind"],
    confidence: row.fetch("confidence", "syntax"),
    path: row["path"], line: row["line"], column: row["column"]
  )
end
puts "loaded #{edges.size} edges from #{edges_path}"
puts "ruby #{RUBY_VERSION}, YJIT #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "on" : "off"}"
puts

iterations = ENV.fetch("ITER", "50").to_i

Benchmark.bm(40) do |b|
  root = edges.first&.from || "Article"

  b.report("Reachability.filter cluster depth=1 out") do
    iterations.times do
      Rigor::ModuleGraph::Reachability.filter(edges, roots: [root], depth: 1, direction: :out)
    end
  end
  b.report("Reachability.filter cluster depth=3 out") do
    iterations.times do
      Rigor::ModuleGraph::Reachability.filter(edges, roots: [root], depth: 3, direction: :out)
    end
  end
  b.report("Reachability.filter walk depth=3 out") do
    iterations.times do
      Rigor::ModuleGraph::Reachability.filter(
        edges, roots: [root], depth: 3, direction: :out, edge_scope: :walk
      )
    end
  end
  b.report("Reachability.filter cluster depth=3 both") do
    iterations.times do
      Rigor::ModuleGraph::Reachability.filter(edges, roots: [root], depth: 3, direction: :both)
    end
  end
  b.report("CycleDetector.detect full graph") do
    (iterations / 10).times { Rigor::ModuleGraph::CycleDetector.detect(edges) }
  end
  b.report("Stats.compute full graph") do
    iterations.times { Rigor::ModuleGraph::Stats.compute(edges) }
  end
  b.report("Dot.render full graph") do
    (iterations / 2).times { Rigor::ModuleGraph::Dot.render(edges) }
  end
  b.report("Mermaid.render full graph") do
    (iterations / 2).times { Rigor::ModuleGraph::Mermaid.render(edges) }
  end
end
