#!/bin/bash
# codex_run.sh — Codex ハーネス共通ランナー (codex-discuss-poc 共用)
#
# usage: cat prompt.md | codex_run.sh <sandbox-mode> <workdir> <out.md> [log.txt] [extra codex args...]
#   sandbox-mode : read-only | workspace-write   (検証系=read-only / 修正・POC実装=workspace-write)
#   workdir      : Codex の作業ルート (-C)。read-only でもここ配下は読める
#   out.md       : 最終回答 (agent_message) の書き出し先 (-o)
#   log.txt      : 実行トランスクリプト全文 (省略時 <out.md>.log)
#
# env:
#   CODEX_MODEL  (必須。使用モデルを環境変数で指定)
#   CODEX_EFFORT (既定 medium。high は推論トークンが膨らむので最終反証ラウンド等に限定)
#   CODEX_TIMEOUT (既定 1200 秒)
#
# 不変条件:
#   - OPENAI_API_KEY と CODEX_API_KEY を必ず除去して起動 = ログイン済みの認証のまま使い、
#     API キー認証 (従量課金) へ意図せず切り替わるのを防ぐ。API キーで使う場合は除去を外す。
#     CODEX_API_KEY は codex exec 専用の一時 API キー指定で、ログイン認証より優先される。
#   - rc=0 でも空応答がありうる → 空なら rc=1 で返す。
set -u
MODE="${1:?sandbox-mode required}"
WORKDIR="${2:?workdir required}"
OUT="${3:?out file required}"
LOG="${4:-${OUT}.log}"
shift 3
[ $# -gt 0 ] && shift

MODEL="${CODEX_MODEL:?set CODEX_MODEL}"
EFFORT="${CODEX_EFFORT:-medium}"
TIMEOUT_S="${CODEX_TIMEOUT:-1200}"

mkdir -p "$(dirname "$OUT")" "$(dirname "$LOG")"

env -u OPENAI_API_KEY -u CODEX_API_KEY timeout "$TIMEOUT_S" codex exec - \
  --skip-git-repo-check \
  --sandbox "$MODE" \
  -C "$WORKDIR" \
  -m "$MODEL" \
  -c "model_reasoning_effort=$EFFORT" \
  -o "$OUT" \
  "$@" > "$LOG" 2>&1
rc=$?

if [ ! -s "$OUT" ]; then
  echo "codex_run: EMPTY output (rc=$rc, model=$MODEL, mode=$MODE) — see $LOG" >&2
  exit 1
fi
cat "$OUT"
exit $rc
