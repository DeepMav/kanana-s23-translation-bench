#!/usr/bin/env bash
# 5초마다 CPU/배터리 온도 + big-core 주파수를 샘플링해 CSV로 기록 (Celsius float).
#
# 배터리 온도 소스 자동 감지 (우선순위):
#   1) termux-battery-status (Termux:API, root 불필요 — S23 기본 경로)
#   2) dumpsys battery (rooted 기기 또는 adb shell 환경)
#   3) NA
#
# CPU thermal zone:
#   /sys/class/thermal/thermal_zone*/temp 중 읽기 가능한 것만 자동 수집.
#   Android 14 stock에서는 대부분 SELinux 차단됨 — 보고서에 측정된 zone 명시.
#
# 사용법:
#   bash bench/thermal_logger.sh results/thermal_run1.csv &
#   THERMAL_PID=$!
#   ... (벤치 실행) ...
#   kill $THERMAL_PID
set -u

OUT="${1:?출력 CSV 경로}"
INTERVAL="${INTERVAL:-5}"

mkdir -p "$(dirname "$OUT")"

# 배터리 온도 소스 감지
BATT_SRC="NA"
if command -v termux-battery-status >/dev/null 2>&1; then
  BATT_SRC="termux"
elif command -v dumpsys >/dev/null 2>&1; then
  BATT_SRC="dumpsys"
fi
echo "[thermal_logger] battery source: $BATT_SRC" >&2

# 읽기 가능한 thermal zone 자동 탐색
ZONES=()
ZONE_NAMES=()
for z in /sys/class/thermal/thermal_zone*; do
  [[ -r "$z/temp" ]] || continue
  ZONES+=("$z/temp")
  NAME="unknown"
  [[ -r "$z/type" ]] && NAME=$(cat "$z/type" 2>/dev/null || echo unknown)
  ZONE_NAMES+=("$NAME")
done
echo "[thermal_logger] readable zones: ${#ZONES[@]} (${ZONE_NAMES[*]:-none})" >&2

# big core (cpu7 = X3 prime) 주파수 — 일부 S23 펌웨어에선 차단됨
CPU7_FREQ="/sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq"
HAS_CPU7_FREQ=0
[[ -r "$CPU7_FREQ" ]] && HAS_CPU7_FREQ=1

# 헤더 — 모든 온도는 Celsius float
HEADER="timestamp,batt_temp_c"
for n in "${ZONE_NAMES[@]}"; do HEADER+=",${n}_c"; done
[[ "$HAS_CPU7_FREQ" == "1" ]] && HEADER+=",cpu7_freq_khz"
echo "$HEADER" > "$OUT"

trap "echo '[thermal_logger] stopped' >&2; exit 0" INT TERM

while true; do
  TS=$(date +%s)

  # 배터리 온도 (Celsius float)
  case "$BATT_SRC" in
    termux)
      BATT=$(termux-battery-status 2>/dev/null | grep -oE '"temperature":[[:space:]]*[0-9.]+' | grep -oE '[0-9.]+$')
      ;;
    dumpsys)
      # dumpsys는 deci-Celsius (정수) → 10으로 나눠 Celsius로
      RAW=$(dumpsys battery 2>/dev/null | awk '/temperature:/ {print $2; exit}')
      [[ -n "$RAW" ]] && BATT=$(awk "BEGIN { printf \"%.1f\", $RAW/10 }") || BATT=""
      ;;
    *)
      BATT=""
      ;;
  esac
  BATT="${BATT:-NA}"

  ROW="$TS,$BATT"
  for tf in "${ZONES[@]}"; do
    V=$(cat "$tf" 2>/dev/null || echo NA)
    # thermal_zone*/temp 은 milli-Celsius → 1000으로 나눠 Celsius로
    if [[ "$V" != "NA" ]]; then
      V=$(awk "BEGIN { printf \"%.2f\", $V/1000 }")
    fi
    ROW+=",$V"
  done

  if [[ "$HAS_CPU7_FREQ" == "1" ]]; then
    F=$(cat "$CPU7_FREQ" 2>/dev/null || echo NA)
    ROW+=",$F"
  fi

  echo "$ROW" >> "$OUT"
  sleep "$INTERVAL"
done
