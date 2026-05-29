#!/usr/bin/env python3
"""Kanana 1.5 2.1B base + harveykim/kanana-1.5-2.1b-aihub-ko-en-lora 머지
   → merged/ 디렉터리에 단일 HF 모델로 저장 (이후 GGUF 변환 입력으로 사용).
"""
import argparse, os, torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel

DEFAULT_BASE = "kakaocorp/kanana-1.5-2.1b-base"
DEFAULT_LORA = "harveykim/kanana-1.5-2.1b-aihub-ko-en-lora"
DEFAULT_OUT = "merged"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=DEFAULT_BASE)
    ap.add_argument("--lora", default=DEFAULT_LORA)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--dtype", default="bfloat16", choices=["bfloat16", "float16"])
    args = ap.parse_args()

    dtype = {"bfloat16": torch.bfloat16, "float16": torch.float16}[args.dtype]

    print(f"📥 베이스 로드: {args.base} ({args.dtype})")
    base = AutoModelForCausalLM.from_pretrained(
        args.base, torch_dtype=dtype, device_map="cpu", low_cpu_mem_usage=True,
    )

    print(f"📥 LoRA 어댑터 로드: {args.lora}")
    model = PeftModel.from_pretrained(base, args.lora)

    print("🔀 LoRA 머지 (merge_and_unload)")
    model = model.merge_and_unload()

    print(f"📥 토크나이저 로드: {args.lora}")
    tok = AutoTokenizer.from_pretrained(args.lora)

    os.makedirs(args.out, exist_ok=True)
    print(f"💾 저장: {args.out}/")
    model.save_pretrained(args.out, safe_serialization=True)
    tok.save_pretrained(args.out)
    print("✅ 완료. 다음: bash prepare/convert_to_gguf.sh")


if __name__ == "__main__":
    main()
