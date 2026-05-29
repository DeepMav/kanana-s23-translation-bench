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
TMP_OUT=$(mktemp)
trap "rm -f $TMP_OUT" EXIT

# 새 llama.cpp(2026~): 모든 출력이 stdout에, 요약 라인은
#   [ Prompt: X t/s | Generation: Y t/s ]
# 형식. stderr는 비어있음.
START=$(date +%s.%N)
"$LLAMA_CLI" \
  -m "$GGUF" \
  -t "$THREADS" \
  -c "$NCTX" \
  -n "$NPREDICT" \
  --temp 0 \
  -p "$PROMPT" \
  --no-display-prompt \
  --single-turn \
  > "$TMP_OUT" 2>&1
END=$(date +%s.%N)
TOTAL_S=$(awk "BEGIN { printf \"%.3f\", $END - $START }")

echo "──── 번역 결과 ────"
# Response 이후만 추출 (배너·로딩 스피너 제외)
awk '/^ ### Response:$/{flag=1; next} /\[ Prompt:/{flag=0} flag' "$TMP_OUT" | sed '/^$/d'
echo ""
echo "──── 성능 ────"
grep -E "\[ Prompt:" "$TMP_OUT" || echo "(no perf summary — old llama.cpp?)"

PREFILL_TPS=$(grep -oE "Prompt: [0-9.]+ t/s" "$TMP_OUT" | grep -oE "[0-9.]+" | head -1)
DECODE_TPS=$(grep -oE "Generation: [0-9.]+ t/s" "$TMP_OUT" | grep -oE "[0-9.]+" | head -1)

echo ""
echo "CSV: $(date +%s),$DIRECTION,${PREFILL_TPS:-NA},${DECODE_TPS:-NA},${TOTAL_S}"
