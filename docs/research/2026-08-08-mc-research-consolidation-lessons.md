# mc-research 統合作業の lessons (2026-08-08)

mc-api-research (haiku) + regression-research (sonnet) → mc-research (sonnet) 統合、
jar-search.sh callers 追加、setup.sh 配線、全 6 プロジェクト配布、実測 eval までの振り返り。

## うまくいったこと

- **WIP と配線の分離コミット**: setup.sh に gametest WIP が 27 日間未コミットで混在していた問題は、
  「WIP をバックアップ → git checkout で復元 → 配線のみ編集・コミット → WIP を Edit で復元」で解消できた。
  復元はバイトレベル比較で検証。長期 WIP と新規変更が同一ファイルに混ざったら早期にこの手で分離する
- **実測駆動のツール改善**: 磨き込み候補 2 件 (resolve_jar 複数マッチ自動選択 / grepall) は机上では妥当に見えたが、
  eval 2 本の実測でどちらも必要になる場面が発生せず No 判定 → 実装せず。
  「観測された詰まりだけ直す」ゲートは無駄な実装を 2 件防いだ
- **eval のベースコミット選定**: ground truth の再調査 eval では「答えの doc が含まれない」「回帰は再現している」
  コミットを worktree ベースに選ぶ必要がある。修正コミットの親には root-cause doc が既に入っていた。
  前回 eval (2026-07-12) と同じ b48caca を使えたことで比較の一貫性も確保できた

## 注意が必要だったこと

- **`setup.sh --update` のダウングレード罠**: `local/scripts/dropbox-upload.py` (gitignored ローカルマスター) が
  LMRB のコミット済み版 (4c930f1, mc_version_platforms 対応) より古く、--update が黙って上書きする。
  今回の再配布は対象ファイルの直接コピーで回避した。**恒久対応はローカルマスターへの逆輸入** (未実施)
- **--update は未コミット変更を消す**: LMRBCompat の .claude/settings.json の未コミット変更が消失し復元不能だった。
  --update 前に対象プロジェクトの `git status` 確認を必須にすべき
- **ライセンス出力ルールの抜け道**: 「コードブロックはシグネチャのみ」という文言では、
  インラインコードでの実コード行引用が両 eval で発生した。禁止は出力形態を問わない表現にする必要があり、
  文言を強化して再配布した (1076716)。残課題: ワークフロー B の報告形式の「根拠」欄が
  javap/diff 出力の逐語引用を誘発しやすい文言のまま (禁止自体は共通節で担保)
- **git log の撤回済み主張**: eval 記録のコミット 69c4a8e のメッセージは「後退であることを確認」と
  断定しているが、直後の bec17e1 で交絡要因を理由に撤回済み。**doc 本文 (最新) が正**で、
  git log だけを見て 69c4a8e の主張を再取り込みしないこと
- **eval ハーネスの限界**: general-purpose サブエージェントで実行した eval は mc-research 本来の
  ツール制限 (Bash, Glob, Grep, Read) を機構的に強制しない。read-only 制約の検証は未実施のまま

## 統合で残した/変えた知識

- 旧 2 エージェントの調査手法はスキル 1 枚 (`.claude/skills/mc-research/SKILL.md`) に SSOT 統合
  (ワークフロー A = API 調査、B = 回帰調査、タスク種別判断を冒頭に)
- エージェントメモリは mc-api-research → mc-research へ改名引き継ぎ (蓄積 API 知識を保持)
- ZabutonR は stonecutter 構成 (common/ なし) で validate_project が弾くため手動オーバーレイ配布。
  SOURCE_PATH は src/main/java/net/sistr/zabutonr (fabric/src/... はスタブのみで誤り)
- YAML frontmatter の description は 1 物理行の二重引用符 + `\n` エスケープで書く
  (複数物理行は折り畳みで値が変わる)
