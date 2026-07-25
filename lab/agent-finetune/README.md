# Symposium Agent Fine-tune — teaching a small model our tools

This folder is a **recipe + dataset** for Symposium's *own* agentic coding model:
a small (~1.5–3B) coder model taught to **emit Symposium tool-call blocks** and to
know the IDE's editor / git / visualisation powers out of the box.

It is the P5 target referenced at the top of
[`ide/extension/src/ai/tools.ts`](../../ide/extension/src/ai/tools.ts):

> *"This same list is the fine-tune target for our own agentic model (P5): we
> teach a small local model to emit these tool calls…"*

## What we're building

A LoRA fine-tune that turns a small instruct base into **`symposium-coder`** — a
model that:

1. **Speaks the tool protocol** — when a task needs a file/git/diagram action it
   emits exactly one fenced ` ```tool_call ` block (the format
   [`providers/local.ts`](../../ide/extension/src/ai/providers/local.ts) parses).
2. **Knows Symposium's capabilities** — the seven tools (`read_file`,
   `list_files`, `apply_edit`, `run_command`, `git_save`, `explain`, `visualize`)
   and *when* a beginner request maps to each (e.g. "how do I save my work" →
   `git_save`; "explain this like I'm 12" → `explain` audience=kid; "draw how
   these connect" → `visualize` flowchart).
3. **Teaches, not just codes** — beginner-friendly explanations, because the
   audience is 15–25-year-old learners (Visionary Sparks' students).

## How it plugs in (already wired)

```
lab/agent-finetune/            ← this folder (dataset + recipe)
   │  build_dataset.py → data/symposium_agent.jsonl  (chat `messages` JSONL)
   ▼
lab/finetune_unsloth.py        ← the EXISTING lab trainer (we reuse it verbatim)
   │  --base <Qwen2.5-Coder-1.5B>  → LoRA → q4_k_m GGUF + Modelfile
   ▼
ollama create symposium-coder  ← the model name pinned by the provider
   ▼
Symposium host proxy (127.0.0.1:47475) / Ollama (11434)
   ▼
ide/extension/src/ai/providers/symposium.ts   ← SymposiumProvider
   • id "symposium", pinnedModel "symposium-coder"
   • appears in the model dropdown / marketplace automatically
```

`SymposiumProvider` extends `LocalProvider` and is **pinned to the model name
`symposium-coder`** with a Symposium persona preamble. As soon as the host serves
an Ollama model called `symposium-coder`, that provider becomes *available* and
the dataset in this folder is what gives it its tool-using behaviour. Nothing in
the extension needs to change — this is purely the "brain" behind the already-
shipped provider.

## Status — HONEST

| Piece | State |
|---|---|
| Dataset schema | ✅ delivered (`dataset/schema.md`) |
| Seed data (hand-written) | ✅ delivered (`dataset/seed.jsonl`, ~40 examples) |
| Dataset builder | ✅ delivered (`build_dataset.py`, pure-python) |
| Train config | ✅ delivered (`train_config.yaml`) |
| Export → Ollama steps | ✅ delivered (`export_to_ollama.md`) |
| **Actual GPU training** | ⏳ **DEFERRED — needs a GPU** |

We do **not** train here. Training needs a GPU box (RTX 4050 for the 1.5B, or a
GCP L4/T4 spot VM for 3B). See the lab hardware table in
[`../README.md`](../README.md) and the spot-VM runbook in
[`../../deploy/gcp-quickstart.md`](../../deploy/gcp-quickstart.md) — the same
"download any model" host box can also run this fine-tune.

## Run it (on a GPU box)

```bash
# from repo root, in the lab's Python 3.11 venv (see lab/README.md)
cd lab

# 1. Build the training file from the hand-written seed.
python agent-finetune/build_dataset.py \
    --seed agent-finetune/dataset/seed.jsonl \
    --out  data/symposium_agent.jsonl

# 2. Fine-tune with the EXISTING lab trainer (params from train_config.yaml).
pip install "unsloth @ git+https://github.com/unslothai/unsloth.git" trl datasets
python finetune_unsloth.py \
    --data data/symposium_agent.jsonl \
    --base unsloth/Qwen2.5-Coder-1.5B-Instruct \
    --gguf symposium-coder \
    --max-seq 4096 --steps 120

# 3. Serve it locally (see export_to_ollama.md for detail).
ollama create symposium-coder -f symposium-coder/Modelfile
```

Then open Symposium → model dropdown → **Symposium Coder (fine-tuned)**.

## Design choices (why these)

- **Base = `Qwen2.5-Coder-1.5B-Instruct`** (or `-3B` on bigger VRAM). Coder base
  ⇒ strong at code; 1.5B fits a 6 GB laptop GPU in 4-bit QLoRA; ₹0-first.
- **LoRA, not full fine-tune** — a few hundred examples only need to *steer*
  format + persona, not re-teach coding. Cheapest path that works.
- **Reuse `finetune_unsloth.py`** — we did NOT fork the pipeline. This folder is
  only the dataset + config; the trainer, GGUF export and `ollama create` step
  are the lab's existing ones. One workshop, not two.
