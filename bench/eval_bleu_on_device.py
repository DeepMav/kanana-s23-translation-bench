#!/usr/bin/env python3
"""S23 Termux에서 Kanana Q4_K_M의 BLEU/chrF 재측정 — PC bf16 결과와 비교용.
   사용자 본인이 AI Hub #126 약관에 따라 다운받은 val_2k.jsonl이 필요.
"""
import argparse, json, random, subprocess, time, os, sys

DEFAULT_LLAMA = os.path.expanduser("~/llama.cpp/build/bin/llama-cli")


def build_prompt(ex):
    inst = ex["instruction"]
    inp = ex.get("input", "")
    if inp:
        return (f"### Instruction:\n{inst}\n\n"
                f"### Input:\n{inp}\n\n"
                f"### Response:\n")
    return f"### Instruction:\n{inst}\n\n### Response:\n"


def run_llama(llama_cli, gguf, prompt, threads, nctx, npredict):
    proc = subprocess.run(
        [llama_cli, "-m", gguf, "-t", str(threads), "-c", str(nctx),
         "-n", str(npredict), "--temp", "0",
         "-p", prompt, "--no-display-prompt", "-no-cnv"],
        capture_output=True, text=True, check=False,
    )
    return proc.stdout.strip()


def clean_response(resp):
    for stop in ("\n### Instruction", "\n###", "\n\n###"):
        i = resp.find(stop)
        if i >= 0:
            resp = resp[:i].strip()
            break
    return resp


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gguf", required=True)
    ap.add_argument("--val", required=True, help="JSONL: instruction/input/output/category/direction")
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--threads", type=int, default=4)
    ap.add_argument("--nctx", type=int, default=1024)
    ap.add_argument("--npredict", type=int, default=200)
    ap.add_argument("--llama-cli", default=DEFAULT_LLAMA)
    ap.add_argument("--out", default="results/eval_q4_on_s23.json")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    try:
        import sacrebleu
    except ImportError:
        print("❌ sacrebleu 미설치. Termux에서: pip install sacrebleu", file=sys.stderr)
        sys.exit(1)

    random.seed(args.seed)
    with open(args.val) as f:
        rows = [json.loads(l) for l in f]
    samples = random.sample(rows, args.n)
    print(f"📂 평가 샘플 {args.n}개, GGUF: {args.gguf}")

    preds, refs = [], []
    t_total = time.time()
    for i, ex in enumerate(samples, 1):
        raw = run_llama(args.llama_cli, args.gguf, build_prompt(ex),
                        args.threads, args.nctx, args.npredict)
        preds.append(clean_response(raw))
        refs.append(ex["output"])
        if i % 10 == 0 or i == args.n:
            elapsed = time.time() - t_total
            print(f"  [{i:>3}/{args.n}] elapsed={elapsed:.1f}s  est_total={elapsed*args.n/i:.0f}s")

    dt = time.time() - t_total
    bleu = sacrebleu.corpus_bleu(preds, [refs]).score
    chrf = sacrebleu.corpus_chrf(preds, [refs]).score

    print("\n" + "=" * 50)
    print(f"📊 S23 Q4_K_M 결과 (n={args.n})")
    print(f"   BLEU:   {bleu:.2f}   (PC bf16 기준 32.04)")
    print(f"   chrF++: {chrf:.2f}   (PC bf16 기준 57.26)")
    print(f"   소요:   {dt:.1f}s  ({args.n/dt:.2f} samples/s)")

    out = {
        "device": "Galaxy S23 (Snapdragon 8 Gen 2)",
        "runtime": "llama.cpp",
        "quant": "Q4_K_M",
        "gguf": os.path.basename(args.gguf),
        "n_samples": args.n,
        "bleu": bleu,
        "chrf": chrf,
        "wall_time_s": dt,
        "samples_per_s": args.n / dt,
        "threads": args.threads,
        "nctx": args.nctx,
        "npredict": args.npredict,
        "pc_bf16_baseline": {"bleu": 32.04, "chrf": 57.26},
        "delta_vs_bf16": {"bleu": bleu - 32.04, "chrf": chrf - 57.26},
    }
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"💾 저장: {args.out}")


if __name__ == "__main__":
    main()
