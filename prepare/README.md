# PC에서 모델 준비

이 단계는 PC(Linux + GPU 권장)에서 1회만 실행하면 됩니다. 생성된 GGUF를 S23에 푸시합니다.

## 1. Kanana base + LoRA 머지

```bash
pip install -U transformers peft accelerate huggingface_hub torch
huggingface-cli login  # HF 토큰 (선택, public 모델이라 미로그인도 가능)

python prepare/merge_lora.py
# → merged/ 디렉터리에 HF 형식 모델 저장 (~4 GB, bf16)
```

## 2. GGUF 변환 + Q4_K_M 양자화

llama.cpp이 필요합니다.

```bash
# llama.cpp 클론 + 빌드 (PC용)
git clone https://github.com/ggerganov/llama.cpp ../llama.cpp
cd ../llama.cpp && cmake -B build && cmake --build build -j --target llama-quantize
cd -

# 변환
bash prepare/convert_to_gguf.sh
# → out/kanana-1.5-2.1b-koen-f16.gguf  (~4.2 GB)
# → out/kanana-1.5-2.1b-koen-q4_k_m.gguf (~1.3 GB) ← S23용
```

기본은 `Q4_K_M`. 비교 측정용으로 `Q5_K_M`, `Q8_0`을 같이 만들고 싶다면 스크립트 안에서 QUANT 변수 수정.

## 3. S23으로 전송

```bash
adb push out/kanana-1.5-2.1b-koen-q4_k_m.gguf /sdcard/Download/
```

Termux에서는 `/storage/emulated/0/Download/kanana-1.5-2.1b-koen-q4_k_m.gguf`로 접근.
