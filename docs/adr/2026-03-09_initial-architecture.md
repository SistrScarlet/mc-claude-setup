# mc-claude-setup 初期アーキテクチャ

## ステータス

承認済み

## コンテキスト

複数の Architectury Minecraft mod プロジェクト（LMRB, LMML, ActionArms, ZabutonR 等）に対して、Claude Code 開発インフラ（フック、スクリプト、スキル、エージェント、品質ツール設定）を個別に手動セットアップしていた。プロジェクト間でファイルが乖離しやすく、新規プロジェクトへの導入コストも高かった。

## 決定

セットアップツールを独立した git リポジトリとして作成し、CLI スクリプトで一括導入・更新・差分確認を行う。

### 設計方針

1. **CLI ファースト** — インタラクティブプロンプトなし。Claude Code や他のエージェントツールから実行可能
2. **設定と処理の分離** — バージョン等のパラメータは `config.sh` に集約し、`setup.sh` は処理のみ
3. **テンプレート + 自動検出** — プロジェクト固有値（JAR_PREFIX, SOURCE_PATH）は `gradle.properties` やディレクトリ構造から自動検出。テンプレート変数 `{{VAR}}` で置換
4. **バージョンの一元管理** — `config.sh` → `gradle.properties` → `build.gradle`（プロパティ参照）。hooks は glob でJAR検索（バージョン非依存）
5. **冪等性** — 既存ファイルはスキップ（`--force` で上書き）、`.gitignore` / `gradle.properties` は重複追記防止
6. **ローカルツール拡張** — `local/scripts/` にユーザー独自スクリプトを配置可能（`.gitignore` で除外）

### リポジトリ構成

```
mc-claude-setup/
├── setup.sh              # メインスクリプト（処理）
├── config.sh             # バージョン・URL定義（設定）
├── README.md
├── templates/
│   ├── claude/            # .claude/ に配置されるファイル群
│   │   ├── settings.json
│   │   ├── hooks/         # pre-commit.sh, post-java-edit.sh
│   │   ├── scripts/       # jar-search.sh, spotbugs-report.py
│   │   ├── skills/        # doc/, release/（.tmpl）
│   │   └── agents/        # mc-api-research.md（.tmpl）
│   └── config/            # checkstyle/, spotbugs/
├── gradle-snippets/       # build.gradle 手動変更用スニペット
├── local/scripts/         # .gitignored、ローカルツール
└── docs/
```

### 対象外とした機能

- **build.gradle の自動編集** — プロジェクト毎に構造が異なるため、スニペット提示＋手動適用とした
- **Notion タスクボード連携** — プロジェクト固有。汎用ツールには含めない
- **Dropbox アップロード** — `local/scripts/` で個別管理
- **GameTest スキル** — LMRB 固有。必要なプロジェクトで個別追加

### セキュリティ対策

- `.setup-vars` の読み込みに `source` を使わず `grep` + `cut` で安全にパース
- テンプレート変数は `validate_vars` で英数字・`_/.-` のみ許可（sed インジェクション防止）
- `.setup-vars` の書き込みは `printf` で行い、シェル変数展開を防止

## 根拠

### テンプレートリポジトリ方式を採用しなかった理由

GitHub のテンプレートリポジトリ機能は新規プロジェクト作成時のみ有効で、既存プロジェクトへの後付け導入や、テンプレート更新時の差分適用ができない。

### build.gradle を自動編集しない理由

各プロジェクトで Loom バージョン、subprojects の構造、既存プラグインが異なる。sed/awk での自動挿入は脆く、誤編集のリスクが高い。スニペット＋README での詳細ガイドにより、エージェントでも人間でも正確に適用可能。

### バージョンを gradle.properties 経由にした理由

Minecraft mod は複数バージョン（1.20.1, 1.18.2 等）のブランチを並行開発することがある。ツールバージョンを `gradle.properties` に置くことで、ブランチ間で `build.gradle` を共通に保ちつつ、バージョン違いを properties で吸収できる。hooks は glob で JAR を検索するためバージョン変更の影響を受けない。

## 影響

- 新規プロジェクトへの Claude Code インフラ導入が `setup.sh` 1コマンド＋build.gradle 編集で完了
- テンプレート更新時は `setup.sh --update` で全プロジェクトに反映可能
- `--diff` で乖離検出が可能になり、プロジェクト間の一貫性を維持しやすい
- `config.sh` のバージョン変更のみで全プロジェクトのツールバージョンを統一更新可能
