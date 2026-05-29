#!/usr/bin/env bash
# Termux 안에서 llama.cpp를 빌드 (S23 Snapdragon 8 Gen 2 + Adreno 740 타겟)
# 사전:
#   pkg install -y git cmake clang make python python-pip
#   (Vulkan 백엔드 원하면 추가)  pkg install -y vulkan-tools vulkan-headers vulkan-loader-android
set -euo pipefail

CLONE_DIR="${CLONE_DIR:-$HOME/llama.cpp}"
USE_VULKAN="${USE_VULKAN:-0}"   # 1 = Vulkan(Adreno 740) 백엔드 활성화

if [[ ! -d "$CLONE_DIR" ]]; then
  echo "📥 llama.cpp 클론 → $CLONE_DIR"
  git clone https://github.com/ggerganov/llama.cpp "$CLONE_DIR"
fi

cd "$CLONE_DIR"

CMAKE_ARGS=(
  -B build
  -DCMAKE_BUILD_TYPE=Release
  -DLLAMA_CURL=OFF
  -DGGML_NATIVE=ON                  # -march=native (X3 자동 감지)
  -DCMAKE_C_FLAGS="-O3 -march=armv8.4-a+dotprod+fp16"
  -DCMAKE_CXX_FLAGS="-O3 -march=armv8.4-a+dotprod+fp16"
)

if [[ "$USE_VULKAN" == "1" ]]; then
  echo "🔧 Vulkan 백엔드 활성화 (Adreno 740)"
  CMAKE_ARGS+=( -DGGML_VULKAN=ON )
fi

cmake "${CMAKE_ARGS[@]}"
cmake --build build -j$(nproc) --target llama-cli llama-bench

echo ""
echo "✅ 빌드 완료. 바이너리:"
ls -la build/bin/llama-cli build/bin/llama-bench

echo ""
echo "다음:"
echo "  export LLAMA_CLI=\"$CLONE_DIR/build/bin/llama-cli\""
echo "  bash bench/run_inference.sh /storage/emulated/0/Download/kanana-1.5-2.1b-koen-q4_k_m.gguf \"오늘 점심으로 김치찌개 어때요?\""
