# mc-research 統合設計 (2026-08-08)

jar 調査系サブエージェント 2 種 (mc-api-research / regression-research) の統合と、
jar-search.sh の改善、setup.sh 配線・全プロジェクト配布までの設計。

## 背景と課題

現状は jar 調査を行うサブエージェントが 2 つ存在する:

- `mc-api-research` (haiku, memory: local) — API 調査。jar-search.sh の find/grep/read を使用
- `regression-research` (sonnet) — 移植回帰バグ調査。doctor/sig/bytecode/apidiff も使用

確認された課題 (3 点すべて該当):

1. **役割の重複・境界が曖昧** — どちらも jar を調べるエージェントで、委譲先の判断に迷う
2. **調査品質の不足** — 特に haiku の mc-api-research の報告の質に不満
3. **メンテナンスの二重化** — jar-search.sh の使い方など同じ知識が 2 箇所に重複

また regression-research の setup.sh 配線が gametest WIP と混在して未コミットのまま
27 日間停滞している。

## 設計

### 1. エージェント統合: mc-research

新エージェント `mc-research` に一本化する。

- テンプレート: `templates/claude/agents/mc-research.md.tmpl`
- frontmatter: `model: sonnet` / `tools: Bash, Glob, Grep, Read` / `memory: local`
- description: 旧 2 エージェントの発火例を統合。API 調査 (機能実装前の API 理解、
  Goal/ネットワーキング等のシステム調査) と回帰調査 (「1.21 にしたら壊れた」
  「移植前は動いていた」) の両方で proactive に起動させる
- 本文は実行環境の記述のみに薄く保つ:
  - 最初に `.claude/skills/mc-research/SKILL.md` を Read してワークフローに従う
  - 調査対象パス (`{{SOURCE_PATH}}`, TODO.md, docs/research/, docs/log/, jar-search.sh, git ブランチ)
  - 制約: read-only (対象コード・設定・ドキュメント不変更)、gradle タスク実行禁止、
    行き詰まったら事実と残仮説を整理して報告
  - ライセンス配慮の出力ルール: コードブロックはシグネチャのみ許可、
    デコンパイルソースの転載・再構成禁止 (旧 mc-api-research から継承)
- メモリ: 既存プロジェクトの `.claude/agent-memory-local/mc-api-research/` を
  `mc-research/` に改名して引き継ぐ (蓄積済み API 知識を保持)

### 2. スキル統合: .claude/skills/mc-research/SKILL.md

調査ワークフローの知識をスキル 1 枚に統合する (SSOT)。構成:

1. **タスク種別の判断基準** (冒頭) — API 調査ワークフローと回帰調査ワークフローの使い分け
2. **共通部** — 調査の原則 (バニラ API を記憶で断定しない、jar で裏取り)、
   jar-search.sh の使い方 (`doctor` で状態判断 → ソース系 find/grep/read または
   javap 系 sig/bytecode/apidiff、`callers` を含む)
3. **ワークフロー A: API 調査** — 旧 mc-api-research の調査手法
   (既存コードのパターン確認 → API クラス追跡 → クロスプラットフォーム考慮) と報告形式
   (Summary / Key Classes / API Details / Usage Pattern / Cross-Platform Notes / Caveats)
4. **ワークフロー B: 回帰調査** — 旧 regression-research スキルの内容を維持
   (症状整理 → 移植 diff → jar 裏取り → 仮説 3 点照合 → 報告形式)

旧テンプレート 3 点は削除する:
`templates/claude/agents/mc-api-research.md.tmpl`、
`templates/claude/agents/regression-research.md.tmpl`、
`templates/claude/skills/regression-research/SKILL.md`

### 3. jar-search.sh 改善

#### callers サブコマンド (逆参照)

```
jar-search.sh callers <Class> [method] [--dir <subdir>] [--all]
```

- 対象 jar 群を tmp に展開し、`.class` ファイルの定数プールを binary grep して
  対象クラスを参照する候補クラスを列挙する
- method 指定時は候補クラスのみ `javap -c` し、
  `invoke* ... Method <Class>.<method>` の実呼び出し行を出力して確認する
- 出力: 参照元クラス一覧 (method 指定時は呼び出し箇所のバイトコード行付き)
- 性能目標: Minecraft 本体 jar 全体で数十秒以内。遅い場合は `--dir` 絞り込みを案内

#### 使い勝手の磨き込み (実測後に確定)

決め打ちせず、実測 (セクション 5) で観測された詰まりから確定する。現時点の候補メモ:

- `resolve_jar` の複数マッチ時にエラーではなく最有力を自動選択
  (sig/bytecode 系の `resolve_class_entry` と挙動を統一)
- jar 名指定なしの横断 `grep`

### 4. setup.sh 配線・配布

- 未コミットの regression-research 配線 hunk はコミットせず、mc-research 用の配線に
  書き換える。gametest WIP と CLAUDE.md.init の hunk は今回触らず未コミットのまま残す
- setup.sh へ追加:
  - `create_directories`: `.claude/skills/mc-research`
  - `copy_static_files`: mc-research SKILL.md
  - `process_templates`: mc-research.md.tmpl
  - `run_diff`: mc-research の SKILL.md エントリ (旧配線で漏れていた skill の diff 対象化)
  - `init_agent_memory`: メモリディレクトリ名を mc-research に変更
  - **マイグレーション処理** (新規関数): 旧 `.claude/agents/mc-api-research.md`、
    `.claude/agents/regression-research.md`、`.claude/skills/regression-research/` を削除し、
    `.claude/agent-memory-local/mc-api-research/` があれば `mc-research/` に改名
- 配布: セットアップ済み全プロジェクトに `--update` を適用し、各プロジェクトでコミット

### 5. 検証 (実測駆動)

1. setup.sh: `--dry-run` / `--diff` を全プロジェクトで実行して出力確認
2. 回帰調査の品質: LMML のサウンド 2 バグ (2026-07-12 eval の ground truth) を
   新 mc-research エージェントに再調査させ、正答・所要を旧実測と比較
3. API 調査の実測: API 調査系タスクを 1 件実行し、callers を含むツールの
   詰まり箇所を観測する
4. 観測結果から磨き込み項目を確定して実装し、必要なら再実測

## スコープ外

- gametest スキルの導入完了 (別 WIP のまま)
- CLAUDE.md.init テンプレートの配線コミット (別 WIP のまま)
- Opus 等 sonnet 以外のモデル選定の検討
