# rigor-module-graph

Class/module/constant dependency graph for Ruby projects, built on
[Rigor](https://rigor.typedduck.fail/). The class-level counterpart
to Packwerk/Graphwerk: where those look at package boundaries, this
looks at the Ruby nominal graph — inheritance, `include`/`prepend`/
`extend`, and (later) constant references.

![billing example](examples/billing/graph.svg)

The screenshot above is from `examples/billing/`. Open
`examples/billing/index.html` for the live Mermaid version.

## これは何をしているのか

原理的には、Ruby ソースを静的解析して **class / module / constant
をノード、言語上の参照関係をエッジに変換するグラフ抽出器** です。

パイプライン:

1. Rigor が Prism で Ruby を AST にする。
2. plugin の `node_rule` が `ClassNode` / `CallNode` /
   `ConstantReadNode` などを拾う。
3. そのノードが意味する依存を edge に変換する。
   - `class A < B` → `A -> B / inherits`
   - `include M` → `A -> M / include`
   - `Money` という定数参照 → `A -> Money / const_ref`（Phase 2 以降）
4. `from` は `context.ancestors` から lexical owner を組み立てる
   （`class Billing::Invoice` の owner は `Billing::Invoice` まで含む）。
5. `to` は syntax → Zeitwerk 規約 → Rigor 型情報 の順で、できる
   範囲だけ解決する。確度は `confidence` フィールドに残す。
6. edge は Rigor の `:info` diagnostic として流し、`collect`
   サブコマンドが `rule == "edge"` だけ抜いて JSONL 化する。
7. JSONL から DOT / SVG / Mermaid / cycle 検出を派生生成する。

つまり、やっていることは Ruby の **実行結果** を見るのではなく、
Ruby の **名前付き構造** を読んで「この定数はどの定数に依存して
いるか」を近似的に再構成することです。

### これは call graph ではありません

`foo.bar` が実行時に誰を呼ぶかは見ません。`Billing::Invoice`
という名義上の構造が `ApplicationRecord` / `Auditable` / `Money`
などの名前に依存している、という **nominal dependency graph** を
作ります。

Rigor / Prism を使った compiler front-end 的な解析で Ruby の構文
と lexical context を読み、Ruby/Rails の constant dependency を
**confidence 付き edge** として graph に射影する、と言えば一番
近い説明になります。

完全な Ruby constant lookup を再実装しない方針は意図的です。
Rails の設計把握用途なら、誤って `resolved` と言い切るよりも
`syntax` / `zeitwerk` / `rigor_type` / `unresolved` で確度を分けて
出した方が、後で読む人にとって使いやすいです。

## Status

- **Phase 0 (spike)** ✅: Rigor plugin API の検証と出力経路の確定
  （`:info` diagnostic 経由）。
- **Phase 1 (MVP)** ✅: `inherits` / `include` / `prepend` /
  `extend` edges, DOT / Mermaid / cycles output, dedup,
  Rigor-driven AST walk。
- **Phase 2** (planned): Rails path / Zeitwerk owner inference。
- **Phase 3** (planned): Rigor type info で indirect ref を補正。
- **Phase 4** (planned): kind filter / namespace fan-in fan-out。
- 詳細は `plan.md`。

## Installation

```ruby
# Gemfile
gem "rigor-module-graph"
gem "rbs", "~> 4.0"  # rigortype 0.2.x needs rbs 4.x; Ruby 4.0 ships 3.10
```

```sh
bundle install
```

The `rbs ~> 4.0` pin matters: rigortype calls
`RBS::Environment::ClassEntry#each_decl`, which only exists in
rbs 4.x. The Ruby 4.0 stdlib bundles rbs 3.10, so without the pin
the analyzer falls over on the first file.

## Configuration

Add the plugin to your project's `.rigor.yml`:

```yaml
target_ruby: '4.0'
paths:
  - app
  - lib
plugins:
  - gem: rigor-module-graph
```

## Usage

Three reader subcommands and one collector:

```sh
# Run `rigor check` and write edges JSONL (default: .rigor/module_graph/edges.jsonl)
bundle exec rigor-module-graph collect

# Render the graph
bundle exec rigor-module-graph dot     .rigor/module_graph/edges.jsonl > graph.dot
bundle exec rigor-module-graph mermaid .rigor/module_graph/edges.jsonl > graph.mmd
dot -Tsvg graph.dot -o graph.svg

# Detect cycles (exit 1 if any are found)
bundle exec rigor-module-graph cycles  .rigor/module_graph/edges.jsonl
bundle exec rigor-module-graph cycles --only include,inherits edges.jsonl
```

`collect` shells out to `rigor check --format json --no-cache` and
filters diagnostics on `source_family == "plugin.module-graph"` +
`rule == "edge"`, so re-running is deterministic and there's no
on-disk side-effect from the plugin itself.

`dot` / `mermaid` / `cycles` accept a file argument or read stdin.

## Edge format

Each edge in the JSONL file looks like:

```json
{"from":"Billing::Invoice","to":"ApplicationRecord","kind":"inherits","path":"app/models/billing/invoice.rb","line":2,"column":3,"confidence":"syntax"}
```

- `kind`: `inherits` / `include` / `prepend` / `extend` /
  `const_ref` (the last one is reserved for Phase 2).
- `confidence`: `syntax` / `zeitwerk` / `rigor_type` /
  `unresolved`. MVP only emits `syntax`.

The renderers dedup by `(from, to, kind, confidence)` so two
`include Foo` on the same class across files collapse to one edge.

## Development

```sh
bundle install
bundle exec rake test
UPDATE_SNAPSHOTS=1 bundle exec rake test   # to refresh snapshots
```

The test suite covers:

- `ConstantName`, `Edge`, `Analyzer`, `CycleDetector` as unit tests
- `Dot`, `Mermaid` rendering via `minitest-snapshot`
- An integration test that boots the real `rigor` binary against
  `test/fixtures/rails_app/` and snapshots the edges JSONL

## Compatibility

- Ruby `>= 4.0.0, < 4.1`
- rigortype `~> 0.2.1`
- rbs `~> 4.0`
