#!/usr/bin/env bash
# Generate edges.jsonl + graph.mmd + graph.dot + index.html for the
# Billing example. Run from the gem root or from this directory.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GEM_ROOT="$(cd "$HERE/../.." && pwd)"
EXE="$GEM_ROOT/exe/rigor-module-graph"

cd "$HERE"

export BUNDLE_GEMFILE="$GEM_ROOT/Gemfile"

echo "==> collect (rigor check + filter)" >&2
bundle exec "$EXE" collect

echo "==> render mermaid" >&2
bundle exec "$EXE" mermaid .rigor/module_graph/edges.jsonl > graph.mmd

echo "==> render dot" >&2
bundle exec "$EXE" dot .rigor/module_graph/edges.jsonl > graph.dot

if command -v dot >/dev/null 2>&1; then
  echo "==> render svg via Graphviz" >&2
  dot -Tsvg graph.dot -o graph.svg
else
  echo "==> skip svg (graphviz `dot` not on PATH)" >&2
fi

echo "==> rebuild index.html (Mermaid embedded inline)" >&2
ruby - <<'RUBY'
mmd = File.read("graph.mmd")
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
  #{mmd.strip.gsub("\n", "\n  ")}
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
RUBY

echo "==> done. open $HERE/index.html in a browser." >&2
