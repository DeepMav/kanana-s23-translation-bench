# S23 — Run 1 (2026-05-29)

Kanana 1.5 2.1B base + AI Hub #126 LoRA → Q4_K_M GGUF, llama.cpp on Galaxy S23 Termux (Snapdragon 8 Gen 2).

## 측정 조건

| 항목 | 값 |
|---|---|
| 기기 | Galaxy S23 (SM-S918N, Korean) |
| OS | Android 14 (kernel 5.15.178) |
| 런타임 | llama.cpp commit `33c718db1`, build `b9403` |
| 빌드 플래그 | `-DGGML_CPU_ARM_ARCH=armv8.4-a+dotprod+fp16 -O3`, spawn.h stub로 server-tools 컴파일 우회 |
| 모델 | `kanana-1.5-2.1b-koen-q4_k_m.gguf` (1.30 GiB, 5.31 BPW) |
| Threads | 4 (`-t 4`; nproc은 3만 보고) |
| Context | 1024 tokens |
| n_predict | 200 tokens |
| 측정 시간 | 30분 연속, thermal logger 5초 간격 |
| 배터리 상태 시작 | 35.0°C, 90% (UNPLUGGED, DISCHARGING) |

## 결과 — Throughput

| 지표 | 값 |
|---|---:|
| Prefill tok/s (mean / median / min-max) | 6.98 / 7.00 / 5.70–8.20 |
| **Decode tok/s** (mean / median / min-max) | **2.25 / 2.20 / 1.70–2.80** |
| Wall time per 200-token run | 24.2 – 31.7 s (median 25.8 s) |
| 30분 동안 처리한 inference 횟수 | 69 |
| 첫 1분 median decode | 2.40 tok/s |
| 마지막 1분 median decode | 2.40 tok/s |

→ **Throttle curve 관찰되지 않음** (decode rate가 30분 동안 노이즈 수준 내에서 일정).

## 결과 — Thermal

| Zone | 시작 | 끝 | Peak | Δ peak-start |
|---|---:|---:|---:|---:|
| Battery | 35.0°C | 37.7°C | 37.7°C | +2.7°C |
| aoss-0 (SoC 평균) | 40.2°C | 41.0°C | 46.5°C | +6.3°C |
| cpuss-0 (CPU 클러스터 0) | 43.0°C | 43.0°C | 51.3°C | +8.3°C |
| gpuss-0 (GPU 클러스터 0) | 41.4°C | 43.0°C | 47.3°C | +5.9°C |
| ddr (메모리) | 40.6°C | 41.4°C | 47.3°C | +6.7°C |
| 배터리 잔량 | 90% | 83% | — | −7% (≈14%/h) |

모든 zone이 thermal 한계(보통 80–90°C)에서 한참 떨어져 있음.

## 핵심 발견 — **Policy-locked, not thermal-throttled**

**`cpu7_freq_khz`가 30분 내내 정확히 864 MHz로 고정** (정격 X3 prime 3.36 GHz의 **26%**).

CPU 온도(51°C peak)는 throttling 임계점에 한참 못 미치고, 발열로 인한 클럭 하강의 흔적도 없음. 그럼에도 클럭이 올라가지 않음 — Android (One UI 6.1)의 background-task power policy가 Termux 앱의 CPU를 의도적으로 제한한 것으로 추정.

**의미**:
- S23이 "물리적으로" 이 속도밖에 못 낸다는 게 아님
- Foreground/screen-on/native APK 환경에선 더 빠를 가능성 큼
- Termux 측정값을 "S23의 한계 성능"으로 보면 안 됨 — "background 앱 정책 하의 성능"

## PC 베이스라인 대비

| | PC i9-10900 (4t) | S23 Termux (4t) | 비율 |
|---|---:|---:|---:|
| Prefill tok/s | 91.1 | 6.98 | 7.7% |
| Decode tok/s | 23.3 | 2.25 | 9.7% |
| 30-min 안정성 | — | 변동 ±15% | 안정 |

## 추후 과제

- [ ] **Foreground 모드 비교** — Termux를 화면 켠 상태로 측정 (현재 화면 꺼지면 더 큰 제한)
- [ ] **APK 형태로 native 측정** — Android Service나 Activity로 돌리면 governor가 다르게 동작할 가능성
- [ ] **`taskset`/`sched_setaffinity`로 BIG core pinning** — 작동하면 throughput 3-5배 가능
- [ ] **Q5_K_M / Q8_0 비교** — Q4 손실 정량화
- [ ] **Vulkan(Adreno 740) 백엔드** — GPU 경로 시도
- [ ] **BLEU 재검증** — val_2k.jsonl 필요 (AI Hub 본인 신청 데이터)

## 파일

- `sustained_1780030806.csv` — 69 iteration × (timestamp, run_idx, prefill_tps, decode_tps, total_s)
- `thermal_1780030806.csv` — 124 sample × 97 thermal zones + 배터리 + cpu7 freq
- `timeline.png` — 배터리/CPU 온도 + cpu7 주파수 + decode tok/s 시계열
