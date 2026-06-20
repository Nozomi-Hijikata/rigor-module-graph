# Design plan

A record of the decisions still load-bearing for the codebase.
Per-version progress lives in [`CHANGELOG.md`](../CHANGELOG.md);
current rough edges live in [`limitation.md`](limitation.md).

## Purpose

Extract the Ruby `class` / `module` / `constant` dependency
graph from a project, render it as Graphviz DOT (and SVG by
extension), Mermaid `flowchart`, and Mermaid `classDiagram`.

The angle is **nominal**: the unit is a Ruby constant, not a
package boundary (Packwerk / Graphwerk) and not a call site
(Rubrowser / RailRoady). Five edge kinds are extracted:

- `inherits` — `class A < B`
- `include` / `prepend` / `extend` — module mixins
- `const_ref` — a bare constant reference inside a method body
- `association` — `has_many` / `belongs_to` / `has_one` /
  `has_and_belongs_to_many`, with cardinality

## Edge model

Edges are serialised as JSONL. One file, one line per edge:

```json
{"from":"Billing::Invoice","to":"ApplicationRecord","kind":"inherits","path":"app/models/billing/invoice.rb","line":1,"confidence":"syntax"}
{"from":"Billing::Invoice","to":"Auditable","kind":"include","path":"app/models/billing/invoice.rb","line":3,"confidence":"zeitwerk"}
{"from":"Billing::Invoice","to":"Money","kind":"const_ref","path":"app/models/billing/invoice.rb","line":12,"confidence":"rigor_type"}
```

Fields:

- `from`, `to` — fully-qualified constant names. Relative and
  absolute (`::Foo`) forms collapse to the same node.
- `kind` — one of the five above.
- `path`, `line`, `column` — extraction site.
- `confidence` — see below.
- `raw` — the source slice for an unresolved edge, so a manual
  pass can sift the `unresolved` pile without re-parsing.

JSONL was chosen over a single graph blob to keep extraction
and rendering decoupled: `collect` writes edges once, the
renderers (`dot`, `mermaid`, `cycles`, `stats`, `class-diagram`,
`view`) each read the same file. Adding a renderer doesn't
touch extraction.

## Confidence ladder

Each edge carries one of four confidence levels. Promotions are
monotonic; demotion never happens.

| level | source |
|---|---|
| `syntax` | the AST said so directly — `class A < B`, `include Mod` |
| `zeitwerk` | path-to-constant inference agreed with the lexical name |
| `rigor_type` | `scope.type_of(arg)` returned a `Singleton[X]` carrier |
| `unresolved` | name resolution failed; the source slice is in `raw` |

The reason for keeping `unresolved` instead of dropping it: in
real codebases, the indirect mixin paths (DSLs, proc-fed module
arguments, `include some_variable`) are exactly where the
interesting cross-cutting structure lives. Dropping them leaves
the graph confidently wrong; keeping them lets the consumer
filter with `--confidence syntax,zeitwerk,rigor_type` when they
want a tight subset, or grep `raw` when they want the noisy
ones.

## Output channel: info diagnostic, not side-effect JSONL

The plugin emits each edge as a Rigor diagnostic with
`severity: :info`, `rule: "edge"`, `source_family:
"plugin.module-graph"`. A wrapper subcommand (`collect`) runs
`rigor check --format json --no-cache` and re-serialises the
matching diagnostics into `.rigor/module_graph/edges.jsonl`.

The alternative — having the plugin append to a JSONL file as a
side effect of `node_rule` — was rejected because it forces the
plugin to handle Rigor's per-file cache invalidation and
`--workers` Ractor-level write coordination by itself. The
info-diagnostic path inherits those guarantees from the engine
unchanged.

The known cost is that Rigor's per-file cache can skip a
`node_rule` whose source hasn't changed, suppressing the edge
re-emission. `collect` defaults to `--no-cache` to side-step
that; an opt-out exists for users who'd rather trade
correctness for speed on large repos.

## Owner resolution

Phase 0 surfaced a Prism quirk: for `class Billing::Invoice`,
`node.constant_path.full_name` returns `"Invoice"`, dropping
the outer `module Billing`. `context.enclosing_module` alone
isn't enough either — it gives the innermost lexical wrapper
but not the constant-path segments above it.

`ConstantName.lexical_owner` reconstructs the full name by
walking `context.ancestors` outer-to-inner, joining each
`ClassNode` / `ModuleNode`'s `constant_path` segment with
`"::"`. This handles all four shapes in one sweep:

- `class Foo` inside `module A` → `A::Foo`
- `class Foo::Bar` inside `module A` → `A::Foo::Bar`
- `class A::B` at top level → `A::B`
- bare `class Foo` at top level → `Foo`

`class << self` doesn't change the owner. Treating it as
`Foo.singleton_class` would create a phantom node with no
matching constant; under-reporting singleton method ownership
is preferable to emitting nodes the user can't look up.

## Association inference: prefer the lexical namespace

`has_many :invoices` inside `Billing::Customer` resolves to
`Billing::Invoice` in Rails via `compute_type`'s namespace
walk — `Invoice` (top-level) only wins when `Billing::Invoice`
doesn't exist. The full walk needs every constant in scope,
which we don't have at extraction time; the namespace default
is the right approximation:

1. `class_name:` always wins. Explicit overrides are exact.
2. With no override, prefix the owner's namespace:
   `Billing::Customer` + `:invoices` → `Billing::Invoice`.
3. Top-level owners keep the bare name unchanged.

The trade-off: when the user has `has_many :users` inside
`Billing::Customer` and means the top-level `::User`, the
inference is wrong. The escape hatch is the same
`class_name: "::User"` override Rails itself needs in that case.

## Architecture map

| file | role |
|---|---|
| `lib/rigor/module_graph/plugin.rb` | declares `node_rule`s, dispatches to `Analyzer` |
| `lib/rigor/module_graph/analyzer.rb` | the four edge-emission rules (`class_edges`, `module_edges`, `call_edges`, `constant_edges`) |
| `lib/rigor/module_graph/constant_name.rb` | owner reconstruction from `context.ancestors` |
| `lib/rigor/module_graph/zeitwerk_resolver.rb` | path → constant inference; promotes confidence to `zeitwerk` when the path agrees |
| `lib/rigor/module_graph/edge.rb` | the `Edge` Data type, JSONL reader / writer, dedup |
| `lib/rigor/module_graph/reachability.rb` | BFS subgraph filter (`--from`, `--depth`, `--direction`, `--edge-scope`) |
| `lib/rigor/module_graph/dot.rb` | DOT renderer with cluster collapse |
| `lib/rigor/module_graph/mermaid.rb` | Mermaid `flowchart` renderer |
| `lib/rigor/module_graph/uml/class_diagram.rb` | Mermaid `classDiagram` renderer |
| `lib/rigor/module_graph/cycle_detector.rb` | iterative Tarjan SCC |
| `lib/rigor/module_graph/stats.rb` | per-namespace fan-in / fan-out / internal |
| `lib/rigor/module_graph/packwerk_overlay.rb` | `package.yml` discovery → `{node => cluster_label}` |
| `lib/rigor/module_graph/html_view.rb` | the `view` subcommand's HTML wrapper |
| `lib/rigor/module_graph/cli.rb` | argument parsing, subcommand dispatch |

## Phase ledger

Compressed history. The current behaviour of each phase lives
in the architecture map above; CHANGELOG carries the
release-level detail.

| phase | scope |
|---|---|
| 0 | Rigor plugin API spike — locked the `node_rule` + info-diagnostic shape, surfaced the rbs 4.x pin and the `class A::B` owner bug |
| 1 | MVP — `inherits` / `include` / `prepend` / `extend`, DOT / Mermaid, cycle detection, snapshot tests |
| 2 | Zeitwerk inference, `const_ref` (gated on `include_constant_refs`), namespace collapse |
| 3 | `scope.type_of` for indirect mixins — `Singleton[X]` promotes, anything else degrades to `unresolved` |
| 4 | `stats` subcommand, Packwerk overlay (`--package`, `--package-root`), confidence / kind filters |
| 5 | UML class diagram — `nodes.jsonl` (visibility tracked), Rails associations with cardinality, `class-diagram` subcommand |

## Risks worth re-checking

The closed ones (Rigor cache / output-channel race, `class A::B`
owner) live in §"Output channel" and §"Owner resolution" above
with their resolution. Two stay live:

- **The Rigor plugin API is still young.** `rigortype` is pinned
  tight (`~> 0.2.1`); the CI matrix runs against that version
  unchanged. README states the supported range explicitly so a
  future `0.3` bump is a deliberate decision, not a silent break.
- **Ruby constant lookup is not fully reproducible from
  syntax.** The fix is structural, not best-effort: the
  `confidence` ladder lets the consumer choose between recall
  (`unresolved` included) and precision
  (`--confidence syntax,zeitwerk,rigor_type`).

## Roadmap

Next phases, in rough priority order. Both are scoped as
self-contained work — they don't unblock each other and can
land independently.

### Edge support — close the recall gap

Today's `Analyzer` captures the structural mixin / inheritance
/ association edges but misses several Rails patterns that
contribute real architectural shape. Each missing edge type
silently shifts the rendered graph away from how the code
actually behaves at runtime, so accuracy improvements here
beat any rendering polish.

In rough effort / value order:

- **`delegate :foo, to: :bar` / `Forwardable`** — extremely
  common in Rails models and form objects. Same analyzer shape
  as `association_edges`: pick up `delegate` call nodes, read
  the `to:` option, emit a `delegate` edge. The `class_name:`
  override pattern from associations applies unchanged.
- **`ActiveSupport::Concern` blocks** — `included do; include
  Foo; end` inside a Concern hides a mixin behind a block. Add
  one `BlockNode` walk so `call_edges` recurses into
  `included do …` / `class_methods do …` bodies and emits the
  enclosed `include` edges against the concern's lexical
  owner.
- **DSL mixin recognition** — `has_secure_password`, `devise
  :database_authenticatable`, `acts_as_*` and similar
  effectively `include` known modules. Plumb a
  `.rigor.yml` `dsl_mixins:` map (`{call_name =>
  target_module}`) with a small set of defaults so the
  Rails-shaped ones work out of the box and projects can
  declare their own.
- **`extend self` / `Module#class_eval(&block)`** — lower
  frequency, lower value. Worth doing only after the above
  three; tackle the same `BlockNode` walk as Concern blocks.

Each new edge kind needs:
1. An `Analyzer` rule + fixture covering the syntactic shape.
2. A row in [the Edge format section in
   how-it-works.md](how-it-works.md) so consumers know what
   to filter on.
3. An entry in the renderer's `KIND_STYLE` tables (Dot /
   Mermaid / class diagram) so the new edge is visually
   distinct from `include` / `inherits`.

### 2D interactive viewer — break the rendering ceiling

`view --output html` currently embeds the graph as Mermaid.
Mermaid's `flowchart` parser starts failing somewhere above
~800 nodes and is unusable above ~1500 — which is where
real-world Rails apps land. The existing `--from` / `--depth`
flags are escape hatches, not a fix.

**Approach**: replace the static Mermaid embed with
[Cytoscape.js](https://js.cytoscape.org/) (MIT, transitive-dep
free), **vendored into the repo at a pinned version with a
sha256 checksum**. No CDN, no npm, no Dependabot auto-bump.
Cytoscape was chosen over a homegrown SVG layer after
weighing the trade-offs — see "Alternatives considered" below.

Features in scope:

- Renders 5k+ nodes without browser strain (Cytoscape's
  selectors + viewport culling do the heavy lifting).
- Live-filters by `kind` / `confidence` / name substring
  without round-tripping through the CLI.
- Click on a node copies its `path:line` to the clipboard;
  `--open-with vscode` opt-in flips the click action to open
  `vscode://file/<path>:<line>`.
- Click on a namespace cluster collapses / expands it
  in-place; the auto-collapse heuristic stays as the default
  starting state. Cytoscape's `compound nodes` give this
  natively.

Deliberately out of scope: 3D rendering (depth perception
costs readability for dependency graphs, no compensating gain),
client-side relayout when the data changes (we re-run `view`
instead), persistent filter state in URL params.

#### Supply-chain controls

The single concession to bringing in a third-party JS library
is paid back with these guardrails:

- Single file vendored under
  `lib/rigor/module_graph/templates/vendor/cytoscape.min.js`,
  shipped in the gem via an updated `spec.files` glob.
- Pinned to a specific upstream release tag, never `latest`.
- `vendor/CHECKSUMS` records the sha256; `rake vendor:verify`
  recomputes and fails on mismatch. Pre-commit runs it on any
  staged file under `lib/**/vendor/**`.
- No CDN reference — the script tag points at the vendored
  copy only, so an HTML artefact opened offline still works.
- Dependabot config explicitly ignores `lib/**/vendor/**` so
  Cytoscape bumps are always a manual PR that re-runs
  `vendor:verify` against a fresh upstream checksum.
- `Content-Security-Policy: default-src 'self'; script-src
  'self' 'unsafe-inline'` in the HTML `<head>`; `'unsafe-inline'`
  is the only concession (we generate inline JSON data) and it
  applies to the vendored file too.
- The viewer file (~100 lines) and the vendored cytoscape are
  the only JS that ever runs; both reviewable in one sitting.

#### Data flow

```
edges.jsonl + nodes.jsonl
    ↓
Viewer::Html.render(edges:, nodes:, ...)
    ↓
HTML template embeds:
  <header>filter controls + search</header>
  <div id="cy">                       ← Cytoscape mount point
  <script type="application/json" id="rmg-data">  ← node + edge dataset
    {"nodes":[...], "edges":[...], "options": {...}}
  </script>
  <script src="vendor/cytoscape.min.js"></script>
  <script>                            ← our ~100-line init
    const data = JSON.parse(document.getElementById('rmg-data').textContent);
    cytoscape({container: document.getElementById('cy'), elements: ..., style: ..., layout: ...});
    // filter / search / click handlers wire into cy.elements().style() and event listeners
  </script>
```

Click metadata sourced from `nodes.jsonl` (the canonical
"where is this constant defined") rather than edges, since
edge dedup ignores `path` / `line` and would lose the
location. `node.path` is normalised to a project-relative
path by default; absolute path requires `--path-mode absolute`.

#### Alternatives considered

| approach | pro | con | verdict |
|---|---|---|---|
| **Cytoscape.js vendored (chosen)** | proven library, native cluster collapse, ~100 LOC of our code, 600KB single-file with zero transitive deps | one third-party library (audited, MIT, no transitive deps) | adopted |
| Homegrown SVG + ~250 LOC of vanilla JS | zero third-party JS | cluster collapse, search index, hit testing all need to be hand-written; ~250 LOC estimate proven optimistic in review | rejected — self-written XSS / event-handler bugs are a worse supply-chain risk than one audited vendor file |
| CDN reference to Cytoscape | no file to vendor | CDN compromise = script injection into every user's view; offline use breaks | rejected outright |
| D3 force layout (~80KB) | smaller vendor footprint | re-runs layout client-side every load; loses dot's hierarchical clarity for inheritance graphs | rejected |
| vis.js | similar feature set to Cytoscape | larger, less stable history, transitive deps | rejected |

#### Phase breakdown

1. **`docs/plan.md`** — this section (current commit).
2. **Vendor cytoscape.min.js** — download, pin version,
   record sha256 in `vendor/CHECKSUMS`, add
   `rake vendor:verify`, update `gemspec.files`.
3. **`Viewer::Html` Ruby class** — builds the HTML page,
   serialises edges + nodes to JSON, wires the
   `<script src="vendor/cytoscape.min.js">` reference. Snapshot
   tests under `test/rigor/module_graph/viewer/`.
4. **Inline init JS** — ~100 lines for Cytoscape config +
   filter / search / click handlers + cluster collapse.
5. **CLI wiring** — `--output html` → `Viewer::Html`;
   `--output mermaid-html` → existing static-Mermaid path
   (renamed but preserved); `--path-mode {relative,absolute,none}`
   default `relative`; `--open-with vscode` opt-in.
6. **Docs / README / CHANGELOG** — update Usage section,
   document the vendor policy in `docs/development.md`, add
   `[Unreleased]` entry.
7. **Performance fixture** — synthetic 1.5k / 5k node
   fixtures committed; manual benchmark numbers recorded in
   the PR description.
