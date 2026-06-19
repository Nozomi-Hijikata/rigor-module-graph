# billing example

Tiny Rails-shaped fixture that exercises `inherits` / `include` /
`prepend` / `extend` edges in a single namespace. Used as the
ready-made browser demo for `rigor-module-graph`.

## Run it

From the gem root:

```sh
bundle install
./examples/billing/build.sh
open examples/billing/index.html
```

`build.sh` does:

1. `rigor-module-graph collect` — runs `rigor check --format json
   --no-cache` against `app/` and writes
   `.rigor/module_graph/edges.jsonl`.
2. `rigor-module-graph mermaid` — renders the edges to
   `graph.mmd`.
3. `rigor-module-graph dot` — renders the edges to `graph.dot`,
   and Graphviz `dot -Tsvg` to `graph.svg` if `dot` is installed.
4. Rewrites `index.html` with the latest Mermaid embedded inline
   (no fetch, so `file://` works).

## What you'll see

- `Billing::Invoice`, `Billing::Payment`, `Billing::LineItem`
  all inherit from `ApplicationRecord`.
- All three include the shared `Auditable` concern.
- `Discountable` itself includes `Auditable`, so the graph shows
  a two-hop chain `Billing::Invoice -> Discountable -> Auditable`.
- `Tracked` is `prepend`ed and `Searchable` is `extend`ed,
  rendered with distinct arrow styles.
