# mc-claude-setup

Architectury (Fabric/Forge) Minecraft mod プロジェクトに Claude Code 開発インフラを一括セットアップするツール。

## セットアップ内容

- **コード品質**: google-java-format 自動整形、Checkstyle、SpotBugs
- **フック**: Java 編集後の自動フォーマット、コミット前のバグチェック＋テスト
- **API調査**: Loom キャッシュ内のデコンパイル済みソースJAR検索ツール
- **スキル**: ドキュメント管理 (`/doc`)、リリースワークフロー (`/release`)
- **エージェント**: Minecraft/Architectury API 調査用エージェント

## 使い方

```bash
git clone <this-repo> mc-claude-setup
cd mc-claude-setup

# 新規セットアップ（自動検出）
./setup.sh /path/to/my-architectury-mod

# オプション指定
./setup.sh /path/to/my-mod --jar-prefix MyMod --source-path common/src/main/java/com/example/mymod/

# 既存セットアップの更新
./setup.sh --update /path/to/my-mod
```

## CLIオプション

| オプション | 説明 |
|---|---|
| `--jar-prefix PREFIX` | JAR名プレフィックス。未指定時は `archives_base_name` から自動検出 |
| `--source-path PATH` | ソースコードパス。未指定時はディレクトリ構造から自動検出 |
| `--force` | 既存ファイルを確認なしで上書き |
| `--update` | `.setup-vars` を使って既存セットアップを更新 |
| `--skip-download` | ツールJARのダウンロードをスキップ |
| `--skip-gradle` | Gradleスニペット案内の表示をスキップ |
| `--dry-run` | ファイル操作を行わず、実行内容のみ表示 |
| `--diff` | セットアップ済みプロジェクトとテンプレートの差分を表示 |

## build.gradle の変更

セットアップスクリプトは `build.gradle` を自動編集しません。
`gradle-snippets/` のスニペットを参考に手動で追加してください。

ツールバージョンは `gradle.properties` に自動追記されるため、build.gradle からはプロパティ参照で使用します。

### root build.gradle

2箇所の変更が必要です。

**1. `plugins {}` ブロック**に2行追加（既存プラグインの後に）:

```groovy
plugins {
    // ... 既存のプラグイン ...
    id "com.diffplug.spotless" version "${spotless_version}" apply false
    id "com.github.spotbugs" version "${spotbugs_version}" apply false
}
```

**2. `allprojects {}` ブロック**内の既存 `apply plugin:` 行の直後に、品質ツール設定を追加:

```groovy
allprojects {
    apply plugin: "java"
    apply plugin: "architectury-plugin"
    apply plugin: "maven-publish"
    // ↓ ここから追加
    apply plugin: "com.diffplug.spotless"
    apply plugin: "checkstyle"
    apply plugin: "com.github.spotbugs"

    checkstyle {
        toolVersion = rootProject.checkstyle_version
        configFile = rootProject.file("config/checkstyle/checkstyle.xml")
        ignoreFailures = true
        sourceSets = [project.sourceSets.main]
    }

    spotbugs {
        ignoreFailures = true
        effort = com.github.spotbugs.snom.Effort.valueOf("DEFAULT")
        reportLevel = com.github.spotbugs.snom.Confidence.valueOf("MEDIUM")
        excludeFilter = rootProject.file("config/spotbugs/exclude.xml")
    }

    tasks.withType(com.github.spotbugs.snom.SpotBugsTask) {
        reports {
            html.required = true
            xml.required = true
        }
    }

    spotless {
        java {
            target "src/*/java/**/*.java"
            googleJavaFormat(rootProject.gjf_version)
            removeUnusedImports()
            trimTrailingWhitespace()
            endWithNewline()
        }
    }
    // ↑ ここまで追加

    // ... 既存の archivesBaseName, version, group 等 ...
}
```

### common/build.gradle

2箇所の変更が必要です。

**1. `dependencies {}` ブロック**内の末尾に2行追加:

```groovy
dependencies {
    // ... 既存の依存 ...

    testImplementation "org.junit.jupiter:junit-jupiter:${rootProject.junit_version}"
    testRuntimeOnly "org.junit.platform:junit-platform-launcher:${rootProject.junit_platform_version}"
}
```

**2. トップレベルに `test {}` ブロック**を追加（`dependencies {}` の後など）:

```groovy
test {
    useJUnitPlatform()
}
```

## ローカルツール

`local/scripts/` にスクリプトを配置すると、セットアップ時にターゲットの `.claude/scripts/` にコピーされます。
このディレクトリは `.gitignore` で除外されているため、公開リポジトリには含まれません。

```bash
# 例: Dropbox アップロードスクリプトを追加
cp ~/my-scripts/dropbox-upload.py local/scripts/
./setup.sh /path/to/my-mod  # 次回セットアップ時に自動コピー
```

## セットアップ後の作業

1. `build.gradle` の変更（上記参照）
2. `CLAUDE.md` の作成（プロジェクト固有のアーキテクチャ説明、コーディング規約など）
3. Claude Code でプロジェクトを開き、必要に応じて `.claude/settings.local.json` を設定

## ツールバージョン

バージョンは `config.sh` で一元管理されています。変更する場合は `config.sh` を編集してください。

| ツール | config.sh 変数 | gradle.properties キー |
|---|---|---|
| google-java-format | `GJF_VERSION` | `gjf_version` |
| checkstyle | `CHECKSTYLE_VERSION` | `checkstyle_version` |
| Spotless (Gradle plugin) | `SPOTLESS_VERSION` | `spotless_version` |
| SpotBugs (Gradle plugin) | `SPOTBUGS_PLUGIN_VERSION` | `spotbugs_version` |
| JUnit Jupiter | `JUNIT_VERSION` | `junit_version` |
| JUnit Platform | `JUNIT_PLATFORM_VERSION` | `junit_platform_version` |
