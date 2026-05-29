#!/usr/bin/env bash
# 단발 추론 — Kanana Q4_K_M으로 한 번 번역 실행 + prefill/decode tok/s 추출.
# 사용법:
#   bash bench/run_inference.sh <GGUF_PATH> "<한국어 문장>"          # 한→영 기본
#   DIRECTION=en2ko bash bench/run_inference.sh <GGUF_PATH> "<영어 문장>"
set -euo pipefail

GGUF="${1:?GGUF 경로}"
TEXT="${2:?입력 문장}"
DIRECTION="${DIRECTION:-ko2en}"
THREADS="${THREADS:-4}"
NCTX="${NCTX:-1024}"
NPREDICT="${NPREDICT:-200}"
LLAMA_CLI="${LLAMA_CLI:-$HOME/llama.cpp/build/bin/llama-cli}"

if [[ ! -x "$LLAMA_CLI" ]]; then
  echo "❌ $LLAMA_CLI 없음. scripts/build_llama_cpp_android.sh로 빌드하거나 LLAMA_CLI 환경변수 지정." >&2
  exit 1
fi

case "$DIRECTION" in
  ko2en) INSTR="다음 한국어 문장을 영어로 번역하세요." ;;
  en2ko) INSTR="Translate the following English sentence into Korean." ;;
  *) echo "❌ DIRECTION은 ko2en|en2ko" >&2; exit 1 ;;
esac

PROMPT="### Instruction:
$INSTR

### Input:
$TEXT

### Response:
"

# llama-cli 실행 — stderr에 timing 정보가 들어옴
TMP_ERR=$(mktemp)
TMP_OUT=$(mktemp)
trap "rm -f $TMP_ERR $TMP_OUT" EXIT

"$LLAMA_CLI" \
  -m "$GGUF" \
  -t "$THREADS" \
  -c "$NCTX" \
  -n "$NPREDICT" \
  --temp 0 \
  -p "$PROMPT" \
  --no-display-prompt \
  --single-turn \
  > "$TMP_OUT" 2> "$TMP_ERR"

echo "──── 번역 결과 ────"
cat "$TMP_OUT"
echo ""
echo "──── 성능 ────"
# llama.cpp는 stderr 끝에 timing 출력
grep -E "(prompt eval time|eval time|total time)" "$TMP_ERR" || tail -20 "$TMP_ERR"

# CSV 한 줄 (timestamp,direction,prefill_tps,decode_tps,total_s)
PREFILL_TPS=$(grep "prompt eval time" "$TMP_ERR" | grep -oE "[0-9.]+ tokens per second" | grep -oE "^[0-9.]+" | head -1)
DECODE_TPS=$(grep "^[[:space:]]*eval time" "$TMP_ERR" | grep -oE "[0-9.]+ tokens per second" | grep -oE "^[0-9.]+" | head -1)
TOTAL_S=$(grep "total time" "$TMP_ERR" | grep -oE "[0-9.]+ ms" | head -1 | grep -oE "^[0-9.]+")
TOTAL_S=$(awk "BEGIN { printf \"%.3f\", ${TOTAL_S:-0}/1000 }")

echo ""
echo "CSV: $(date +%s),$DIRECTION,${PREFILL_TPS:-NA},${DECODE_TPS:-NA},${TOTAL_S}"
