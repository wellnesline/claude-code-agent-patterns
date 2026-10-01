---
name: persona-qa-loop
description: 文章 artifact(記事 / script.json / slides.json / 動画台本)生成タスクの基本フロー。「writer → ペルソナ並列QA → aggregate → 停止判定 → 改訂」 を最大5ループ回し、 director × 1.0 + selector × 5 + guide weighted の主スコア最大版を採択する。 全チャンネルの文章系生成タスクは原則このスキル経由。
---

# Persona QA Loop スキル

文章 artifact 生成の**基本ルール**。 セッション開始時に「記事を書いて」「台本を生成」「slides.json を出して」 系の指示が来たら、 まず本スキルに従って 5ループ QA を回す。

**親セッション(トップレベル Claude)内で実行**されるため、 `Agent` ツールで writer + ペルソナを並列 spawn 可能。

---

## When to use

新セッションで以下のような指示を受けたら、 まず本スキル:
- 「記事を書いて」 「<post-id> を書いて」
- 「(チャンネル名)の台本を書いて」 「script.json 生成」
- 「slides.json を作って」 「slides_skeleton.json を出して」
- 「<topic> の原稿を磨きたい」 「QA 回して」

**例外**(本スキル対象外):
- タイトル / サムネ / フック単発 QA → 別ルート(`persona_qa.runner aggregate --artifact {title,thumbnail,shorts_hook,video_hook}` を直接呼ぶ)
- news 系の script.json(構造化対話台本、 script ループ非対象。 ビルド内で 1パス生成)

---

## Phase 0: 準備(セッション開始時に1回)

1. 対象 channel と topic spec を確認
2. work_dir を決定:
   - 記事: `<project>/posts/<topic>/`
   - 動画: `<project>/videos/<slug>/`
3. channel.yaml の `persona_qa.script.cast` / `iter_max` / `early_stop` を読む。 無ければ ch 別デフォルト(下記表)を使う
4. `mkdir -p <work_dir>/iterations/v1`
5. TodoWrite で 5ループ分のタスクを作る(各ループに「writer」「persona spawn」「aggregate」「停止判定」 の4 sub-task)

---

## Phase 1-N: ループ(最大 5 回)

各イテレーション v{N}:

### Step 1. writer 起動(ch毎)

Agent tool で writer を spawn。 出力先 = `iterations/v{N}/<artifact_name>`。

| ch カテゴリ | writer agent | artifact |
|---|---|---|
| 記事 | general-purpose(設定で指定した記事ライター) | `article.md` |
| スライド型の動画 | general-purpose(設定で指定したスライド台本ライター) | `slides.json` |
| 掛け合い台本の動画 | `scriptwriter` | `script.json` |

v1 では topic spec を渡す。 v≥2 では前イテの「改訂方針 top 2」(各ペルソナの「改訂案」 セクションを抜粋)を writer に渡す。

### Step 2. ペルソナ並列 spawn(1メッセージ複数 Agent)

`channel.yaml persona_qa.script.cast` の **全ペルソナを単一メッセージで並列 Agent 呼出**。

各 spawn の prompt は必ず以下を含む:
- 自分のペルソナ MD パス(`persona_qa/personas/<id>.md`)を Read
- rubric MD パス(`persona_qa/rubrics/script.md`)を Read
- 評価対象パス(`iterations/v{N}/<artifact>`)を Read
- 出力先: `iterations/v{N}/feedback_<id>.md`
- fabrication 禁止(想像で他人の反応を混ぜない)
- 300-500字以内、 rubric の出力フォーマットに厳密に従う

### Step 3. aggregate

```bash
python -m persona_qa.runner aggregate \
  --artifact script \
  --work-dir <work_dir> \
  --iter <N>
```

→ `iterations/v{N}/score.json` 生成

### Step 4. 停止判定

`score.json` を読んで:

**早期停止(続行しない)**:
- A: `selector_star == 5.0` → 「selector ★5 達成」 即採用
- B: `director_score >= 45` AND **全 guide persona PASS**(skeptic/expert/viewer の verdict が PASS) → 「条件 B 達成」 即採用
- C: **直近 2 連続で `main_score` 改善なし**(改善幅 < 0.5)→ 「plateau」 直近最高版採用
- D: `skeptic_hard_fail == True` → 「HARD_FAIL veto、 修正必須」 → そのイテは没、 writer 差し戻し(ループ継続)

**強制停止**:
- `iter == 5` → 強制確定

**続行**:
- 上記いずれも該当なし → 次イテ v{N+1} へ(writer に改訂方針を渡す)

---

## Phase Final: select + 採用版コピー

```bash
python -m persona_qa.runner select \
  --artifact script \
  --work-dir <work_dir> \
  --artifact-file <name>     # article.md / slides.json / script.json 等
```

出力:
- `<work_dir>/<artifact_file>` に採用版が実体コピーされる
- `<work_dir>/iterations/selected.txt` に v番号
- `<work_dir>/persona_qa_log.md` 自動生成

parent Claude は人間に「採択版 v{N}、 main_score = X、 主要改善点 top 2」 を1-2行で報告。

---

## Phase Structural Gate: 構造系 critic (採択版に対する hard gate)

採択版確定後、 build パイプ起動前に **structural-critic** を 1回 spawn。 既存ペルソナ (主観評価) が拾えない構造系問題 (L1骨格逸脱 / L2 内部矛盾 + 番号自己整合 / L3 transition段差 / L4前提先取り / L5循環整合) を機械検査する。

### 起動条件
- artifact = script / slides.json / article.md (長文構造物)
- 採択版が存在 (`iterations/selected.txt` がある)
- 例外 (skip 可): タイトル / サムネ / フック単発、 構造が異なる成果物 (コマ割り台本など)

### 起動コマンド (parent Claude が Agent tool で spawn)

```
subagent_type: structural-critic
prompt:
  - 骨格 (scaffold.yaml / planning.md / outline.md) パス
  - 本文 (採択版 artifact) パス
  - 出力先: <work_dir>/iterations/v{N}/structural_critique.md
```

### 判定と扱い

structural-critic は 5軸 PASS/WARN/FAIL + 総合 verdict を返す:

| 総合 verdict | 扱い |
|---|---|
| **OK** | そのまま build へ進む |
| **OK_WITH_NOTES** | build 進行可、 改訂指示は memo として記録 (人間判断で後追い) |
| **REVISE** | writer 差し戻し 1回 (改訂指示 top 3 を渡す)、 再度 Phase Final → Structural Gate を実施。 ループ最大 2回 |
| **HARD_FAIL** | build BLOCK。 5ループ全体を見直し、 scaffold or writer prompt 修正。 人間判断仰ぐ |

### コスト目安
- 1 spawn / sonnet / 約 $0.03-0.05
- REVISE 1回追加で +$0.10-0.15 (writer 差戻 + critic 再走)
- 既存5ループの +5-10% コスト

### 既存運用との関係
- 既存 6-7体QA は **主観評価** (読者目線/演出/技術) で 採択版を 1つ決める
- structural-critic は **構造評価** で 採択版の合格判定を hard gate する
- 観点が直交するので 重複/競合しない (PoC 実証 = 既存7体が検出できなかった問題を新規検出)

### 一次ソース
- agent 定義: `.claude/agents/structural-critic.md`
- 設計メモ(非同梱): 運用ルール文書

---

## デフォルト cast(channel.yaml に persona_qa.script.cast 未設定時)

| ch カテゴリ | cast(全 guide + selector) | rationale |
|---|---|---|
| 記事 | 読者ペルソナ複数 + selector_editor | 読者層ごとの視点を並べる |
| 動画台本 | viewer_generalist, expert_domain, skeptic_critic, director_documentary(4体) | 一般視聴者・専門家・批判的視聴者・演出の4視点 |
| 軽量構成 | viewer_generalist, selector_editor, director_documentary(3-4体) | 設定で選択 |

cast 内に **必ず**:
- guide ≥ 1 体(主スコア基本要素)
- selector_editor または同等(採択決定)
- director_documentary は推奨(BLOCK ガード機能あり、 50点軸)

---

## 出力構造(統一)

```
<work_dir>/
├── iterations/
│   ├── v1/
│   │   ├── <artifact>             ← writer 出力(article.md / slides.json 等)
│   │   ├── feedback_<id>.md       ← ペルソナ feedback(cast 数分)
│   │   └── score.json             ← aggregate 出力
│   ├── v2/ ... v5/
│   └── selected.txt               ← v番号(例: "v3\n")
├── <artifact_file>                ← 採択版実体(parent から見える正本)
└── persona_qa_log.md              ← qa_log(select 出力)
```

---

## コスト目安

- 1 ループ:
  - writer: ~$0.10
  - 4-7 体並列 ペルソナ: ~$0.20-0.40
  - aggregate(CLI): ~$0
  - 合計: **$0.30-0.50 / loop**
- 5 ループ max: **$1.5-2.5 / topic**
- 早期 stop(平均 3 ループ): **$0.9-1.5 / topic**

---

## 既存運用との互換性

本スキルは以下3つの旧手順書を**統一吸収**:
- 記事向けの複数ペルソナ QA 手順
- 動画台本向けの複数ペルソナ QA 手順(演出家の採点つき)
- スライド型動画向けの短縮 QA 手順

旧 MD は履歴用に残し、 冒頭に「**運用一次ソースは `/persona-qa-loop` スキル**」 と banner を貼る。

---

## エラー処理

- writer 失敗 → イテ中止、 parent Claude が原因を人間報告
- ペルソナ spawn 失敗(1体) → 残りで aggregate 続行、 score.json `missing` に記録
- aggregate 失敗 → イテ中止、 score.json なしで stop
- 5 ループ全て skeptic HARD_FAIL → 「題材撤退 signal」 として人間に判断仰ぐ

---

## 関連

- `persona_qa/README.md` — 全体仕様
- `persona_qa/personas/` — 11ペルソナ(属性+口調のみ)
- `persona_qa/rubrics/script.md` — 評価軸+出力フォーマット
- `persona_qa/runner/__main__.py` — aggregate / select CLI
- 設計メモ(非同梱) — 設計の一次ソース、および「全文章生成は本スキル経由」基本ルール
