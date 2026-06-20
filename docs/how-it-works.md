# How it works

A short tour of the pipeline that turns Ruby source into a
[Mermaid](https://mermaid.js.org/) / [Graphviz](https://graphviz.org/)
graph. The forward-looking design notes live in
[the design plan](plan.md); current limitations live in
[the limitations doc](limitation.md).

## The pipeline

In principle this is a static-analysis tool that turns Ruby
source into a graph whose **nodes are classes / modules /
constants** and whose **edges are the references the language
itself spells out**.

1. Rigor parses Ruby into an AST with
   [Prism](https://github.com/ruby/prism).
2. The plugin's `node_rule`s pick up `ClassNode` / `CallNode`
   / `ConstantReadNode` and friends.
3. Each interesting node becomes one or more edges:
   - `class A < B` → `A -> B / inherits`
   - `include M` → `A -> M / include`
   - a `Money` constant reference → `A -> Money / const_ref`
     (gated on `include_constant_refs: true`)
4. `from` is the lexical owner, assembled by walking
   `context.ancestors` — so `class Billing::Invoice` produces
   `Billing::Invoice`, not just `Invoice`.
5. `to` is resolved through a confidence ladder: `syntax` →
   `zeitwerk` (path agrees with the lexical name) → `rigor_type`
   (Rigor's `scope.type_of` returned a `Singleton[X]` carrier).
   Whatever couldn't be pinned down stays visible at
   `confidence: "unresolved"` rather than being dropped.
6. Every edge ships as a Rigor `:info` diagnostic. The `collect`
   subcommand filters them on `rule == "edge"` and writes JSONL
   to `.rigor/module_graph/edges.jsonl`.
7. DOT, SVG, Mermaid, Mermaid `classDiagram`, cycle detection,
   and per-namespace statistics all read from that JSONL.

So this is not a tool that watches what Ruby *does at runtime*.
It reads Ruby's *named structure* and reconstructs,
approximately, "which constants depend on which other
constants".

## This is not a call graph

`foo.bar`'s runtime target isn't tracked. What is tracked: the
fact that the `Billing::Invoice` name depends on the
`ApplicationRecord` / `Auditable` / `Money` names. That is a
**nominal dependency graph** — a compiler-front-end-style view
of the project's syntactic and lexical structure, projected
into edges with explicit `confidence`.

Not re-implementing Ruby's constant lookup is deliberate. For
understanding a Rails codebase's shape it's more useful to
leave each edge tagged `syntax` / `zeitwerk` / `rigor_type` /
`unresolved` than to fake a `resolved` answer and silently get
it wrong.

## Why this design vs. the alternatives

| tool | unit | technique |
|---|---|---|
| **rigor-module-graph** | Ruby constant | static AST, confidence-tagged |
| Packwerk / Graphwerk | package | static, package-boundary lint |
| Rubrowser / RailRoady | method call | static, runtime-leaning |

Packwerk / Graphwerk look at package boundaries, which is the
right unit when the project already has packages drawn. This
tool's angle is one level down — the **nominal** graph that
exists in any Ruby project regardless of whether anyone drew
packages.

Rubrowser / RailRoady aim at the call graph (who invokes whom);
useful for tracing a specific execution path, less so for
"what's the shape of this codebase". The confidence ladder is
what lets us leave the unresolved edges in the picture without
lying about them.
