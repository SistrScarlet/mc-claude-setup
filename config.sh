# mc-claude-setup 設定ファイル
# バージョンやURLを変更する場合はこのファイルを編集してください

# ツールバージョン
GJF_VERSION="1.17.0"
CHECKSTYLE_VERSION="10.21.4"
SPOTLESS_VERSION="6.25.0"
SPOTBUGS_PLUGIN_VERSION="6.1.7"
JUNIT_VERSION="5.10.2"
JUNIT_PLATFORM_VERSION="1.10.2"

# gradle.properties に追記するプロパティ一覧（キー=変数名）
GRADLE_PROPS=(
  "gjf_version=GJF_VERSION"
  "checkstyle_version=CHECKSTYLE_VERSION"
  "spotless_version=SPOTLESS_VERSION"
  "spotbugs_version=SPOTBUGS_PLUGIN_VERSION"
  "junit_version=JUNIT_VERSION"
  "junit_platform_version=JUNIT_PLATFORM_VERSION"
)

# ダウンロードURL
GJF_URL="https://github.com/google/google-java-format/releases/download/v${GJF_VERSION}/google-java-format-${GJF_VERSION}-all-deps.jar"
CS_URL="https://github.com/checkstyle/checkstyle/releases/download/checkstyle-${CHECKSTYLE_VERSION}/checkstyle-${CHECKSTYLE_VERSION}-all.jar"
