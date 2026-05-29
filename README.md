# kanana-s23-translation-bench

[![License: Apache-2.0 (code)](https://img.shields.io/badge/Code-Apache--2.0-blue.svg)](LICENSE)
[![Runtime: llama.cpp](https://img.shields.io/badge/Runtime-llama.cpp%20Android-purple.svg)](https://github.com/ggerganov/llama.cpp)
[![Model: Kanana LoRA](https://img.shields.io/badge/🤗-kanana--1.5--2.1b--aihub--ko--en--lora-yellow.svg)](https://huggingface.co/harveykim/kanana-1.5-2.1b-aihub-ko-en-lora)
[![Device: Galaxy S23](https://img.shields.io/badge/Device-Galaxy%20S23-black.svg)](https://www.gsmarena.com/samsung_galaxy_s23-12082.php)

**Kanana 1.5 2.1B + AI Hub #126 LoRA** 한↔영 통번역 모델을 **갤럭시 S23 (Snapdragon 8 Gen 2)** 에서 직접 돌리며 **속도·발열·지속 처리량**을 측정하는 벤치마크 레포입니다.

상위 프로젝트: [`DeepMav/on-device-translation`](https://github.com/DeepMav/on-device-translation) (학습·평가 코드)
모델: [`harveykim/kanana-1.5-2.1b-aihub-ko-en-lora`](https://huggingface.co/harveykim/kanana-1.5-2.1b-aihub-ko-en-lora)

---

## 목표

| 질문 | 측정 |
|---|---|
| **(1) 얼마나 빠른가?** | Prefill / Decode tokens/sec, time-to-first-token |
| **(2) 얼마나 뜨거워지는가?** | CPU 온도(`/sys/class/thermal/`), 배터리 온도(`dumpsys battery`) 5초 샘플링 |
| **(3) 지속 가능한가?** | 30분 연속 추론 동안 throttling 발생 시점·이후 안정 tok/s |
| **(4) Q4 양자화 손실은?** | PC bf16 BLEU 32.04 → 온디바이스 Q4 BLEU 재측정 |

---

## 대상 기기 — Galaxy S23 (SM-S911)

| 항목 | 값 |
|---|---|
| SoC | Snapdragon 8 Gen 2 (TSMC 4nm) |
| CPU | Cortex-X3 @ 3.36 GHz × 1 + A715 × 2 + A710 × 2 + A510 × 3 |
| GPU | Adreno 740 (Vulkan 1.3, OpenCL 3.0) |
| NPU | Hexagon (Genie SDK 대상) |
| RAM | 8 GB LPDDR5X |
| OS | Android 14 (One UI 6.1) + Termux |
| 냉각 | Vapor chamber (구형 — 발열 throttling 비교적 빠름) |

---

## 모델 사양

- **베이스**: `kakaocorp/kanana-1.5-2.1b-base` (Apache 2.0)
- **LoRA**: `harveykim/kanana-1.5-2.1b-aihub-ko-en-lora` (CC BY-NC 4.0, AI Hub #126 988K 학습)
- **타겟 포맷**: GGUF Q4_K_M (~1.3 GB, RAM ~1.5 GB 예상)
- **PC bf16 베이스라인**: BLEU 32.04 / chrF++ 57.26 (200쌍 균형 검증셋)

---

## 사용 절차

### 1. PC에서 모델 준비 (1회)

```bash
# (1) Kanana base + LoRA 어댑터 머지 → HF 형식
python prepare/merge_lora.py

# (2) HF → GGUF f16 → Q4_K_M 양자화 (llama.cpp 필요)
bash prepare/convert_to_gguf.sh
# → out/kanana-1.5-2.1b-koen-q4_k_m.gguf 생성 (약 1.3 GB)
```

상세: [`prepare/README.md`](prepare/README.md)

### 2. S23에 모델 + llama.cpp 배포

```bash
# Termux 안에서 llama.cpp 빌드
bash scripts/build_llama_cpp_android.sh

# GGUF 모델 푸시 (PC → 폰)
adb push out/kanana-1.5-2.1b-koen-q4_k_m.gguf /sdcard/Download/
# Termux에서 /storage/emulated/0/Download/ 로 접근
```

### 3. 벤치마크 실행 (S23 Termux)

```bash
# (A) 단발 속도 측정 — 한 번 추론, prefill/decode tok/s 출력
bash bench/run_inference.sh \
    /storage/emulated/0/Download/kanana-1.5-2.1b-koen-q4_k_m.gguf \
    "오늘 점심으로 김치찌개 어때요?"

# (B) Thermal 타임라인 — 백그라운드로 5초마다 온도 샘플링
bash bench/thermal_logger.sh results/thermal_$(date +%s).csv &
THERMAL_PID=$!

# (C) 30분 지속 처리량 테스트
bash bench/sustained_30min.sh \
    /storage/emulated/0/Download/kanana-1.5-2.1b-koen-q4_k_m.gguf \
    results/sustained_$(date +%s).csv

# 종료 후 thermal 로거 정지
kill $THERMAL_PID

# (D) Q4 BLEU 재검증 (사용자 본인 val_2k.jsonl 필요 — AI Hub 신청 후 본인 환경에서)
python bench/eval_bleu_on_device.py \
    --gguf /storage/emulated/0/Download/kanana-1.5-2.1b-koen-q4_k_m.gguf \
    --val /sdcard/Download/val_2k.jsonl \
    --n 200
```

### 4. 결과 시각화 (PC로 다시 가져와)

```bash
adb pull /data/data/com.termux/files/home/.../results/ ./results/
python scripts/plot_thermal_timeline.py results/thermal_*.csv results/sustained_*.csv
```

---

## 측정 방법론

상세한 측정 프로토콜·외부 변수 통제 방법은 [`docs/METHODOLOGY.md`](docs/METHODOLOGY.md)를 참조하세요. 핵심:

- **공조 환경 동일화**: 동일 실온(±2°C), 케이스 제거, 모든 백그라운드 앱 종료, 화면 끔
- **시작 온도 표준화**: 배터리 27±1°C에서 시작 (15분 휴면 후)
- **스레드 수 고정**: `-t 4` (big cores X3+A715×2 + Vulkan dispatch 1)
- **프롬프트 표준화**: AI Hub 12개 카테고리 × 양방향 균등 샘플 (사용자 본인 신청·다운로드)
- **샘플링 간격**: thermal 5초, throughput 1분 평균

---

## 결과

⏳ **S23 측정 대기 중** — 결과 CSV·플롯은 [`results/`](results/) 디렉터리에 추가됩니다.

### PC 베이스라인 (i9-10900, llama.cpp CPU, 4 threads, Q4_K_M)

llama-bench 측정값 (smoke test 동시 확인):

| 항목 | 값 |
|---|---:|
| Prefill (pp64) | **92.56 ± 0.41 tok/s** |
| Decode (tg32) | **20.35 ± 0.16 tok/s** |
| 실제 추론 (--single-turn) | Prefill 91.1 / Decode 23.3 tok/s |
| 모델 메모리 | 1.29 GiB (Q4 5.31 BPW) |

### S23 (Snapdragon 8 Gen 2) 예상치 vs 측정 비교 표

| 항목 | PC bf16 (3090) | PC Q4 (i9-10900) | S23 Q4 (예상) | S23 측정값 |
|---|---:|---:|---:|---:|
| Decode tok/s | ~50+ | 20.4 | 6–10 | TBD |
| Prefill tok/s | ~200+ | 92.6 | 30–60 | TBD |
| BLEU (200쌍) | 32.04 | TBD | 28–31 | TBD |
| chrF++ | 57.26 | TBD | 54–57 | TBD |
| Throttle 시작 | n/a | n/a | 3–8 분 | TBD |
| 30분 평균 tok/s | n/a | n/a | 4–8 | TBD |
| Peak CPU 온도 | n/a | n/a | 80–90°C | TBD |
| Peak 배터리 온도 | n/a | n/a | 40–45°C | TBD |

---

## 디렉터리 구조

```
.
├── prepare/                 PC에서 모델 양자화 (1회 실행)
│   ├── merge_lora.py       HF Kanana base + LoRA → merged HF model
│   └── convert_to_gguf.sh  llama.cpp 변환 + Q4_K_M 양자화
├── bench/                   S23 Termux에서 실행하는 벤치 스크립트
│   ├── run_inference.sh    단발 추론 (tok/s 측정)
│   ├── thermal_logger.sh   5초 간격 CPU/배터리 온도 로깅
│   ├── sustained_30min.sh  30분 연속 추론, 분당 throughput 기록
│   ├── eval_bleu_on_device.py  Q4 BLEU/chrF 재측정
│   └── prompts/            공개 샘플 프롬프트 (AI Hub 데이터 미포함)
├── scripts/
│   ├── build_llama_cpp_android.sh  Termux 빌드 절차
│   └── plot_thermal_timeline.py    Matplotlib 시각화
├── results/                 측정 결과 CSV / 플롯 (계측 후 추가)
├── docs/
│   └── METHODOLOGY.md      측정 프로토콜 상세
└── LICENSE                  Apache 2.0 (코드)
```

---

## 라이선스

| 항목 | 라이선스 |
|---|---|
| 본 레포의 코드 | Apache-2.0 |
| Kanana 1.5 2.1B base 모델 | Apache-2.0 |
| Kanana LoRA 어댑터 가중치 | **CC BY-NC 4.0** (비영리 한정) |
| AI Hub #126 데이터 | NIA 약관 (재배포 금지) — 사용자 본인 신청·다운로드 |

상용 사용을 원하면 본인 데이터로 별도 LoRA 재학습 필요. 본 벤치 자체(속도·발열 측정 코드)는 Apache 2.0이라 어떤 모델로든 재사용 가능.

---

## 인용

```bibtex
@misc{kanana_s23_bench_2026,
  title  = {kanana-s23-translation-bench: On-device Korean-English translation benchmark for Galaxy S23},
  author = {DeepMav},
  year   = {2026},
  url    = {https://github.com/DeepMav/kanana-s23-translation-bench}
}
```
