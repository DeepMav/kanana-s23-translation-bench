#!/usr/bin/env bash
# 5초마다 CPU/배터리 온도 + big-core 주파수를 샘플링해 CSV로 기록.
# 사용법:
#   bash bench/thermal_logger.sh results/thermal_run1.csv &
#   THERMAL_PID=$!
#   ... (벤치 실행) ...
#   kill $THERMAL_PID
set -u

OUT="${1:?출력 CSV 경로}"
INTERVAL="${INTERVAL:-5}"

mkdir -p "$(dirname "$OUT")"

# Snapdragon 8 Gen 2의 주요 thermal zone 이름 — S23 펌웨어에 따라 일부 다를 수 있음.
# 가능한 모든 zone을 한 줄에 기록하고 헤더에 이름을 함께 남김.
ZONES=()
ZONE_NAMES=()
for z in /sys/class/thermal/thermal_zone*; do
  [[ -r "$z/temp" ]] || continue
  ZONES+=("$z/temp")
  NAME="unknown"
  [[ -r "$z/type" ]] && NAME=$(cat "$z/type" 2>/dev/null || echo unknown)
  ZONE_NAMES+=("$NAME")
done

# big core (cpu7 = X3 prime) 주파수
CPU7_FREQ="/sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq"
HAS_CPU7_FREQ=0
[[ -r "$CPU7_FREQ" ]] && HAS_CPU7_FREQ=1

# 헤더
HEADER="timestamp,batt_temp_decic"
for n in "${ZONE_NAMES[@]}"; do HEADER+=",${n}_millic"; done
[[ "$HAS_CPU7_FREQ" == "1" ]] && HEADER+=",cpu7_freq_khz"
echo "$HEADER" > "$OUT"

trap "echo '[thermal_logger] stopped' >&2; exit 0" INT TERM

while true; do
  TS=$(date +%s)

  # 배터리 온도 — dumpsys 출력에서 "temperature: NNN" (deci-Celsius)
  BATT=$(dumpsys battery 2>/dev/null | awk '/temperature:/ {print $2; exit}')
  BATT="${BATT:-NA}"

  ROW="$TS,$BATT"
  for tf in "${ZONES[@]}"; do
    V=$(cat "$tf" 2>/dev/null || echo NA)
    ROW+=",$V"
  done

  if [[ "$HAS_CPU7_FREQ" == "1" ]]; then
    F=$(cat "$CPU7_FREQ" 2>/dev/null || echo NA)
    ROW+=",$F"
  fi

  echo "$ROW" >> "$OUT"
  sleep "$INTERVAL"
done
