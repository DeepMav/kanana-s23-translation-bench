#!/usr/bin/env python3
"""thermal_*.csv + sustained_*.csv → 단일 타임라인 플롯
   - 위: 배터리 + CPU 주요 zone 온도
   - 가운데: big-core 주파수 (있을 때)
   - 아래: 분당 decode tok/s
"""
import argparse, csv, sys, os
from collections import defaultdict
from datetime import datetime

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def read_thermal(path):
    with open(path) as f:
        reader = csv.reader(f)
        header = next(reader)
        cols = {h: [] for h in header}
        for row in reader:
            for h, v in zip(header, row):
                cols[h].append(v)
    return header, cols


def to_floats(xs, scale=1.0):
    out = []
    for x in xs:
        try:
            out.append(float(x) * scale)
        except ValueError:
            out.append(float("nan"))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("thermal_csv")
    ap.add_argument("sustained_csv", nargs="?", default=None,
                    help="(선택) sustained_30min.sh 결과 CSV — 분당 throughput 오버레이")
    ap.add_argument("--out", default="results/thermal_timeline.png")
    args = ap.parse_args()

    header, cols = read_thermal(args.thermal_csv)
    ts = to_floats(cols["timestamp"])
    t0 = ts[0]
    minutes = [(t - t0) / 60 for t in ts]

    # 새 포맷: batt_temp_c (Celsius float). 구버전 호환: batt_temp_decic (deci-C → C).
    if "batt_temp_c" in cols:
        batt_c = to_floats(cols["batt_temp_c"])
        batt_col = "batt_temp_c"
    else:
        batt_c = to_floats(cols.get("batt_temp_decic", []), scale=0.1)
        batt_col = "batt_temp_decic"

    # CPU zones — 흥미로운 것만 (cpuss, gpu, aoss, skin)
    interesting = []
    for h in header:
        if h in ("timestamp", batt_col, "cpu7_freq_khz"):
            continue
        if any(k in h.lower() for k in ("cpuss", "gpu", "aoss", "skin", "battery")):
            interesting.append(h)

    has_freq = "cpu7_freq_khz" in cols
    sustained_data = None
    if args.sustained_csv and os.path.exists(args.sustained_csv):
        with open(args.sustained_csv) as f:
            reader = csv.DictReader(f)
            sustained_data = list(reader)

    n_subplots = 2 + (1 if has_freq else 0) + (1 if sustained_data else 0)
    fig, axes = plt.subplots(n_subplots, 1, figsize=(11, 2.6 * n_subplots), sharex=True)
    if n_subplots == 1:
        axes = [axes]
    axi = 0

    # 1) 배터리 온도
    ax = axes[axi]; axi += 1
    ax.plot(minutes, batt_c, label="Battery", color="tab:red", lw=2)
    ax.set_ylabel("Battery °C")
    ax.grid(alpha=0.3)
    ax.legend(loc="lower right")
    ax.set_title(f"S23 thermal + throughput timeline — start {datetime.fromtimestamp(t0):%Y-%m-%d %H:%M}")

    # 2) CPU zones — thermal_logger가 이미 Celsius로 변환해 기록
    ax = axes[axi]; axi += 1
    for h in interesting:
        vals = to_floats(cols[h])
        ax.plot(minutes, vals, label=h, lw=1.2, alpha=0.85)
    ax.set_ylabel("CPU °C")
    ax.grid(alpha=0.3)
    ax.legend(loc="lower right", fontsize=7, ncol=2)

    # 3) CPU 주파수
    if has_freq:
        ax = axes[axi]; axi += 1
        f_mhz = [v / 1000 if v == v else float("nan") for v in to_floats(cols["cpu7_freq_khz"])]
        ax.plot(minutes, f_mhz, color="tab:purple", lw=1.5, label="cpu7 (X3) MHz")
        ax.axhline(3360, color="gray", ls="--", lw=0.8, label="rated 3.36 GHz")
        ax.set_ylabel("CPU7 MHz")
        ax.grid(alpha=0.3); ax.legend(loc="lower right", fontsize=8)

    # 4) Sustained throughput
    if sustained_data:
        ax = axes[axi]; axi += 1
        s_ts = [float(r["timestamp"]) for r in sustained_data]
        s_min = [(t - t0) / 60 for t in s_ts]
        s_dec = []
        for r in sustained_data:
            try: s_dec.append(float(r["decode_tps"]))
            except (ValueError, KeyError): s_dec.append(float("nan"))
        ax.plot(s_min, s_dec, "o-", color="tab:blue", ms=3, lw=1, label="decode tok/s")
        ax.set_ylabel("Decode tok/s"); ax.grid(alpha=0.3); ax.legend(loc="lower right")

    axes[-1].set_xlabel("Elapsed time (min)")

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    plt.tight_layout()
    plt.savefig(args.out, dpi=130)
    print(f"💾 저장: {args.out}")


if __name__ == "__main__":
    main()
