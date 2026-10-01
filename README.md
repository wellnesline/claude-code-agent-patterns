# claude-code-agent-patterns

A collection of Claude Code subagent definitions and skills: role-split production agents, independent QA critics, and orchestration skills with human gates.

Claude Code のサブエージェント定義（`agents/`）とスキル（`skills/`）の実例集です。公開用に整理したサンプル実装です。コードではなく、役割・入出力・停止条件を書いた Markdown が中心です。

## 概要

AI に長い制作や検証を任せるとき、1 つのプロンプトに全部を書くと、役割が混ざり、自己採点で甘くなります。ここでは「作る担当」「検査する担当」「全体を回す担当」を別のエージェントに分け、人間の承認ゲート・差し戻しの上限・読み取り専用の検査役といった制約をプロンプト側に書き込んでいます。

## 主な機能・設計のポイント

- **作る人と検査する人の分離**: 台本・記事・LP・サムネイルなどを書く agent と、それを検査する agent（構造の論理整合、事実照合、AI 臭・専門用語の検出、視覚確認など）を別に定義しています。検査役は読み取り専用のツール構成にして、勝手に直せないようにしています。
- **検査の観点を絞る**: 例えば構造検査役は「全体構造の論理整合」だけを見て、行番号を引用して PASS / WARN / FAIL を返します。主観評価の役割とは分けています。
- **複数ペルソナによる反復 QA**（`persona-qa-loop`）: 書き手と複数の読者ペルソナを並列で起動し、集計・停止判定・改訂を上限付きで繰り返し、最高スコアの版を採用します。
- **オーケストレーター型**: 1 本の制作を複数の worker agent に分けて順に起動する agent（映像制作、WordPress サイト構築、LP 制作など）と、`bulk-approve` のように承認ゲートまで並列で進めるスキルがあります。
- **別モデルへの委譲ランナー**（`skills/_codex-common/`）: 議論 → 反証 → 実測の POC というループを別の CLI エージェントに実行させるためのラッパーです。API キーの環境変数を子プロセスから外して、API キー認証（従量課金）へ意図せず切り替わるのを防ぎます（API キーで使う場合は除去を外します）。空応答は失敗として返します。
- **監査・E2E 系の agent**: プロンプトの偏りの監査（`prompt-bias-auditor`）、未使用項目の洗い出し（`unused-audit`）、ブラウザ自動操作による通し検証（`webapp-e2e-tester`）を agent として定義しています（`prompt-audit-agents` にも切り出しています）。
- **値は設定駆動**: 視聴者層・尺・段数・シリーズ名・締めの文言・色などの運用値は、各 agent 内のサンプル値であり、実際はチャンネル設定（`channel.yaml` など）で指定する前提です。
- **コストと権限の明示**: 各 agent の frontmatter に `model` と `tools` を書き、役割に必要な最小のツールだけを与えています。

## ディレクトリ構成

```
agents/     サブエージェント定義 45 本（Markdown + frontmatter: name / description / model / tools）
skills/     スキル定義（SKILL.md）3 本: persona-qa-loop, bulk-approve, codex-discuss-poc
skills/_codex-common/   別 CLI エージェント呼び出しの共通ランナー（codex_run.sh / codex_run.ps1）
```

### agents/ の一覧

| 分類 | ファイル |
|---|---|
| 統括・承認・変更検証 | `director`, `batch-approver`, `change-validator`, `prototyper` |
| 企画・台本 | `planner`, `producer`, `scriptwriter`, `shorts-producer` |
| 素材・制作 | `content-scout`, `scout-broll`, `editor`, `thumbnailer` |
| 検査・批評 | `qa`, `video-qa`, `thumb-qa`, `structural-critic`, `prompt-bias-auditor`, `unused-audit`, `webapp-e2e-tester` |
| 公開・告知 | `uploader`, `description-writer`, `x-operator` |
| 分析・改善 | `optimizer`, `competitor-analyst`, `pdca-analyst`, `pdca-competitor`, `pdca-proposer`, `pdca-strategist` |
| LP・営業資料 | `lp-strategist`, `lp-copy-writer`, `lp-copy-reviewer`, `lp-information-architect`, `lp-visual-implementer`, `sales-deck-designer`, `sales-deck-writer`, `outbound-email-humanness-critic` |
| Web サイト・記事 | `wp-site-builder`, `wp-home-builder`, `wp-article-writer`, `wp-reader-agency`, `wp-reader-ceo`, `wp-reader-dx-manager`, `wp-reader-freelancer` |
| 画面定義 | `sitemap-architect`, `sitemap-qa-reviewer` |

## 使い方

`agents/*.md` を `.claude/agents/`、`skills/<name>/` を `.claude/skills/` に置くと、Claude Code から利用できます。そのまま動くパッケージではなく、各自の運用に合わせて書き換える前提の参考実装です。

委譲ランナーを使う場合の環境変数:

| 変数 | 用途 |
|---|---|
| `CODEX_MODEL` | 必須。使用するモデル名 |
| `CODEX_EFFORT` | 推論量（既定 medium） |
| `CODEX_TIMEOUT` | タイムアウト秒（既定 1200） |
| `CODEX_BIN` | PowerShell 版で CLI の場所を明示するとき |

agent / skill の中で言及される外部サービスの鍵（環境変数名のみ）: `ANTHROPIC_API_KEY`、`OPENAI_API_KEY`（画像生成）、`ELEVENLABS_API_KEY`（音声合成）、`FAL_KEY`（動画生成）、`PEXELS_API_KEY` / `PIXABAY_API_KEY`（素材検索）。YouTube Data API は OAuth の資格情報ファイルを使います。

## 制限事項（閉包）

- **同梱していない依存**（コード上の import は 0 件）: このリポジトリに Python / TypeScript のコードはなく、ランナー（シェル / PowerShell）のみです。ただし、定義が前提にしている次のものは同梱していません。
  - 各 agent が呼び出すアプリ本体・スクリプト・設定ファイル（動画制作アプリ、台本・画像生成の CLI、検査スクリプトなど）
  - 外部 CLI とサービス: Claude Code、Codex CLI（委譲ランナー用）、`ffmpeg`、Playwright、YouTube Data API、WordPress、OpenAI、ElevenLabs、VOICEVOX、Fal 系の動画生成、素材サイト
  - ランナー: `codex_run.sh` は bash と coreutils の `timeout` が前提、PowerShell 版は Windows 用の代替です。
- 画面定義の作成・レビュー用の agent（`sitemap-architect`、`sitemap-qa-reviewer`）は、`spec-to-mockup` のパイプラインの前後工程を担う想定です。`prompt-bias-auditor` などの監査役は `prompt-audit-agents` にも切り出しています。
- 定義の中の「設計メモ(非同梱)」は、運用ルールを書いた非公開の文書を指します。このリポジトリには含めていません。参照している節の名前は、ルールの置き場を示す目印として残してあります。
- そのままでは特定の運用に接続できません。パスやコマンド名は各自の環境に合わせて書き換えてください。
- 外部サービスのページやデータの取得・保存は、各サービスの規約の範囲で行ってください（保存期間を含む）。
- 映像素材はストック素材・パブリックドメイン/CC・自社素材・AI 生成のみを前提にしています。他者がアップロードした動画の映像は使いません。調査・素材収集の agent は、各サービスの利用規約と素材の許諾の範囲で使ってください。
- 音声合成のキャラクターや声は、それぞれの利用条件に従ってください（クレジット表記が条件のものは、説明欄に規約どおりの表記を入れます）。
- モデル名・数値の基準・運用ルールには、サンプルとして置いた値が含まれます。そのまま流用せず確認してください。

## ライセンス

All rights reserved. 閲覧目的で公開しています。詳細は LICENSE を参照。
