#!/usr/bin/env bash
# 30분 연속 추론 — 동일 프롬프트를 반복 호출하여 분당 throughput 측정.
# Throttling 발생 시점·이후 안정 tok/s를 관찰.
#
# 사용법:
#   bash bench/sustained_30min.sh <GGUF_PATH> results/sustained_run1.csv
# 환경변수:
#   DURATION_S=1800 NPREDICT=200 THREADS=4 NCTX=1024
#
# 새 llama.cpp는 timing summary가 stdout: [ Prompt: X t/s | Generation: Y t/s ]
set -uo pipefail   # -e 제외: grep 실패해도 NA로 기록 후 계속

GGUF="${1:?GGUF 경로}"
OUT="${2:?출력 CSV 경로}"
DURATION_S="${DURATION_S:-1800}"   # 30분
THREADS="${THREADS:-4}"
NCTX="${NCTX:-1024}"
NPREDICT="${NPREDICT:-200}"
LLAMA_CLI="${LLAMA_CLI:-$HOME/llama.cpp/build/bin/llama-cli}"

mkdir -p "$(dirname "$OUT")"

# 표준 프롬프트 — AI Hub 외부의 공개 문장 (재배포 가능)
PROMPT="### Instruction:
다음 한국어 문장을 영어로 번역하세요.

### Input:
오늘 점심으로 김치찌개를 먹으려고 하는데 같이 가실래요?

### Response:
"

echo "timestamp,run_idx,prefill_tps,decode_tps,total_s" > "$OUT"

START_TS=$(date +%s)
RUN=0

while true; do
  NOW=$(date +%s)
  ELAPSED=$((NOW - START_TS))
  if (( ELAPSED >= DURATION_S )); then
    echo "[sustained] $DURATION_S 초 경과 — 종료" >&2
    break
  fi

  RUN=$((RUN + 1))
  TMP_OUT=$(mktemp)
  RUN_START=$(date +%s.%N)
  "$LLAMA_CLI" \
    -m "$GGUF" \
    -t "$THREADS" -c "$NCTX" -n "$NPREDICT" --temp 0 \
    -p "$PROMPT" --no-display-prompt --single-turn \
    > "$TMP_OUT" 2>&1
  RUN_END=$(date +%s.%N)
  TOTAL_S=$(awk "BEGIN { printf \"%.3f\", $RUN_END - $RUN_START }")

  # 새 포맷: [ Prompt: 8.6 t/s | Generation: 3.4 t/s ]
  PREFILL=$(grep -oE "Prompt: [0-9.]+ t/s" "$TMP_OUT" | grep -oE "[0-9.]+" | head -1)
  DECODE=$(grep -oE "Generation: [0-9.]+ t/s" "$TMP_OUT" | grep -oE "[0-9.]+" | head -1)

  echo "$NOW,$RUN,${PREFILL:-NA},${DECODE:-NA},$TOTAL_S" >> "$OUT"
  rm -f "$TMP_OUT"

  # 표시
  printf "[%3dmin %2ds] run=%-3d decode=%s tok/s\n" $((ELAPSED/60)) $((ELAPSED%60)) "$RUN" "${DECODE:-NA}"
done

echo "✅ 완료: $RUN runs / $OUT"
