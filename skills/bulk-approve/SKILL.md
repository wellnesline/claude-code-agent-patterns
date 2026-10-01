---
name: bulk-approve
description: 複数(channel,slug)のStage1/Stage3/Stage3.7を並列自動進行し、review/配置+captions.yaml生成して結果通知する。Stage3.7まで(upload submit は範囲外)。過去問題チェックリストを毎回走査し、長期間発動しない項目は自動削除。skill 形式のため親セッション内で実行され、Agent ツールで director を直接 spawn できる。
---

# bulk-approve スキル

複数チャンネル横断の Stage1/Stage3/Stage3.7 一括進行 + captions.yaml生成 + 完了通知を行うオーケストレーター。
**親セッション(=トップレベル Claude)内で実行されるため、`Agent` ツールで director を spawn 可能。**

## 入力(CLI 形式)
- `--channels <ch1,ch2,...>` 対象チャンネル
- `--slugs <slug1,slug2,...>` 対象スラッグ
- `--parallel N` 並列度上書き(任意、デフォルト N=1 直列、`--parallel` 明示で並列化)
- (diagram_blob モード時) `--topic-seed "..."` + `--hook-type ...` 必須。`--slugs` 不要(orchestrator が `_progress.yaml` から fuzzy 一致して採番)

## 規約
詳細は設計メモ(非同梱)を参照(動作規約・並列度・spawn手順・集計・チェックリスト増減・重大度ルーティング)。

## 関連
- チェックリスト・履歴: 設計メモ(非同梱)
- 検出スクリプト: `scripts/qa_bulk_approve.py`

## batch-approver との関係
別物。`batch-approver` は batch_unattended pipeline 内の stage間 MVP承認エージェント(子エージェント)。本 skill は複数ch横断の上位オーケストレーターで親セッション内で動く。

## skill 化の経緯
旧実装は `.claude/agents/bulk-approve.md`(子エージェント)だったが、Claude Code の構造的制約により子エージェントは Agent ツールを持てず director を spawn できない問題が複数回再発。skill 化により親セッション内実行に移行し、Agent ツール常時利用可能となった。

## diagram_blob モード
入力 `--channel <ch> --topic-seed "..." --hook-type ...` で起動した場合、director を spawn せず本 skill orchestrator が直接 25 step を実行する(scout-broll → editor の標準パイプを使わず、 plan.md/script.json 等を orchestrator が自動生成 + gen_diagram_blob_diagrams + 図解の順序付け agent(非同梱)の並列 spawn + build_diagram_blob_shorts 経路)。

詳細手順 + 採番ロジック(`_progress.yaml` fuzzy 一致引き継ぎ)+ slug 生成ガイド + hook_type 別切替は設計メモ(非同梱)を参照。生成失敗の事後検出は `scripts/qa_bulk_approve.py` の `detect_diagram_blob_*` 系。
