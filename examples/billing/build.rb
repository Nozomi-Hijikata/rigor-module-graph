#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate edges.jsonl + graph.mmd + graph.dot + index.html for
# the Billing example. Run from any working directory:
#
#   ruby examples/billing/build.rb
#   bundle exec ruby examples/billing/build.rb
#
# The script shells out to the `rigor-module-graph` executable
# from the gem checkout, pinning `BUNDLE_GEMFILE` to the gem's
# own Gemfile so the host doesn't have to know about it.

require "fileutils"
require "open3"

HERE = File.expand_path(__dir__)
GEM_ROOT = File.expand_path("../..", HERE)
EXE = File.join(GEM_ROOT, "exe/rigor-module-graph")
ENV["BUNDLE_GEMFILE"] = File.join(GEM_ROOT, "Gemfile")

Dir.chdir(HERE)

def step(label)
  warn "==> #{label}"
  yield
end

def sh!(*cmd, **opts)
  if opts[:out]
    out, err, status = Open3.capture3(*cmd)
    raise "command failed (#{status.exitstatus}): #{cmd.inspect}\n#{err}" unless status.success?

    File.write(opts[:out], out)
  else
    system(*cmd, exception: true)
  end
end

step "collect (rigor check + filter)" do
  sh! "bundle", "exec", EXE, "collect"
end

step "render mermaid (collapsed under Billing)" do
  sh!(
    "bundle", "exec", EXE, "mermaid",
    "--collapse", "Billing",
    ".rigor/module_graph/edges.jsonl",
    out: "graph.mmd"
  )
end

step "render dot (collapsed under Billing)" do
  sh!(
    "bundle", "exec", EXE, "dot",
    "--collapse", "Billing",
    ".rigor/module_graph/edges.jsonl",
    out: "graph.dot"
  )
end

if (dot = `command -v dot`.strip) && !dot.empty?
  step "render svg via Graphviz" do
    sh! "dot", "-Tsvg", "graph.dot", "-o", "graph.svg"
  end
else
  warn "==> skip svg (graphviz `dot` not on PATH)"
end

step "rebuild index.html (Mermaid embedded inline)" do
  mmd = File.read("graph.mmd")
  indented = mmd.strip.gsub("\n", "\n  ")
  html = <<~HTML
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>rigor-module-graph: billing example</title>
        <script type="module">
          import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs";
          mermaid.initialize({ startOnLoad: true, securityLevel: "loose" });
        </script>
        <style>
          body { font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 2rem; color: #0f172a; background: #f8fafc; }
          h1 { margin-top: 0; }
          .meta { color: #64748b; margin-bottom: 1.5rem; }
          .card { background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 1.5rem; box-shadow: 0 1px 2px rgba(15,23,42,0.04); }
          .legend { display: flex; gap: 1rem; flex-wrap: wrap; margin-top: 1rem; }
          .legend span { padding: 0.25rem 0.75rem; border-radius: 999px; color: white; font-size: 12px; }
          .legend .inherits { background: #0f172a; }
          .legend .include { background: #1d4ed8; }
          .legend .prepend { background: #9333ea; }
          .legend .extend { background: #0f766e; }
          .legend .const_ref { background: #94a3b8; color: #0f172a; }
        </style>
      </head>
      <body>
        <h1>rigor-module-graph: billing example</h1>
        <p class="meta">Generated from <code>examples/billing/app</code> via <code>rigor-module-graph collect &amp;&amp; mermaid</code>.</p>
        <div class="card">
          <pre class="mermaid">
    #{indented}
          </pre>
        </div>
        <div class="legend">
          <span class="inherits">inherits</span>
          <span class="include">include</span>
          <span class="prepend">prepend</span>
          <span class="extend">extend</span>
          <span class="const_ref">const_ref</span>
        </div>
      </body>
    </html>
  HTML
  File.write("index.html", html)
end

warn "==> done. open #{File.join(HERE, "index.html")} in a browser."
