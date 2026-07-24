# Symposium Lab — the model workshop

Everything you need to **develop, fine-tune, and RAG-enable models** for Visionary
Sparks, in one folder. Nothing here touches the Flutter app — it's a self-contained
playground so anyone (you, a friend with a GPU, a rented cloud box) can be productive
in ~10 minutes.

> Golden rule: **Python 3.11** in a venv. Not 3.13/3.14 — the ML stack has no wheels
> for them yet.

---

## Who runs what (match the task to the hardware)

| Box | Specs | What it's good for |
|---|---|---|
| No-GPU laptop | Ryzen 5 / 16 GB, no GPU | **RAG pipeline** (`rag_pipeline.py`) — CPU embeddings, zero GPU. Dataset prep. |
| Gaming laptop | i7 / RTX 4050 6 GB / 32 GB | **Fine-tune small models** (`finetune_unsloth.py`) — 1B–3B in 4-bit QLoRA. |
| GCP spot GPU | L4 / T4 (free credit) | Fine-tune up to **8B**, big RAG indexes, the "download any model" host. |
| Phone | Android/iOS | **Run** tiny models client-side (WebLLM / MLC) or hit the cloud host. Not training. |

---

## Quick start

```bash
# 1. one-time environment (from repo root)
scripts/setup_env.ps1        # Windows PowerShell
scripts/setup_env.sh         # Linux / macOS / Arch

# 2. RAG — works on ANY box, no GPU
cd lab
python rag_pipeline.py ingest ./data        # or point at a folder of PDFs/MD
python rag_pipeline.py ask "what is normalization?"

# 3. Fine-tune — GPU box only
pip install "unsloth @ git+https://github.com/unslothai/unsloth.git" trl datasets
python finetune_unsloth.py --data data/socratic_sample.jsonl --steps 60
ollama create astra-tutor -f astra-tutor/Modelfile
ollama run astra-tutor
```

---

## The files

- **`rag_pipeline.py`** — ingest PDF/MD/txt → chunk → embed (fastembed, CPU) →
  Qdrant (local, on-disk) → retrieve. The retrieval half of RAG; feed the top
  chunks into any chat model's prompt.
- **`finetune_unsloth.py`** — QLoRA fine-tune with [Unsloth](https://github.com/unslothai/unsloth)
  and export a `q4_k_m` GGUF that Ollama loads directly. GPU required.
- **`data/socratic_sample.jsonl`** — a 4-example Socratic-tutor dataset in chat
  `messages` format. Replace/extend it with real Astra transcripts.
- **`requirements.txt`** — CPU/RAG deps. Fine-tuning deps are installed separately
  (they pull CUDA torch).
- **`.env.example`** — HF token, admin token, optional remote Qdrant.

---

## First real target: **the in-app help bot**

Our first shipped fine-tune should be the **"Astra Guide"** — the little helper bot
in the app's bottom-right corner that tells a user *exactly what they need* for a
feature ("to fine-tune you need a GPU box + a .jsonl dataset…"). Two flavours:
- **desktop/linux** guide — a 3B tutor tuned on our docs + this README.
- **mobile** guide — a 1B model small enough to run client-side on a phone.

The recipe is already here: put the guidance Q&A into a `messages` .jsonl, run
`finetune_unsloth.py`, ship the GGUF. That's the proof-of-skill artifact.

---

## Want something stronger than this starter? (honest options)

- **Fine-tuning frameworks:** Unsloth (fastest, lowest VRAM — what we use) →
  [Axolotl](https://github.com/axolotl-ai-cloud/axolotl) or
  [LLaMA-Factory](https://github.com/hiyouga/LLaMA-Factory) (more knobs, multi-GPU, YAML configs).
- **Managed GPU + training (no ops):** [Modal](https://modal.com),
  [Together AI](https://www.together.ai), [Replicate](https://replicate.com),
  RunPod, Vast.ai. Pay per second; great when the free GCP credit runs out.
- **RAG frameworks:** this hand-rolled script → [LlamaIndex](https://www.llamaindex.ai)
  or [Haystack](https://haystack.deepset.ai) when you need routers, rerankers, evals.
- **On-phone inference:** [MLC-LLM](https://llm.mlc.ai) / WebLLM, or
  [llama.cpp](https://github.com/ggerganov/llama.cpp) via a native plugin.
