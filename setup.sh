#!/usr/bin/env bash
# mc-claude-setup - Architectury Minecraft mod プロジェクトに
# Claude Code 開発インフラをセットアップするスクリプト
#
# Usage:
#   setup.sh <target-dir> [options]
#   setup.sh --update <target-dir>
#
# Options:
#   --jar-prefix PREFIX      JAR名のプレフィックス (例: LMRB)
#   --source-path PATH       ソースコードパス (例: common/src/main/java/net/sistr/mymod/)
#   --force                  既存ファイルを確認なしで上書き
#   --update                 既存セットアップの更新（.setup-vars から変数を読む）
#   --skip-download          ツールJARのダウンロードをスキップ
#   --skip-gradle            Gradleスニペットの表示をスキップ
#   --dry-run                実際のファイル操作を行わない
#   --diff                   セットアップ済みプロジェクトとテンプレートの差分を表示
#   --help                   ヘルプ表示

set -euo pipefail

# スクリプト自身のディレクトリ
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 設定ファイル読み込み
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
SNIPPETS_DIR="$SCRIPT_DIR/gradle-snippets"
LOCAL_DIR="$SCRIPT_DIR/local"

# デフォルト値
TARGET_DIR=""
JAR_PREFIX=""
SOURCE_PATH=""
FORCE=false
UPDATE=false
SKIP_DOWNLOAD=false
SKIP_GRADLE=false
DRY_RUN=false
DIFF_MODE=false

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $*"; }

usage() {
  cat <<'EOF'
Usage: setup.sh <target-dir> [options]

Architectury Minecraft mod プロジェクトに Claude Code 開発インフラをセットアップします。

Options:
  --jar-prefix PREFIX      JAR名のプレフィックス (例: LMRB)
  --source-path PATH       ソースコードパス (例: common/src/main/java/net/sistr/mymod/)
  --force                  既存ファイルを確認なしで上書き
  --update                 既存セットアップの更新（.setup-vars から変数を読む）
  --skip-download          ツールJARのダウンロードをスキップ
  --skip-gradle            Gradleスニペットの表示をスキップ
  --dry-run                実際のファイル操作を行わない
  --diff                   セットアップ済みプロジェクトとテンプレートの差分を表示
  --help                   ヘルプ表示

Examples:
  # 新規セットアップ
  setup.sh /path/to/my-mod --jar-prefix MyMod --source-path common/src/main/java/com/example/mymod/

  # 自動検出でセットアップ
  setup.sh /path/to/my-mod

  # 既存セットアップの更新
  setup.sh --update /path/to/my-mod

  # 差分確認
  setup.sh --diff /path/to/my-mod

Template Variables:
  JAR_PREFIX     - JARファイル名のプレフィックス。gradle.properties の archives_base_name から自動検出
  SOURCE_PATH    - common/src/main/java/ 配下のソースパス。ディレクトリ構造から自動検出
EOF
  exit 0
}

# 引数パース
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --jar-prefix)    [ $# -ge 2 ] || { log_error "--jar-prefix requires a value"; exit 1; }; JAR_PREFIX="$2"; shift 2 ;;
      --source-path)   [ $# -ge 2 ] || { log_error "--source-path requires a value"; exit 1; }; SOURCE_PATH="$2"; shift 2 ;;
      --force)         FORCE=true; shift ;;
      --update)        UPDATE=true; shift ;;
      --skip-download) SKIP_DOWNLOAD=true; shift ;;
      --skip-gradle)   SKIP_GRADLE=true; shift ;;
      --dry-run)       DRY_RUN=true; shift ;;
      --diff)          DIFF_MODE=true; shift ;;
      --help|-h)       usage ;;
      -*)              log_error "Unknown option: $1"; exit 1 ;;
      *)
        if [ -z "$TARGET_DIR" ]; then
          TARGET_DIR="$1"
        else
          log_error "Unexpected argument: $1"
          exit 1
        fi
        shift
        ;;
    esac
  done

  if [ -z "$TARGET_DIR" ]; then
    log_error "Target directory is required"
    echo "Usage: setup.sh <target-dir> [options]"
    exit 1
  fi

  # 相対パスを絶対パスに変換
  TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
    log_error "Target directory does not exist: $TARGET_DIR"
    exit 1
  }
}

# テンプレート変数のバリデーション（sed インジェクション防止）
validate_vars() {
  local var_regex='^[a-zA-Z0-9_/.\-]+$'
  if [ -n "$JAR_PREFIX" ] && ! echo "$JAR_PREFIX" | grep -qE "$var_regex"; then
    log_error "JAR_PREFIX contains invalid characters: $JAR_PREFIX"
    log_error "Allowed: alphanumeric, underscore, hyphen, dot"
    exit 1
  fi
  if [ -n "$SOURCE_PATH" ] && ! echo "$SOURCE_PATH" | grep -qE "$var_regex"; then
    log_error "SOURCE_PATH contains invalid characters: $SOURCE_PATH"
    log_error "Allowed: alphanumeric, underscore, hyphen, dot, slash"
    exit 1
  fi
}

# プロジェクト検証
validate_project() {
  local errors=0

  if [ ! -f "$TARGET_DIR/build.gradle" ]; then
    log_error "build.gradle not found in $TARGET_DIR"
    errors=$((errors + 1))
  fi

  if [ ! -f "$TARGET_DIR/gradle.properties" ]; then
    log_error "gradle.properties not found in $TARGET_DIR"
    errors=$((errors + 1))
  fi

  if [ ! -d "$TARGET_DIR/common" ]; then
    log_error "common/ directory not found (not an Architectury project?)"
    errors=$((errors + 1))
  fi

  if [ "$errors" -gt 0 ]; then
    exit 1
  fi
}

# 自動検出
auto_detect() {
  # JAR_PREFIX: gradle.properties の archives_base_name から
  if [ -z "$JAR_PREFIX" ]; then
    JAR_PREFIX=$(grep "^archives_base_name=" "$TARGET_DIR/gradle.properties" 2>/dev/null | cut -d= -f2 || true)
    if [ -n "$JAR_PREFIX" ]; then
      log_info "JAR_PREFIX auto-detected: $JAR_PREFIX"
    else
      log_warn "JAR_PREFIX could not be detected. Use --jar-prefix to set it."
      JAR_PREFIX="MyMod"
    fi
  fi

  # SOURCE_PATH: common/src/main/java/ 配下のパッケージルートを検出
  # 全 .java ファイルのディレクトリパスから共通プレフィックスを求める
  if [ -z "$SOURCE_PATH" ]; then
    local java_base="$TARGET_DIR/common/src/main/java"
    if [ -d "$java_base" ]; then
      local common_prefix
      common_prefix=$(find "$java_base" -name "*.java" -type f 2>/dev/null \
        | sed "s|$TARGET_DIR/||" \
        | sed 's|/[^/]*\.java$||' \
        | sort -u \
        | awk '
          NR==1 { prefix=$0; next }
          {
            while (substr($0, 1, length(prefix)) != prefix) {
              sub(/[^/]*\/?$/, "", prefix)
            }
          }
          END { print prefix }
        ')
      # 末尾スラッシュを正規化
      common_prefix="${common_prefix%/}"
      if [ -n "$common_prefix" ] && [ -d "$TARGET_DIR/$common_prefix" ]; then
        SOURCE_PATH="${common_prefix}/"
        log_info "SOURCE_PATH auto-detected: $SOURCE_PATH"
      fi
    fi
    if [ -z "$SOURCE_PATH" ]; then
      log_warn "SOURCE_PATH could not be detected. Use --source-path to set it."
      SOURCE_PATH="common/src/main/java/"
    fi
  fi
}

# --update モード: .setup-vars から変数を読む（source を使わず安全にパース）
load_setup_vars() {
  local vars_file="$TARGET_DIR/.claude/.setup-vars"
  if [ ! -f "$vars_file" ]; then
    log_error ".claude/.setup-vars not found. Run initial setup first (without --update)."
    exit 1
  fi
  local val
  val=$(grep "^JAR_PREFIX=" "$vars_file" | head -1 | cut -d= -f2-)
  [ -n "$val" ] && JAR_PREFIX="$val"
  val=$(grep "^SOURCE_PATH=" "$vars_file" | head -1 | cut -d= -f2-)
  [ -n "$val" ] && SOURCE_PATH="$val"
  log_info "Loaded variables from .setup-vars"
  FORCE=true  # update モードでは常に上書き
}

# ファイルコピー（上書き確認付き）
copy_file() {
  local src="$1"
  local dst="$2"

  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] $dst"
    return
  fi

  mkdir -p "$(dirname "$dst")"

  if [ -f "$dst" ] && [ "$FORCE" != true ]; then
    log_warn "Already exists: ${dst#$TARGET_DIR/} (skipped, use --force to overwrite)"
    return
  fi

  cp "$src" "$dst"
  echo "  ${dst#$TARGET_DIR/}"
}

# テンプレート処理（変数置換してコピー）
process_template() {
  local src="$1"
  local dst="$2"

  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] $dst (from template)"
    return
  fi

  mkdir -p "$(dirname "$dst")"

  if [ -f "$dst" ] && [ "$FORCE" != true ]; then
    log_warn "Already exists: ${dst#$TARGET_DIR/} (skipped, use --force to overwrite)"
    return
  fi

  sed \
    -e "s|{{JAR_PREFIX}}|${JAR_PREFIX}|g" \
    -e "s|{{SOURCE_PATH}}|${SOURCE_PATH}|g" \
    "$src" > "$dst"
  echo "  ${dst#$TARGET_DIR/} (from template)"
}

# ディレクトリ構造の作成
create_directories() {
  log_step "Creating directory structure..."
  local dirs=(
    ".claude/hooks"
    ".claude/scripts"
    ".claude/skills/doc"
    ".claude/skills/release"
    ".claude/agents"
    ".claude/tools"
    ".claude/agent-memory-local/mc-api-research"
    "config/checkstyle"
    "config/spotbugs"
    "docs/adr"
    "docs/plan"
    "docs/research"
  )
  for d in "${dirs[@]}"; do
    if [ "$DRY_RUN" = true ]; then
      echo "  [dry-run] mkdir $d"
    else
      mkdir -p "$TARGET_DIR/$d"
    fi
  done
}

# 静的ファイルのコピー
copy_static_files() {
  log_step "Copying static files..."

  copy_file "$TEMPLATES_DIR/claude/settings.json" "$TARGET_DIR/.claude/settings.json"
  copy_file "$TEMPLATES_DIR/claude/hooks/pre-commit.sh" "$TARGET_DIR/.claude/hooks/pre-commit.sh"
  copy_file "$TEMPLATES_DIR/claude/hooks/post-java-edit.sh" "$TARGET_DIR/.claude/hooks/post-java-edit.sh"
  copy_file "$TEMPLATES_DIR/claude/scripts/jar-search.sh" "$TARGET_DIR/.claude/scripts/jar-search.sh"
  copy_file "$TEMPLATES_DIR/claude/scripts/spotbugs-report.py" "$TARGET_DIR/.claude/scripts/spotbugs-report.py"
  copy_file "$TEMPLATES_DIR/claude/skills/doc/SKILL.md" "$TARGET_DIR/.claude/skills/doc/SKILL.md"
  copy_file "$TEMPLATES_DIR/config/checkstyle/checkstyle.xml" "$TARGET_DIR/config/checkstyle/checkstyle.xml"
  copy_file "$TEMPLATES_DIR/config/spotbugs/exclude.xml" "$TARGET_DIR/config/spotbugs/exclude.xml"

  # 実行権限の付与
  if [ "$DRY_RUN" != true ]; then
    chmod +x "$TARGET_DIR/.claude/hooks/pre-commit.sh" 2>/dev/null || true
    chmod +x "$TARGET_DIR/.claude/hooks/post-java-edit.sh" 2>/dev/null || true
    chmod +x "$TARGET_DIR/.claude/scripts/jar-search.sh" 2>/dev/null || true
  fi
}

# テンプレートファイルの処理
process_templates() {
  log_step "Processing template files..."

  process_template \
    "$TEMPLATES_DIR/claude/skills/release/SKILL.md.tmpl" \
    "$TARGET_DIR/.claude/skills/release/SKILL.md"

  process_template \
    "$TEMPLATES_DIR/claude/agents/mc-api-research.md.tmpl" \
    "$TARGET_DIR/.claude/agents/mc-api-research.md"
}

# エージェントメモリの初期化
init_agent_memory() {
  local memory_file="$TARGET_DIR/.claude/agent-memory-local/mc-api-research/MEMORY.md"
  if [ ! -f "$memory_file" ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "  [dry-run] $memory_file (empty MEMORY.md)"
    else
      echo "# MC API Research Memory" > "$memory_file"
      echo "" >> "$memory_file"
      echo "<!-- This file persists across conversations. Keep under 200 lines. -->" >> "$memory_file"
      echo "  ${memory_file#$TARGET_DIR/} (initialized)"
    fi
  fi
}

# ローカルスクリプトのコピー
copy_local_scripts() {
  if [ ! -d "$LOCAL_DIR/scripts" ]; then
    return
  fi

  local has_files=false
  for f in "$LOCAL_DIR/scripts/"*; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = ".gitkeep" ] && continue
    has_files=true
    break
  done

  if [ "$has_files" = true ]; then
    log_step "Copying local scripts..."
    for f in "$LOCAL_DIR/scripts/"*; do
      [ -f "$f" ] || continue
      [ "$(basename "$f")" = ".gitkeep" ] && continue
      copy_file "$f" "$TARGET_DIR/.claude/scripts/$(basename "$f")"
      if [ "$DRY_RUN" != true ]; then
        chmod +x "$TARGET_DIR/.claude/scripts/$(basename "$f")" 2>/dev/null || true
      fi
    done
  fi
}

# ツールJARのダウンロード
download_tools() {
  if [ "$SKIP_DOWNLOAD" = true ]; then
    log_info "Skipping tool download (--skip-download)"
    return
  fi

  log_step "Downloading tools..."

  local gjf_jar="$TARGET_DIR/.claude/tools/google-java-format-${GJF_VERSION}-all-deps.jar"
  local cs_jar="$TARGET_DIR/.claude/tools/checkstyle-${CHECKSTYLE_VERSION}-all.jar"

  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] download google-java-format-${GJF_VERSION}-all-deps.jar"
    echo "  [dry-run] download checkstyle-${CHECKSTYLE_VERSION}-all.jar"
    return
  fi

  # google-java-format
  if [ -f "$gjf_jar" ]; then
    log_info "google-java-format already exists, skipping"
  else
    echo "  Downloading google-java-format ${GJF_VERSION}..."
    curl -fSL --progress-bar -o "$gjf_jar" "$GJF_URL" || {
      log_error "Failed to download google-java-format"
      rm -f "$gjf_jar"
      return 1
    }
    echo "  google-java-format ${GJF_VERSION} downloaded"
  fi

  # checkstyle
  if [ -f "$cs_jar" ]; then
    log_info "checkstyle already exists, skipping"
  else
    echo "  Downloading checkstyle ${CHECKSTYLE_VERSION}..."
    curl -fSL --progress-bar -o "$cs_jar" "$CS_URL" || {
      log_error "Failed to download checkstyle"
      rm -f "$cs_jar"
      return 1
    }
    echo "  checkstyle ${CHECKSTYLE_VERSION} downloaded"
  fi
}

# gradle.properties にツールバージョンを追加
update_gradle_properties() {
  log_step "Updating gradle.properties..."

  local props_file="$TARGET_DIR/gradle.properties"

  # ファイル末尾に改行がない場合は追加（連結防止）
  if [ -s "$props_file" ] && [ "$(tail -c 1 "$props_file" | wc -l)" -eq 0 ]; then
    echo "" >> "$props_file"
  fi

  local added=0
  for entry in "${GRADLE_PROPS[@]}"; do
    local key="${entry%%=*}"
    local var="${entry#*=}"
    local value="${!var}"

    if [ "$DRY_RUN" = true ]; then
      echo "  [dry-run] gradle.properties: $key=$value"
      continue
    fi

    if grep -q "^${key}=" "$props_file"; then
      local current
      current=$(grep "^${key}=" "$props_file" | cut -d= -f2)
      if [ "$current" != "$value" ]; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$props_file"
        echo "  Updated: ${key}=${value} (was: $current)"
        added=$((added + 1))
      fi
    else
      echo "${key}=${value}" >> "$props_file"
      echo "  Added: ${key}=${value}"
      added=$((added + 1))
    fi
  done

  if [ "$DRY_RUN" != true ] && [ "$added" -eq 0 ]; then
    log_info "gradle.properties already up to date"
  fi
}

# .gitignore の更新
update_gitignore() {
  log_step "Updating .gitignore..."

  local gitignore="$TARGET_DIR/.gitignore"
  local entries=(
    ".claude/tools/"
    ".claude/agent-memory-local/"
    ".claude/settings.local.json"
  )

  if [ "$DRY_RUN" = true ]; then
    for entry in "${entries[@]}"; do
      echo "  [dry-run] .gitignore += $entry"
    done
    return
  fi

  # .gitignore がなければ作成
  touch "$gitignore"

  # ファイル末尾に改行がない場合は追加（連結防止）
  if [ -s "$gitignore" ] && [ "$(tail -c 1 "$gitignore" | wc -l)" -eq 0 ]; then
    echo "" >> "$gitignore"
  fi

  local added=0
  for entry in "${entries[@]}"; do
    if ! grep -qxF "$entry" "$gitignore"; then
      echo "$entry" >> "$gitignore"
      echo "  Added: $entry"
      added=$((added + 1))
    fi
  done

  if [ "$added" -eq 0 ]; then
    log_info ".gitignore already up to date"
  fi
}

# セットアップ変数の保存
save_setup_vars() {
  local vars_file="$TARGET_DIR/.claude/.setup-vars"

  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] save .setup-vars"
    return
  fi

  # シェル変数展開を防ぐため、値をそのまま書き出す
  {
    echo "# mc-claude-setup variables (auto-generated)"
    printf 'JAR_PREFIX=%s\n' "$JAR_PREFIX"
    printf 'SOURCE_PATH=%s\n' "$SOURCE_PATH"
  } > "$vars_file"
  echo "  .claude/.setup-vars saved"
}

# Gradle スニペットの表示
show_gradle_instructions() {
  if [ "$SKIP_GRADLE" = true ]; then
    return
  fi

  echo ""
  echo "============================================================"
  echo "  build.gradle の手動変更が必要です"
  echo "============================================================"
  echo ""
  echo "以下の変更を手動で適用してください。"
  echo "スニペットファイル: $SNIPPETS_DIR/"
  echo ""
  echo "--- root build.gradle ---"
  echo ""
  echo "1. plugins {} ブロックに追加:"
  echo "     id \"com.diffplug.spotless\" version \"\${spotless_version}\" apply false"
  echo "     id \"com.github.spotbugs\" version \"\${spotbugs_version}\" apply false"
  echo ""
  echo "2. allprojects {} ブロック内に品質ツール設定を追加"
  echo "   (詳細: $SNIPPETS_DIR/root-build.gradle.snippet)"
  echo ""
  echo "--- common/build.gradle ---"
  echo ""
  echo "3. dependencies {} に JUnit 5 を追加:"
  echo "     testImplementation \"org.junit.jupiter:junit-jupiter:\${rootProject.junit_version}\""
  echo "     testRuntimeOnly \"org.junit.platform:junit-platform-launcher:\${rootProject.junit_platform_version}\""
  echo ""
  echo "4. test {} ブロックを追加:"
  echo "     test { useJUnitPlatform() }"
  echo ""
  echo "   (詳細: $SNIPPETS_DIR/common-build.gradle.snippet)"
  echo ""
}

# 差分比較モード
run_diff() {
  echo ""
  log_info "mc-claude-setup --diff"
  echo ""
  echo "  Target:      $TARGET_DIR"
  echo "  JAR_PREFIX:  $JAR_PREFIX"
  echo "  SOURCE_PATH: $SOURCE_PATH"
  echo ""

  local has_diff=false
  local missing=0

  # 静的ファイルの比較
  local static_files=(
    "claude/settings.json:.claude/settings.json"
    "claude/hooks/pre-commit.sh:.claude/hooks/pre-commit.sh"
    "claude/hooks/post-java-edit.sh:.claude/hooks/post-java-edit.sh"
    "claude/scripts/jar-search.sh:.claude/scripts/jar-search.sh"
    "claude/scripts/spotbugs-report.py:.claude/scripts/spotbugs-report.py"
    "claude/skills/doc/SKILL.md:.claude/skills/doc/SKILL.md"
    "config/checkstyle/checkstyle.xml:config/checkstyle/checkstyle.xml"
    "config/spotbugs/exclude.xml:config/spotbugs/exclude.xml"
  )

  log_step "Static files"
  for entry in "${static_files[@]}"; do
    local tmpl_rel="${entry%%:*}"
    local target_rel="${entry#*:}"
    local tmpl_file="$TEMPLATES_DIR/$tmpl_rel"
    local target_file="$TARGET_DIR/$target_rel"

    if [ ! -f "$target_file" ]; then
      echo -e "  ${RED}MISSING${NC}  $target_rel"
      missing=$((missing + 1))
    else
      local result
      result=$(diff "$target_file" "$tmpl_file" 2>&1) || true
      if [ -z "$result" ]; then
        echo -e "  ${GREEN}OK${NC}       $target_rel"
      else
        echo -e "  ${YELLOW}DIFF${NC}     $target_rel"
        echo "$result" | sed 's/^/           /'
        has_diff=true
      fi
    fi
  done

  # テンプレートファイルの比較（変数置換後）
  local template_files=(
    "claude/skills/release/SKILL.md.tmpl:.claude/skills/release/SKILL.md"
    "claude/agents/mc-api-research.md.tmpl:.claude/agents/mc-api-research.md"
  )

  echo ""
  log_step "Template files (after substitution)"
  for entry in "${template_files[@]}"; do
    local tmpl_rel="${entry%%:*}"
    local target_rel="${entry#*:}"
    local tmpl_file="$TEMPLATES_DIR/$tmpl_rel"
    local target_file="$TARGET_DIR/$target_rel"

    if [ ! -f "$target_file" ]; then
      echo -e "  ${RED}MISSING${NC}  $target_rel"
      missing=$((missing + 1))
    else
      local rendered
      rendered=$(sed \
        -e "s|{{JAR_PREFIX}}|${JAR_PREFIX}|g" \
        -e "s|{{SOURCE_PATH}}|${SOURCE_PATH}|g" \
        "$tmpl_file")
      local result
      result=$(diff "$target_file" <(echo "$rendered") 2>&1) || true
      if [ -z "$result" ]; then
        echo -e "  ${GREEN}OK${NC}       $target_rel"
      else
        echo -e "  ${YELLOW}DIFF${NC}     $target_rel"
        echo "$result" | sed 's/^/           /'
        has_diff=true
      fi
    fi
  done

  # gradle.properties のチェック
  echo ""
  log_step "gradle.properties"
  local props_file="$TARGET_DIR/gradle.properties"
  for entry in "${GRADLE_PROPS[@]}"; do
    local key="${entry%%=*}"
    local var="${entry#*=}"
    local expected="${!var}"

    if ! grep -q "^${key}=" "$props_file" 2>/dev/null; then
      echo -e "  ${RED}MISSING${NC}  ${key}=${expected}"
      missing=$((missing + 1))
    else
      local current
      current=$(grep "^${key}=" "$props_file" | cut -d= -f2)
      if [ "$current" = "$expected" ]; then
        echo -e "  ${GREEN}OK${NC}       ${key}=${current}"
      else
        echo -e "  ${YELLOW}DIFF${NC}     ${key}=${current} (expected: ${expected})"
        has_diff=true
      fi
    fi
  done

  # .gitignore のチェック
  echo ""
  log_step ".gitignore"
  local gitignore="$TARGET_DIR/.gitignore"
  local gitignore_entries=(
    ".claude/tools/"
    ".claude/agent-memory-local/"
    ".claude/settings.local.json"
  )
  for entry in "${gitignore_entries[@]}"; do
    if [ ! -f "$gitignore" ]; then
      echo -e "  ${RED}MISSING${NC}  .gitignore (file not found)"
      missing=$((missing + 1))
      break
    elif grep -qxF "$entry" "$gitignore"; then
      echo -e "  ${GREEN}OK${NC}       $entry"
    else
      echo -e "  ${RED}MISSING${NC}  $entry"
      missing=$((missing + 1))
    fi
  done

  # ツール JAR のチェック
  echo ""
  log_step "Tool JARs"
  local gjf_jar="$TARGET_DIR/.claude/tools/google-java-format-${GJF_VERSION}-all-deps.jar"
  local cs_jar="$TARGET_DIR/.claude/tools/checkstyle-${CHECKSTYLE_VERSION}-all.jar"
  for jar in "$gjf_jar" "$cs_jar"; do
    local jar_name
    jar_name=$(basename "$jar")
    if [ -f "$jar" ]; then
      echo -e "  ${GREEN}OK${NC}       $jar_name"
    else
      echo -e "  ${RED}MISSING${NC}  $jar_name"
      missing=$((missing + 1))
    fi
  done

  # サマリー
  echo ""
  echo "============================================================"
  if [ "$missing" -gt 0 ] || [ "$has_diff" = true ]; then
    echo -e "  ${YELLOW}Differences found${NC} (missing: $missing)"
    echo "  Run setup.sh --update to sync, or review diffs above."
  else
    echo -e "  ${GREEN}All files match${NC}"
  fi
  echo "============================================================"
  echo ""
}

# サマリー表示
show_summary() {
  echo ""
  echo "============================================================"
  echo "  Setup Complete"
  echo "============================================================"
  echo ""
  echo "  Target:      $TARGET_DIR"
  echo "  JAR_PREFIX:  $JAR_PREFIX"
  echo "  SOURCE_PATH: $SOURCE_PATH"
  echo ""
  echo "残りの作業:"
  echo "  1. build.gradle の変更（上記参照）"
  echo "  2. CLAUDE.md の作成（プロジェクト固有の説明）"
  echo "  3. Claude Code でプロジェクトを開き、settings.local.json を設定"
  echo ""
}

# メイン
main() {
  parse_args "$@"

  echo ""
  log_info "mc-claude-setup"
  echo ""

  validate_project

  if [ "$UPDATE" = true ]; then
    load_setup_vars
  elif [ "$DIFF_MODE" = true ] && [ -f "$TARGET_DIR/.claude/.setup-vars" ]; then
    load_setup_vars
  else
    auto_detect
  fi

  validate_vars

  if [ "$DIFF_MODE" = true ]; then
    run_diff
    exit 0
  fi

  create_directories
  copy_static_files
  process_templates
  init_agent_memory
  copy_local_scripts
  download_tools
  update_gradle_properties
  update_gitignore
  save_setup_vars
  show_gradle_instructions
  show_summary
}

main "$@"
