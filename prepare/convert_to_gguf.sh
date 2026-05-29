#!/usr/bin/env bash
# Kanana merged HF model → GGUF f16 → Q4_K_M 양자화
# 사전 조건:
#   - prepare/merge_lora.py 실행 완료 (merged/ 디렉터리 존재)
#   - llama.cpp 클론 + llama-quantize 빌드 완료 (기본 경로: ../llama.cpp)
set -euo pipefail

MERGED_DIR="${MERGED_DIR:-merged}"
OUT_DIR="${OUT_DIR:-out}"
LLAMA_CPP="${LLAMA_CPP:-../llama.cpp}"
MODEL_TAG="${MODEL_TAG:-kanana-1.5-2.1b-koen}"
QUANT="${QUANT:-Q4_K_M}"   # Q4_K_M (기본) / Q5_K_M / Q8_0

mkdir -p "$OUT_DIR"

F16_GGUF="$OUT_DIR/${MODEL_TAG}-f16.gguf"
Q_GGUF="$OUT_DIR/${MODEL_TAG}-${QUANT,,}.gguf"

if [[ ! -d "$MERGED_DIR" ]]; then
  echo "❌ $MERGED_DIR 가 없습니다. 먼저 prepare/merge_lora.py를 실행하세요." >&2
  exit 1
fi
if [[ ! -d "$LLAMA_CPP" ]]; then
  echo "❌ llama.cpp 경로($LLAMA_CPP)가 없습니다. LLAMA_CPP=/path/to/llama.cpp 로 지정하거나" >&2
  echo "   git clone https://github.com/ggerganov/llama.cpp $LLAMA_CPP" >&2
  exit 1
fi

QUANTIZE_BIN="$LLAMA_CPP/build/bin/llama-quantize"
if [[ ! -x "$QUANTIZE_BIN" ]]; then
  echo "❌ $QUANTIZE_BIN 빌드 안 됨. $LLAMA_CPP 에서 cmake -B build && cmake --build build -j --target llama-quantize" >&2
  exit 1
fi

# 1) HF → GGUF f16
if [[ -f "$F16_GGUF" ]]; then
  echo "✓ $F16_GGUF 이미 존재 — 변환 단계 건너뜀"
else
  echo "🔄 HF → GGUF f16 변환..."
  python "$LLAMA_CPP/convert_hf_to_gguf.py" "$MERGED_DIR" \
    --outfile "$F16_GGUF" --outtype f16
fi

# 2) GGUF f16 → Q4_K_M (또는 사용자 지정)
echo "🔄 양자화: f16 → $QUANT"
"$QUANTIZE_BIN" "$F16_GGUF" "$Q_GGUF" "$QUANT"

echo "✅ 완료:"
ls -lh "$OUT_DIR"/*.gguf
echo ""
echo "다음: adb push $Q_GGUF /sdcard/Download/"
