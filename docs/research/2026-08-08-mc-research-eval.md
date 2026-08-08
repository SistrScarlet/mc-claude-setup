# mc-research 統合後の実測評価 (2026-08-08)

Task 5 (docs/superpowers/plans/2026-08-08-mc-research-consolidation.md)。統合後の `mc-research` エージェント/スキル/`jar-search.sh` を、実際のサブエージェント起動で 2 系統評価した記録。

- 評価対象: LMML (`/home/sistr/works/mc/LittleMaidModelLoader-Architectury`) に Task 4 で配布済みの `.claude/agents/mc-research.md` / `.claude/skills/mc-research/SKILL.md` / `.claude/scripts/jar-search.sh`
- 実行方式: Agent tool、`subagent_type: general-purpose`、`model: sonnet`。プロンプトは mc-research.md の frontmatter 以下全文 + 作業ディレクトリ指定 + 調査依頼 + 「使用したコマンドと詰まった点」セクション要求
- 実行時刻: 2026-08-08 12:30:37Z 起動、回帰 eval 12:35:57Z 完了 (所要 319.8s)、API eval 12:42:09Z 完了 (所要 711.5s)。2 つは並行起動

## 0. セットアップ時の逸脱 (重要)

brief の Step 2 は「修正コミットの親」(`ede9d9c~1`) を worktree のベースにする指示だったが、これをそのまま使うと **root-cause doc が最初から worktree に存在する**事故が起きた。

調査の結果、実際のコミット順序は:

```
c030645 fix: NeoForge 双方向 payload 二重登録回避       (a2df84a 移植リグレッション後、まだ TODO 記載なし)
ce0a59b docs: TODO に 1.21.1 移植回帰バグを追加           (症状のみ記載、root cause 未記載)
2631da5 chore: bump version to 9.0.0-beta.1
e626aa4 fix(neoforge): dedicated server起動時のクラッシュを修正
b48caca chore: bump version to 9.0.0-beta.2               ← 今回使用したベース
4a1c875 docs: サウンドパック回帰バグ2件の原因調査を記録    (root-cause doc 追加、ここで答えが出る)
ede9d9c fix: サウンドパック選択時に声が鳴らない回帰を修正   (brief が指示した ~1 の基準点)
6d3ebd3 fix: サウンドパック選択画面のUIが背景ブラーに巻き込まれる問題を修正
```

root-cause doc (`docs/research/2026-07-11_soundpack-regression-root-cause.md`) は `4a1c875` で追加されているため、`ede9d9c~1 = 4a1c875` を使うと最初から答えが書かれた状態になる。brief にはこの「答えが書いてあるファイルが存在してしまう場合」の対応指示は無かったが、実装者 (eval オーケストレーター) の判断として、答えが露出するベースコミットを避けることにした。

**対応**: 「root-cause doc が無く、かつ回帰も既に発生している」最小差分のコミットとして `b48caca` (`4a1c875` の直前) を採用した。確認済み:
- `git show b48caca:docs/research/2026-07-11_soundpack-regression-root-cause.md` → 存在しない (fatal: path exists on disk, but not in 'b48caca')
- `git show b48caca:TODO.md` → 症状のみの TODO エントリ (`ce0a59b` 由来) は存在する
- `a2df84a` (回帰混入コミット) は `b48caca` の祖先 → 回帰は再現する
- `LMSoundManager.java` の `getLocation()` override は `b48caca` 時点で既に無い (`new Sound(location, ...)` のみ) → 症状が実際に発生する状態

**事後確認 (重要)**: 前回 eval (2026-07-12) の `soundpack-silent-with_skill` 出力自体に「ローカル 1.21.1 ブランチに調査対象 HEAD (b48caca) 未取り込みの修正コミット ede9d9c が存在し…」という記述があり、**前回 eval も worktree のベースとして `b48caca` を使っていたことが本人の報告文から確定した**。つまり今回選び直したベースコミットは、brief 記載の `ede9d9c~1` ではなく、前回 eval と完全に同一のコミットだった。ベースコミットの一致という点では懸念解消。

worktree 作成中に `.gradle` symlink を張った状態のまま `git worktree remove` を一度実行してしまいそうになったが、symlink を先に `rm` してから `remove` する正しい手順に修正した (最終的な作業には影響なし、実体の `.gradle` も無事)。

## 1. 回帰 eval: サウンドパック無音バグ

### 症状文 (前回 2026-07-12 eval と同一、review HTML `EMBEDDED_DATA.runs[0].prompt` から転記)

> LMML 1.21.1 移植後、サウンドパックを選択してもメイドさんの声が鳴らない (デフォルトのガスト声は鳴る)。1.20.1 では正常。root cause と最小修正方針を調査報告せよ (read-only、gradle 禁止)。

### Ground truth (`docs/research/2026-07-11_soundpack-regression-root-cause.md` + 修正コミット `ede9d9c`)

`LMSoundManager#addSound` が生成する `Sound` の `getLocation()` override が 1.21.1 移植時 (`a2df84a`) に失われ、バニラの `Sound#getLocation()` (`ResourceFinder("sounds",".ogg")`) が `sounds/` prefix と `.ogg` suffix を再付与するため、`ResourceWrapper` の登録キーと二重に不一致になり無音になる。

### 結果: root cause 正答か → **Yes (完全一致)**

サブエージェントの報告 (`common/.../LMSoundManager.java` の override 消失、`FINDER = new ResourceFinder("sounds", ".ogg")` の static init、`ResourceFinder#toResourcePath` が `sounds/sounds/....ogg.ogg` を作る、`SoundLoader`/`SoundSystem` が消費側であることを `callers` で確認、ガスト声だけ鳴る理由を `contains(":")` 分岐で説明) は、ファイル・メカニズムともに ground truth と本質的に同一。デフォルト声が生存する理由の説明も一致。

**軽微な gap**: ground truth と前回 eval (with_skill) は override 削除コミット `a2df84a` を `git log -S` で明示的に特定していたが、今回の報告は `git diff local/1.20..HEAD` で「override が無い」ことは確認したが、削除コミットのハッシュを明示していない。スキル (SKILL.md B-2) は `git log --oneline -S "<消えた/変わったシンボル>"` を明示的に推奨しており、この 1 ステップが省略された形。root cause の正否には影響しないが、報告の完全性としては前回よりわずかに劣る。

### 報告形式 B 準拠 → **Yes**

Root cause / 旧バージョンで動いていた理由 / (追加: なぜ今壊れた) / 症状との整合 / 最小修正方針 (代替案の却下理由込み) / 根拠まとめ、の全項目が揃っている。

### ライセンス出力ルール (参考観察、brief は API eval にのみ要求だが実際に問題が見つかったため記録)

**違反あり。** 報告中に、シグネチャを超えるロジックを含む ``` コードブロックが 2 箇所あった:

1. 1.20 ブランチの override 実装をほぼそのまま再現 (コンストラクタ呼び出し全体 + `@Override` メソッド本体) して ``` ブロックで提示
2. 現行 (1.21.1) の `addSound()` 内の `new Sound(...)` 呼び出しをそのまま ``` ブロックで提示

どちらも「メソッド/フィールドのシグネチャのみ許可」のルールに反し、プロジェクトファイル (LMML 自身のソース) のコードを転載している。一方、javap のバイトコード出力 (`getstatic`/`invokevirtual` 等の逆アセンブル) はスキルの「報告」節が明示的に要求する根拠形式であり、これは問題ない。javap 出力の中に 1 箇所、`id.withPath("sounds/" + id.getPath() + ".ogg")` という Java 風の擬似コードで要約した行があり、これは実際の javap 出力そのものではなく「バイトコードが意味することを再構成した Java 表現」に見える — デコンパイル的な再構成であり、これも厳密にはルール抵触。

**前回との比較は交絡しており因果を断定できない**: review HTML の `EMBEDDED_DATA.runs[*].outputs[*].content` を確認したところ、前回 (2026-07-12) の `soundpack-silent-with_skill` 出力はバッククォート (`` ` ``) の使用が 0 個だった。ただしこの比較には複数の交絡要因がある — (a) 前回の出力はエージェントが書いたファイル成果物 (`report.md`)、今回はチャット最終メッセージであり出力チャネルが異なる、(b) `EMBEDDED_DATA.runs[*].prompt` に記録されているのは症状文のみで、前回ハーネスが mc-research のエージェント定義・スキル本文をどう与えたかは不明、(c) 前回出力は 2,575 文字、今回の報告ははるかに長く、単純に転載が起きる表面積が違う、(d) 今回のプロンプトは「使用したコマンドと詰まった点」セクションや「javap/diff 出力の要点を省略せず書く」という追加指示を含み、これ自体がコードブロック使用を誘発する方向に働く。したがって「違反が観測された」ことは事実として確定できるが、「統合作業が原因で後退した」という因果関係はこの eval からは判定できない。Task 7 では「統合による後退」ではなく「出力ルール文言の強化 (``` ブロックだけでなくインラインコードでの逐語転載も明示的に禁止する等) を検討する」という穏当な提言にとどめるべきである。

### 使用したコマンドと詰まった点 (サブエージェント報告より)

| コマンド | 回数 | エラー | 備考 |
|---|---|---|---|
| `doctor` | 1 | なし | ソース jar 無し (genSources 未実行) を確認、javap 系に方針決定 |
| `sig` | 2 | なし | `Sound`, `ResourceFinder` |
| `bytecode` | 5 | なし | `getLocation`, `getIdentifier`, `static`, `toResourcePath`, `SoundLoader.method_19740` |
| `callers` | 1 | なし | `Sound getLocation` |
| `find`/`grep`/`read` | 0 | — | 未使用 (バニラクラスのみで完結) |

エージェント自身の申告: 「詰まった点: 特になし」。複数 jar マッチの情報メッセージ (`minecraft-merged` と `neoforge-*-minecraft-merged` の重複) は毎回出たが、`sig`/`bytecode`/`callers` が使う `resolve_class_entry` の既存の「先頭マッチを使用 + 通知」動作で自動的に処理され、絞り込み操作は不要だった。

**所要時間・トークン**: 319.8 秒 (about 5m20s)、tool_uses 29、subagent_tokens 80,107。

**前回実測 (スキルあり Sonnet, 2026-07-12) との比較**: review HTML の `EMBEDDED_DATA.benchmark` は `runs: []` / `evals_run: []` で、構造化された数値記録は存在しなかった。ただし出力本文 (`runs[*].outputs[*].content`) まで確認したところ、`soundpack-silent-without_skill` (スキルなしベースライン) の出力末尾に自己申告の所要時間「約19分 / 102kトークン / ツール呼び出し42回」があった (ただし jar-search.sh 不使用、fabric-loom キャッシュを手動展開する経路)。**`soundpack-silent-with_skill` (今回比較したい対象) 側には同様の自己申告が無く**、数値比較は今回もできない。定性面では、前回 with_skill 実行の 6 expectation (prefix/suffix 二重化の特定、override 削除の特定、ガスト声生存理由、正しい最小修正、jar による裏取り、worktree 無改変) のうち、削除コミットのハッシュ特定を除く 5 項目相当を今回も満たしている。Task 2 で単独計測された `callers Sound getLocation` の実測 82.6s と比べると、今回の 29 コマンド・約 320 秒というトータルは同オーダーで妥当な範囲。参考までに、前回のスキルなしベースライン (jar-search.sh 不使用、手動 fabric-loom キャッシュ展開) の ~19分/102kトークン/42回に対し、今回のスキルあり実行は 5.3分/80kトークン/29回と少ない。ただしこれは「スキルなし vs スキルあり (今回)」という異なる設定同士の比較であり、比較したい「前回スキルあり vs 今回スキルあり」の対比ではないため、統合作業自体の速度改善/悪化を示す根拠にはならない (参考情報として記録するのみ)。

## 2. API eval: PlayerList.tracking のプラットフォーム差

### 調査依頼

LMML `TODO.md` (中優先度、コミット `20cdc79` で追記) の実タスクをそのまま提示: 「`PlayerList.tracking` の実装がプラットフォームで食い違っている…」+ Fabric/NeoForge 双方の実際の API と呼び出し箇所の調査、NeoForge を tracker ベースに揃える場合の実装方針を依頼。作業ディレクトリは LMML 本体 (worktree ではなく main)。

**方法論上の注記**: brief 指定通り `subagent_type: general-purpose` で起動しており、これは `Bash`/`Glob`/`Grep`/`Read` に加えて `Write`/`Edit` 等フルツールセットを持つ。実際の `mc-research` エージェント定義 (frontmatter `tools: Bash, Glob, Grep, Read`) が持つツール制限は、このハーネスではプロンプト遵守のみで担保されており機構的には強制されていない。今回は eval 実行後に `git -C .../LittleMaidModelLoader-Architectury status --short` で main リポジトリが清潔なまま (変更なし) であることを確認できたため実害は無かったが、read-only 制約の機構的強制そのものは本 eval の検証範囲外である。

### 結果: 調査質問に答えられたか → **Yes**

Fabric (`PlayerLookup.tracking`) と NeoForge (現行 `world.getPlayers()`) の意味差を一次情報 (ソース) で確認した上で、NeoForge 側のトラッカーベース等価 API として `ServerChunkLoadingManager#getPlayersWatching(Entity)` を発見。これが NeoForge 自身の内部コード (`AttachmentSync`) でも使われている「公式に安定した経路」であることまで裏付け、`ServerChunkManager` へのキャストが必要な点・`instanceof` 防御を推奨する点まで具体的な実装方針を提示した。さらに、LMML の実際の呼び出し箇所 (`sendS2CPacket` 3 箇所) では `entity` が常にメイドさん Mob でプレイヤーではないため、TODO が懸念していた「Fabric の tracking は自分自身を含まない」問題は該当しないと結論づけ、修正後の挙動リグレッションリスクも評価した。TODO のヒントの単純な引き写しでなく、実装レベルまで踏み込んだ独自の調査。

### callers を使ったか → **No**

`doctor` でソース jar が揃っていることを確認し、`find`/`read`/`grep` のみで完結。`sig`/`bytecode`/`apidiff`/`callers` は「ソース jar で十分だったため」未使用、と明示的に申告。ソースが手に入る場合に javap 系を使わないのは合理的判断であり、欠陥ではない。

### 報告形式 A 準拠 → **Yes**

Summary / Key Classes/Interfaces / API Details / Usage Pattern / Cross-Platform Notes / Caveats が全て揃っている。

### ライセンス出力ルール (コード転載なし) を守ったか → **No、複数箇所で違反**

コードブロック (```) の使用は無かったが、インラインコード (単一バッククォート) で「使用パターン・例」を自然言語化せず直接提示した箇所が複数ある:

- Cross-Platform Notes の比較表内: `((ServerChunkManager) entity.getWorld().getChunkManager()).chunkLoadingManager.getPlayersWatching(entity)` — 提案する呼び出し式をコードとして提示 (自然言語での説明が求められる箇所)
- 本文: 「`AttachmentSync` line 132: `serverLevel.getChunkManager().chunkLoadingManager.getPlayersWatching(entity)`」— **NeoForge (サードパーティライブラリ) の実際のソース行を行番号付きで直接引用**。これはルールが最も強く禁じる「デコンパイルソース・ライブラリのコードの転載」に該当する、最も明確な違反
- 比較表内の `entity.getWorld().getPlayers()` (LMML 自身の現行実装の引用)、本文中の `squaredDistanceTo(entity) < 16*16` (LMML 自身の条件式の引用) も、プロジェクトファイルの転載にあたる

これらはいずれも ``` ブロックを使っていないため「コードブロックはシグネチャのみ許可」という字面上のルールはすり抜けているが、「挙動・ロジック・使用パターン・例はすべて自然言語で記述する」という別のルールには明確に反する。SKILL.md / mc-research.md の出力ルールが「``` ブロック」だけを名指ししており、インラインコードでの再現を明示的に禁止していないため、エージェントがこの抜け道を使った可能性がある。

### 使用したコマンドと詰まった点 (サブエージェント報告より)

| コマンド | 回数 | エラー | 備考 |
|---|---|---|---|
| `doctor` | 1 | なし | ソース jar 有りと確認、javap 不要と判断 |
| `find` | 3 | なし | `PlayerLookup`, `PacketDistributor`, `ServerChunkManager --dir minecraftMaven` |
| `read` | 12 | なし | 全て成功 |
| `grep` | 6 | **1 回エラー** | `jar-search.sh grep NetworkManager.java "sendToPlayers" 40` → `Error: No source jar matching 'NetworkManager.java' found`。第一引数に jar パターンではなくファイルパスを渡した誤用。`find` で得た正確な jar パス (`architectury-13.0.8`) を使い、`grep` の代わりに `read` で回避 |
| `sig`/`bytecode`/`apidiff`/`callers`/`list` | 0 | — | 未使用 (ソース jar で十分) |

その他の詰まり (エラーにはならず): `find ServerChunkManager` で Fabric 側 (Yarn マップ) の `minecraft-merged` jar が 2 種類ヒットし、目的の NeoForge パッチ入り jar を明示的に選ぶ必要があった。ジャー名の部分一致 (`neoforge-21.1.233-minecraft-merged`) で一貫して絞り込めたため、これはエラーではなく `find` の設計通りの動作 (全 jar 横断) で正常に解決している。

Task 2 で観測された「`--dir` 指定ミスは無診断 exit 0」の再現: **無し** (今回は `--dir minecraftMaven` を正しく使用できていた)。

**所要時間・トークン**: 711.5 秒 (about 11m52s)、tool_uses 48、subagent_tokens 88,714。

## 3. ツール観測まとめ (両 eval 横断)

- `sig`/`bytecode`/`callers`/`apidiff` (= `resolve_class_entry` 系) は複数 jar マッチ時も自動で先頭マッチを使い通知するのみで、両 eval とも詰まらなかった。この系統は既に候補 A の挙動を実装済みで問題なし
- `grep`/`read` が使う `resolve_jar` については、両 eval とも `find` で事前に候補 jar を確認してから `grep`/`read` に具体的な jar パターンを渡す使い方をしており、**`resolve_jar` の「複数マッチでエラー終了」自体には一度も到達しなかった**
- 唯一のエラーは `grep` の引数誤用 (jar パターン欄にファイルパスを渡した) で、これは 0 件マッチのエラーであり複数マッチのエラーではない。エラーメッセージ自体は分かりやすく (`No source jar matching '...' found`)、エージェントは 1 手で `read` に切り替えて自己解決した。ツールの欠陥というより誤用に近く、対応は必須ではない
- 両 eval とも「目的の jar/クラスが分からず全 jar を横断検索する」必要が生じる場面は無かった (`find` の全 jar 横断機能で十分事足りた)
- ライセンス出力ルール (コード転載なし) について、両 eval で実際に違反が観測された。回帰 eval は ``` ブロックでの逐語コード転載 (LMML 自身のソース)、API eval はインラインコードでの逐語転載 (LMML 自身のソースおよび NeoForge の実ソース行を行番号付きで引用) だった。jar-search.sh 自体の問題ではなく、mc-research.md/SKILL.md の出力ルール記述 (```` ``` ```` ブロックのみを名指し) がインラインコードでの抜け道を塞げていない可能性がある。ただし前回 eval (バッククォート 0 個) との比較は出力チャネル・プロンプト・文章量が異なり交絡しているため、「統合作業による後退」と断定はできない (詳細は 1 節)。違反が観測された事実そのものは確定している

## 4. 磨き込み判定 (Task 6 向け)

既知候補 2 件について、「観測で必要性が確認されたか」:

| 候補 | 判定 | 根拠 |
|---|---|---|
| A: `resolve_jar` 複数マッチ自動選択 | **No** | 両 eval とも `resolve_jar` の複数マッチエラー (現状の「エラー終了」挙動) には一度も到達しなかった。ただし完全な無風ではない: API eval で `find ServerChunkManager` が Fabric 側 (Yarn マップ) の `minecraft-merged` jar 2 種 (ハッシュ違い) にヒットし、目的の NeoForge パッチ入り jar を得るために `grep`/`read` へ渡すパターンを `neoforge-21.1.233-minecraft-merged` まで具体化する一手間が発生した (ニアミス、`resolve_jar` のエラー分岐そのものには入っていない)。エージェントは `find` の結果を見てから長いパターンを渡す運用で自力回避しており、これが `resolve_jar` の「エラー終了」を実際にトリガーしたわけではない。実装しても実害を防ぐ効果が観測上確認できたとまでは言えない (将来別のタスクで起きうるリスク自体は否定できない) |
| B: 横断 grep (`grepall`) | **No** | 両 eval とも「対象 jar が分からず全体を検索する」場面が発生しなかった。`find` によるクラス検索が事前情報として十分機能していた |

**新規に観測された詰まり**:
- `grep` の引数誤用 (ファイルパスを jar パターンとして渡す) による 0 件マッチエラー。1 件のみの発生で、エラーメッセージで自己解決できているため、Task 6 のゲート (「観測で新たな詰まりが見つかった場合はプランを更新してから実装する」) に照らして実装が必要なほどの重大さではないと判断する。usage 文言に「第一引数は jar パターンで、パスではない」旨を一言添えるかどうかは任意判断とし、今回は追加提案としてのみ記録し実装は見送る
- ライセンス出力ルールの逐語転載 (上記 3 節) は jar-search.sh の改修範囲外 (Task 6 は `templates/claude/scripts/jar-search.sh` の変更のみが対象)。前回 eval との比較は交絡しており「統合による後退」とは断定できないが、違反が実際に観測された事実は確定している。Task 7 で SKILL.md/mc-research.md の出力ルール文言強化 (```` ``` ```` ブロックだけでなくインラインコードでの逐語転載も明示的に禁止する) を検討事項として引き継ぐことを推奨する

**結論**: 候補 A・候補 B とも Yes 判定に至る観測は得られなかった。新規の重大な詰まりも無し。Task 6 は「両候補とも No で新規詰まりも無ければ実装なしとしてスキップする」の条件に該当する。

## 5. worktree

`$SCRATCH/lmml-eval` (base commit `b48caca`) は Step 6 で `.gradle` symlink 削除 → `git worktree remove --force` により掃除済み。
