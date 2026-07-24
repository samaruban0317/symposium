"""Symposium Lab — QLoRA fine-tune with Unsloth, export straight to GGUF for Ollama.

GPU REQUIRED. This runs on the RTX 4050 box or a GCP L4/T4 spot VM — NOT on CPU.
It trains a small base model on a Socratic chat dataset (`messages` .jsonl) and
writes a q4_k_m .gguf you can load directly in Ollama.

Install first (see lab/README.md — do this in a Python 3.11 venv):
    pip install "unsloth @ git+https://github.com/unslothai/unsloth.git" trl datasets

Run:
    python finetune_unsloth.py --data data/socratic_sample.jsonl \
        --base unsloth/Llama-3.2-3B-Instruct --steps 60

Then:
    ollama create astra-tutor -f astra-tutor/Modelfile
    ollama run astra-tutor
"""
from __future__ import annotations

import argparse


def main() -> None:
    ap = argparse.ArgumentParser(description="Unsloth QLoRA fine-tune -> GGUF")
    ap.add_argument("--data", required=True, help="chat .jsonl with a 'messages' field per line")
    # 3B fits a 6GB 4050 in 4-bit; bump to 8B on the GCP L4/T4.
    ap.add_argument("--base", default="unsloth/Llama-3.2-3B-Instruct")
    ap.add_argument("--out", default="astra-lora", help="LoRA adapter output dir")
    ap.add_argument("--gguf", default="astra-tutor", help="GGUF output dir (has the Modelfile)")
    ap.add_argument("--steps", type=int, default=60)
    ap.add_argument("--max-seq", type=int, default=2048)
    args = ap.parse_args()

    # Imported here so `--help` works without the heavy CUDA stack installed.
    import torch
    from datasets import load_dataset
    from trl import SFTConfig, SFTTrainer
    from unsloth import FastLanguageModel
    from unsloth.chat_templates import get_chat_template

    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=args.base,
        max_seq_length=args.max_seq,
        load_in_4bit=True,      # QLoRA — the whole point (fits small VRAM)
        dtype=None,             # auto: bf16 where supported, else fp16
    )
    model = FastLanguageModel.get_peft_model(
        model,
        r=16, lora_alpha=16, lora_dropout=0.0,
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                        "gate_proj", "up_proj", "down_proj"],
        use_gradient_checkpointing="unsloth",
        random_state=42,
    )
    tokenizer = get_chat_template(tokenizer, chat_template="llama-3.1")

    def to_text(example):
        return {"text": tokenizer.apply_chat_template(
            example["messages"], tokenize=False, add_generation_prompt=False)}

    ds = load_dataset("json", data_files=args.data, split="train").map(to_text)

    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=ds,
        args=SFTConfig(
            dataset_text_field="text",
            max_seq_length=args.max_seq,
            per_device_train_batch_size=2,
            gradient_accumulation_steps=4,
            warmup_steps=5,
            max_steps=args.steps,
            learning_rate=2e-4,
            logging_steps=1,
            optim="adamw_8bit",
            weight_decay=0.01,
            lr_scheduler_type="linear",
            seed=42,
            output_dir="outputs",
            bf16=torch.cuda.is_bf16_supported(),
            fp16=not torch.cuda.is_bf16_supported(),
        ),
    )
    trainer.train()

    model.save_pretrained(args.out)
    tokenizer.save_pretrained(args.out)
    print(f"LoRA adapter -> {args.out}/")

    # Merge + quantise to a GGUF Ollama understands, plus a ready Modelfile.
    model.save_pretrained_gguf(args.gguf, tokenizer, quantization_method="q4_k_m")
    print(f"GGUF -> {args.gguf}/   run:  ollama create {args.gguf} -f {args.gguf}/Modelfile")


if __name__ == "__main__":
    main()
