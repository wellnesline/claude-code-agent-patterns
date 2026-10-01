---
name: codex-discuss-poc
description: 任意テーマの 議論→反証→POC実施→確認検証ループ を Codex に実行させる汎用パイプライン。Claude はハーネス/議事進行に徹する。技術選定・設計判断・仮説検証など、特定の内容によらず「決着を実測でつけたい」時に使う。「codexと議論して」「これ反証して」「POCで確かめて」系で起動。
---

# codex-discuss-poc — Codex 駆動 議論・反証・POC パイプライン

## 大原則 (役割分担)
- **Claude (このセッション) = ハーネス/議事進行のみ**: 論点ブリーフ作成、Codex 起動、ラウンド管理、争点の整理 (要約であって意見ではない)、成果物ファイル書き出し、課金ゲート、依頼者への報告。
- **Codex = 議論・反証・POC 実装・検証判定の実体**。Claude は議論の当事者にならない — 自分の意見で主張・反論しない。争点を抽出して次ラウンドのプロンプトに変換するのが仕事。
- **モデル = `CODEX_MODEL` で指定した値に固定**。effort 既定 medium。利用枠を消費するのでラウンド上限を守る。

## 共通ランナー
```bash
# bash 環境
RUN=.claude/skills/_codex-common/codex_run.sh
cat prompt.md | bash $RUN <read-only|workspace-write> <workdir> <out.md> [log]
```
```powershell
# PowerShell 環境
.\.claude\skills\_codex-common\codex_run.ps1 -Mode <read-only|workspace-write> -WorkDir <workdir> -PromptFile prompt.md -Out <out.md> [-Log <log>]
```
- 議論/反証 = `read-only` (repo 参照可)、POC 実装 = `workspace-write`。
- POC がパッケージ install 等でネットを要する時のみ `-c sandbox_workspace_write.network_access=true` を追加 (必要最小限・外部送信系の用途は不可)。

## 成果物の置き場
テーマごとに `sandbox/spike-<slug>/` (既存 spike の続きならそこに追記):
```
sandbox/spike-<slug>/
  ├ ISSUE.md          # Phase0: 論点ブリーフ (ハーネスが書く)
  ├ DISCUSSION.md     # Phase1-2: 議論・反証の全ラウンド議事録 (追記式)
  ├ POC_PLAN.md       # Phase3: 実験計画 (成功基準を事前固定)
  ├ poc/              # Phase4: POC コード・実行結果
  └ POC_REPORT.md     # Phase6: 結論
```

## Phase 0 — 論点ブリーフ (ハーネス)
`ISSUE.md` を書く: 背景 / 決めたいこと (1 文で) / 制約 (課金・品質・納期・既存資産) / 関連する過去資産のパス (notes/ 該当メモリ、既存 spike、docs) / 成功基準の素案。
- 依頼文をそのまま冒頭に引用する (伝言ゲーム劣化防止)。
- 関連資産の**パス列挙まで**がハーネスの仕事。内容の咀嚼・評価は Codex に渡してやらせる。

## Phase 1 — 議論 (Codex read-only)
ISSUE.md + 関連資産を投入し、指示する内容:
- 選択肢を網羅 → 各選択肢の利害・前提・不確実性 → 推奨案 + その根拠。
- **不明な事実は「未確認」と明示させる** (作話ガード)。repo 内で確認できることは実ファイルを開いて確認させる。
出力 → `DISCUSSION.md` に「## R1 主張」として追記。

## Phase 2 — 反証 (Codex read-only、**別セッション** = コンテキスト非共有)
R1 の主張全文を渡し、**敵対的に**反証させる: 前提の誤り / 見落とした選択肢 / 隠れコスト / 「実測しないと分からない」箇所の特定。
- ハーネスは R1 と R2 を突き合わせて**争点リスト**を作る (合意点 / 対立点 / 実測で決着つく点 の 3 分類)。
- 対立点が残れば追加ラウンド (R3=再主張、R4=再反証)。**最大 4 ラウンドで打ち切り** — 収束しない対立点は「実測で決着」か「人間の判断」に振り分ける。
- 各ラウンドを `DISCUSSION.md` に追記 + 末尾に争点リスト最新版を維持。

## Phase 3 — POC 計画 (Codex read-only → ハーネスがゲート)
争点リストの「実測で決着つく点」を Codex に渡し、実験計画を書かせる:
- 最小の実験 / **成功基準は実施前に数値で固定** (実測 first — 後出し判定禁止) / 測定方法 / 交絡要因と潰し方。
出力 → `POC_PLAN.md`。
**課金ゲート (ハーネス)**: 従量課金 (gpt-image / ElevenLabs / API 直叩き等) を伴う実打が計画に入る場合は**停止→概算提示→依頼者の承認**が先。

## Phase 4 — POC 実施 (Codex workspace-write, `-C sandbox/spike-<slug>`)
- POC_PLAN.md を渡し、`poc/` 配下に実装→実行→生ログ保存までやらせる。**結果の生データ (数値・ログ) を必ずファイルに残させる** (要約だけの報告は不可)。
- 実行が長い/対話環境依存でハーネス側の実行が必要な場合のみ、Codex が書いたスクリプトをハーネスが実行してログを戻す。
- ⚠ 本番コード (`<app>/backend` 等) には触らせない。POC は spike 内で完結。

## Phase 5 — 確認検証ループ (Codex read-only、別セッション、最大 3 ラウンド)
POC の実装 + 生ログ + POC_PLAN.md を新セッションに渡し、反証させる:
- 成功基準を満たしたか (数値で) / 測定は妥当か (交絡・n 不足・プロンプト調整バイアス) / 結論を一般化しすぎてないか。
- 不備指摘 → Phase 4 に差し戻して再実験。**収束 = 反証が新規の重大不備を出さなくなったら**。
- 判定結果も `DISCUSSION.md` に追記。

## Phase 6 — 結論 (ハーネス)
`POC_REPORT.md`: 決めたかったこと → 議論の争点 → 実測値 (生データへのパス付き) → 結論 → 残リスク/未検証事項 → 推奨アクション。
- 依頼者に要約報告。**本番反映はこのスキルの範囲外** — 反映が必要なら change-validator 等の既存の変更管理パイプラインへ引き継ぐ。
- 汎用的な学び (罠・実測値) が出たら運用メモ化を提案する。

## 禁止・注意まとめ
- Claude 自身が議論の内容判断・POC コード執筆をする (ハーネス逸脱)
- 成功基準の後出し変更 / 実測なしの断定を結論に載せる
- 従量課金の実打を承認なしで実行
- effort high の常用 / モデルの勝手な変更
