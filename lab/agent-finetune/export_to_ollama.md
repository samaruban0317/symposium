# Export `symposium-coder` → Ollama (and it just shows up in Symposium)

The finish line: turn the trained LoRA into a GGUF, register it with Ollama under
the name **`symposium-coder`**, and it appears automatically in Symposium's model
dropdown — because
[`providers/symposium.ts`](../../ide/extension/src/ai/providers/symposium.ts) is
already pinned to that exact model name.

> GPU box only for the training step. The `ollama create` + serving steps run on
> any machine that has the GGUF and Ollama installed (including the deploy/ host).

---

## Path A — the easy path (Unsloth does the GGUF for you)

`lab/finetune_unsloth.py` already calls `model.save_pretrained_gguf(...)`, which
**merges the LoRA into the base, quantises to `q4_k_m`, and writes a Modelfile**.
So after training you only run one command:

```bash
# in lab/, after finetune_unsloth.py finished (it printed this line for you)
ollama create symposium-coder -f symposium-coder/Modelfile
```

That's it. Verify:

```bash
ollama list                       # symposium-coder should be listed
ollama run symposium-coder "How do I save my work?"
# expect a ```tool_call``` block calling git_save
```

---

## Path B — the manual path (merge → llama.cpp → Modelfile)

Use this if you trained elsewhere, want a different quant, or Unsloth's GGUF
export failed.

**1. Merge the LoRA into the base** (Unsloth, or `peft`):

```python
from unsloth import FastLanguageModel
model, tok = FastLanguageModel.from_pretrained("symposium-coder-lora", load_in_4bit=False)
model.save_pretrained_merged("symposium-coder-merged", tok, save_method="merged_16bit")
```

**2. Convert to GGUF + quantise** with llama.cpp:

```bash
git clone https://github.com/ggerganov/llama.cpp && cd llama.cpp
pip install -r requirements.txt
python convert_hf_to_gguf.py ../symposium-coder-merged \
    --outfile ../symposium-coder.f16.gguf --outtype f16
# quantise to a small, fast q4_k_m
./llama-quantize ../symposium-coder.f16.gguf ../symposium-coder.q4_k_m.gguf q4_k_m
```

**3. Write a Modelfile** (`symposium-coder/Modelfile`). Bake the persona in so it
holds even if a caller forgets the system preamble — keep the SYSTEM text in sync
with [`system_prompt.md`](./system_prompt.md):

```dockerfile
FROM ./symposium-coder.q4_k_m.gguf

# Keep answers focused and let tool_call fences stream cleanly.
PARAMETER temperature 0.5
PARAMETER stop "```\n\n"

SYSTEM """You are Symposium Coder, Visionary Sparks' own fine-tuned coding assistant, running locally inside Symposium Studio. You are agentic and beginner-friendly. When a task needs the workspace, git, or the Explainer panel, emit exactly one fenced ```tool_call``` block: {"name":"<tool>","arguments":{...}}. Tools: read_file, list_files, apply_edit, run_command, git_save, explain, visualize. Always read_file before apply_edit. For plain questions, just answer — no tool call."""
```

**4. Register with Ollama:**

```bash
ollama create symposium-coder -f symposium-coder/Modelfile
```

---

## How it reaches the IDE (no extension change needed)

1. Ollama now serves a model named **`symposium-coder`** on `127.0.0.1:11434`
   (and, if you use the Symposium host proxy, on `127.0.0.1:47475`).
2. `SymposiumProvider` (`id: "symposium"`, `pinnedModel: "symposium-coder"`)
   extends `LocalProvider`, which POSTs to `/v1/chat/completions` on those exact
   endpoints. Its `isAvailable()` returns true the moment the host answers.
3. The provider registry lists it as **"Symposium Coder (fine-tuned)"** in the
   model dropdown / marketplace. Pick it and you're talking to your fine-tune.
4. `LocalProvider`'s `ToolFenceScanner` parses the ```` ```tool_call ```` blocks
   your model was trained to emit into `toolCall` deltas — which is why the
   dataset's fence format has to match byte-for-byte (it does; see
   `dataset/schema.md`).

## Serving it for others (optional)

To let a friend use it, run it behind the Symposium host from
[`../../deploy/`](../../deploy/) (Caddy + systemd, admin/viewer split). The same
`ollama create symposium-coder` on that VM makes it selectable by anyone paired
to the host. Mind the ₹5k kill-switch in `deploy/killswitch/`.

---

## Sanity checks before you ship

- `ollama run symposium-coder "how do I save my work?"` → a `git_save` tool_call.
- `... "explain app.py like I'm 12"` → an `explain` call with `audience:"kid"`.
- `... "what is a list vs a tuple?"` → **prose, no tool call** (restraint works).
- Open Symposium, pick **Symposium Coder (fine-tuned)**, ask it to read a file →
  you should see the diff/approval flow trigger from a real tool call.
