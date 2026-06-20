# Changelog

このプロジェクトの変更履歴。

フォーマットは [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) 準拠、
バージョニングは [Semantic Versioning](https://semver.org/spec/v2.0.0.html) に従う。

カテゴリは次のいずれか:

- **Added** — 新機能
- **Changed** — 既存機能の挙動変更
- **Deprecated** — 将来削除予定
- **Removed** — 削除
- **Fixed** — バグ修正
- **Security** — セキュリティ修正
- **Performance** — 体感に影響する性能改善

## [Unreleased]

## [0.1.0] — 2026-06-20

初回リリース。Phase 0 spike から Phase 5 (UML class diagram) まで通したベースライン。

### Added

- Phase 0: Rigor plugin API spike。`rigortype 0.2.1` + `rbs ~> 4.0` で `node_rule(Prism::ClassNode)` 等が動くことを確認、出力経路を `:info` diagnostic に確定。
- Phase 1: MVP — `inherits` / `include` / `prepend` / `extend` edge 抽出、`Rigor::ModuleGraph::Edge` (Data) と JSONL writer、Graphviz DOT / Mermaid flowchart / Tarjan SCC による cycle 検出。
- Phase 2: Zeitwerk 風 path → constant 推定 (`ZeitwerkResolver`)、namespace collapse (DOT `subgraph cluster_*` / Mermaid `subgraph`)、`const_ref` edge の method body 内抽出 (`include_constant_refs` config)。`confidence` が `syntax` → `zeitwerk` に昇格。
- Phase 3: `scope.type_of` 経由の indirect mixin 解決。`Singleton[X]` carrier から `confidence: rigor_type` に昇格、その他は `unresolved` に degrade。CLI に `--kind` / `--confidence` フィルタを追加。
- Phase 4: `stats` サブコマンド (per-namespace fan-in / fan-out / internal、text / JSON、`--grouping-depth N` / `--limit N`)、Packwerk overlay (`--package` / `--package-root PATH`、`PackwerkOverlay.discover` が `package.yml` を再帰探索)。`Dot` / `Mermaid` の `groups:` 引数で explicit node→cluster mapping をサポート。
- Phase 5: UML クラス図出力。`collect` が `nodes.jsonl` も書く (class / module / method / attribute、visibility 込み)、`VisibilityMap` が bare `private` / `protected` / `public` キーワードを追跡、Rails association edge (`has_many` / `belongs_to` / `has_one` / `has_and_belongs_to_many`、cardinality 付き、`Inflector` で `:invoices → Invoice`)、`Uml::ClassDiagram` レンダラと `class-diagram` サブコマンド (Mermaid `classDiagram` 構文)。フィルタ `--no-methods` / `--no-attributes` / `--public-only` / `--no-private`。
- `view` ワンショットサブコマンド (`rigor-module-graph` 引数なしでも実行可能)。`--output html|mermaid|dot|svg|class-diagram` で出力形式を切替、html は browser で自動 open。
- `--from NAMES --depth N --direction in/out/both` の reachability フィルタ全 reader サブコマンド共有。
- `--edge-scope cluster|walk` フィルタ。`walk` は BFS が実際に通った edge のみ残す (Codex review で命名・semantics 確定)。
- `examples/billing/` showcase (Customer / Invoice / Payment / LineItem + concerns、`build.rb` で `view --output` 経由生成、index.html / class-diagram.html / graph.svg / preview.png を commit)。
- RDoc 対応 (`rake rdoc` / `rake rdoc:preview` / `rake rdoc:server`)。
- minitest + minitest-snapshot のテストハーネス。`UPDATE_SNAPSHOTS=1` で snapshot 再生成。
- SimpleCov による C2 (branch) coverage 計測。`COVERAGE=1 rake test` または `rake coverage`。現状 91.19% (445/488 branches)。
- lefthook で pre-commit に rubocop / betterleaks / rigor / zizmor、pre-push に minitest。
- GitHub Actions CI (`ci.yml`: test + lint + workflow-lint) と Release (`release.yml`: `workflow_dispatch`、trusted publishing 経由で API token 不要)。

### Performance

- `Stats.compute` が 3 周 + `Data#with` cascade → 1 周 + mutable counter array で 2016 edges に対し **139ms → 47ms (3.0×)**。
- `Reachability.walk` を `Set` → `Hash<name, true>` + Array frontier に切替、`direction != :both` のとき必要な adjacency だけ build で 1.7×。
- `Edge#dedup_key` を Array → frozen joined string に変更、Dot / Mermaid render が 1.2×。
- YJIT (`--yjit`) で追加 1.5× 程度。ZJIT は YJIT より遅いケースが多く、推奨は YJIT。

[Unreleased]: https://github.com/Nozomi-Hijikata/rigor-graphviz/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Nozomi-Hijikata/rigor-graphviz/releases/tag/v0.1.0
