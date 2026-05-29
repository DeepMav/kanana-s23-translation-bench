# 측정 방법론 (METHODOLOGY)

본 문서는 갤럭시 S23에서 Kanana 2.1B Q4_K_M 한↔영 번역 모델의 속도·발열·지속 처리량을 재현 가능하게 측정하기 위한 프로토콜입니다.

## 1. 외부 변수 통제

| 변수 | 통제 방법 |
|---|---|
| 실온 | 24±2°C, 직사광선 없음, 에어컨/난방 OFF로 통일 |
| 케이스 | 제거 (방열 방해 제거) |
| 화면 | 측정 중 OFF (`adb shell input keyevent KEYCODE_POWER`) |
| 백그라운드 앱 | 종료, 항공기 모드 권장 (셀룰러 모뎀 발열 차단) |
| Wi-Fi | OFF (선택) — 측정 중에는 결과 동기화 불필요 |
| 충전기 | **분리** (충전 시 배터리 온도 ↑, 발열 결과 왜곡) |
| 시작 온도 | 배터리 27±1°C, CPU SoC 35°C 이하 — 15분 휴면 후 측정 |

## 2. 빌드·실행 환경

- **Termux 최신 안정판** (F-Droid 빌드 권장; Play 스토어 버전은 옛 버전)
- **llama.cpp**: 측정 시점 main 브랜치 commit hash를 결과 CSV에 기록
- **컴파일러**: clang (Termux 기본), `-O3 -march=armv8.4-a+dotprod+fp16`
- **스레드 수**: `-t 4` (Cortex-X3 + A715×2 + A710×1)
- **Vulkan 백엔드**: Adreno 740 활성화 시 별도 표기
- **컨텍스트 길이**: 1024
- **샘플링**: greedy (`--temp 0`) — 재현성 우선

## 3. 측정 지표 정의

### 3.1 Prefill tok/s
입력 프롬프트 N개 토큰을 KV cache에 채우는 데 걸린 시간으로 N을 나눈 값.
llama.cpp `--verbose-prompt` 또는 stderr의 `prompt eval time = ...` 줄에서 추출.

### 3.2 Decode tok/s
모델이 새 토큰 M개를 생성하는 데 걸린 시간으로 M을 나눈 값.
stderr의 `eval time = ... (... tokens, ... ms per token)` 줄에서 추출.

### 3.3 Time-to-first-token (TTFT)
입력 시작부터 첫 디코드 토큰까지 (= prefill 시간 + 첫 step 시간).

### 3.4 CPU 온도
`cat /sys/class/thermal/thermal_zone*/temp` 모든 zone 동시 샘플링.
Snapdragon 8 Gen 2의 주요 zone: `cpuss-0` (X3), `cpuss-1/2` (A715), `gpu`, `aoss-0` (SoC 평균).
값은 milli-Celsius (90000 = 90.0°C).

### 3.5 배터리 온도
`dumpsys battery | grep temperature` — deci-Celsius (300 = 30.0°C).

### 3.6 Throttling 시작
big-core (cpuss-0) 클럭이 정격 3.36 GHz 대비 10% 이상 하락한 첫 시점.
`cat /sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq` (cpu7 = X3 prime core, S23 매핑).
또는 decode tok/s가 시작 10초 평균 대비 20% 이하 떨어진 시점 (functional throttle 기준).

### 3.7 30분 평균 throughput
30분 연속 추론 동안의 분당 decode tok/s를 평균. throttled steady-state 측정.

### 3.8 Q4 양자화 손실
PC bf16 BLEU 32.04 / chrF++ 57.26 대비 S23 Q4_K_M 동일 200쌍 BLEU/chrF 감소량.

## 4. 측정 절차 (단일 run)

1. 15분 휴면 (배터리/SoC cool-down)
2. `dumpsys battery | grep temperature` 시작 온도 기록
3. `thermal_logger.sh results/thermal_<timestamp>.csv &` 백그라운드 시작
4. 측정 대상 스크립트 실행 (run_inference.sh / sustained_30min.sh / eval_bleu_on_device.py)
5. 종료 후 thermal logger 정지
6. 다음 run 전까지 충분히 휴면 (배터리 ≤28°C 복귀까지)

## 5. 보고 형식 (results/*.csv)

### thermal_*.csv 컬럼
```
timestamp_unix, batt_temp_c, cpuss0_c, cpuss1_c, cpuss2_c, gpu_c, aoss0_c, cpu7_freq_khz
```

### sustained_*.csv 컬럼
```
minute, n_tokens_decoded, decode_tok_per_s, ttft_s, prefill_tok_per_s
```

## 6. 최소 3회 반복

각 측정은 동일 조건에서 **3회 반복**, 결과 CSV는 `results/<measurement>_run<N>.csv` 명명. 본 레포의 결과 섹션에는 중앙값과 ±스프레드를 함께 표기.

## 7. 알려진 한계

- **Termux 권한**: `/sys/class/thermal/` 일부 zone은 SELinux로 차단될 수 있음. 접근 가능한 zone만 기록 (보고서에 명시).
- **클럭 주파수 일부 미공개**: 일부 S23 펌웨어에서는 `scaling_cur_freq` 권한 없음. 그 경우 functional throttle 기준(decode tok/s 하락)으로 대체.
- **배경 OS 작업**: One UI의 자동 백그라운드 작업이 노이즈를 만들 수 있음 → 측정 전 `pm disable-user --user 0 <불필요 패키지>` 권장하지 않음 (재현성 vs 사용자 환경 trade-off).
- **Vulkan 백엔드 안정성**: 2.1B Q4 + Adreno 740 조합은 일부 빌드에서 OOM 가능성 있음. CPU-only 결과를 우선 보고, Vulkan은 부록.
