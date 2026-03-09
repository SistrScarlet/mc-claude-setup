# mc-claude-setup

Architectury Minecraft mod プロジェクトに Claude Code 開発インフラをセットアップする CLI ツール。

## 構成

- `setup.sh` - メインスクリプト（処理のみ、設定値なし）
- `config.sh` - バージョン・URL等の設定（唯一の定義元）
- `templates/` - ターゲットにコピーされるファイル群
  - `.tmpl` 拡張子 = テンプレート変数あり（`{{JAR_PREFIX}}`, `{{SOURCE_PATH}}`）
  - それ以外 = 静的ファイル（そのままコピー）
- `gradle-snippets/` - build.gradle 手動変更用スニペット
- `local/scripts/` - .gitignored、ユーザーのローカルツール
- `docs/adr/` - 設計判断記録

## コマンド

- `./setup.sh <target-dir>` - 新規セットアップ（自動検出）
- `./setup.sh --update <target-dir>` - テンプレート更新を既存プロジェクトに反映
- `./setup.sh --diff <target-dir>` - テンプレートとの差分確認
- `./setup.sh --dry-run <target-dir>` - 実行内容のプレビュー
- `./setup.sh --force <target-dir>` - 既存ファイルを上書き

## 開発ルール

- バージョン追加・変更は `config.sh` のみ。setup.sh やテンプレートにハードコードしない
- hooks 内の JAR 参照は glob（`google-java-format-*-all-deps.jar`）でバージョン非依存にする
- ファイル追記時は末尾改行を保証する（連結バグ防止）
- テンプレート変数は `validate_vars` で英数字・`_/.-` のみ許可（sed インジェクション防止）
- `.setup-vars` の読み書きに `source` を使わない（`grep`/`cut`/`printf` で安全にパース）

## テスト

- `--dry-run` で全プロジェクトに対して実行し、出力を確認
- `--diff` で全プロジェクトの整合性を一括チェック
- 変更後は既存セットアップ済みプロジェクトと diff 比較
