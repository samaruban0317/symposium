# Dataset schema — Symposium agent fine-tune

Same format the existing lab trainer eats: **one JSON object per line (JSONL)**,
each with a `"messages"` array of chat turns. This is exactly what
[`../../finetune_unsloth.py`](../../finetune_unsloth.py) reads
(`load_dataset("json", ...)` → `apply_chat_template(example["messages"])`), so the
seed slots straight into the existing pipeline — no new loader.

## One line = one conversation

```jsonc
{"messages": [
  {"role": "system",    "content": "<the canonical Symposium Coder prompt>"},
  {"role": "user",      "content": "<what the learner asked>"},
  {"role": "assistant", "content": "<prose and/or a ```tool_call``` fence>"},
  {"role": "tool",      "content": "<result the IDE fed back>"},
  {"role": "assistant", "content": "<final answer / next step>"}
]}
```

### Roles (from `ide/extension/src/ai/types.ts`)

| Role | Meaning here |
|---|---|
| `system` | The Symposium Coder prompt. **Every** example starts with it (see `system_prompt.md`). Kept identical across lines so the model over-learns the persona + protocol. |
| `user` | The learner's message. |
| `assistant` | The model's turn. Either plain prose (Q&A) **or** prose + exactly one fenced ` ```tool_call ` block, matching `local.ts`'s scanner. |
| `tool` | A tool *result* fed back by the IDE. In runtime `types.ts` this carries `toolCallId`/`name`; for **training** we flatten it to plain `content` because `local.ts` collapses `tool` turns into user context on the wire anyway. Keeping training and inference identical avoids a train/serve skew. |

## The tool-call block (must match `local.ts` byte-for-byte)

Inside an assistant turn, a tool call is **one** fenced block:

````
```tool_call
{"name":"read_file","arguments":{"path":"src/app.py"}}
```
````

- Opener is literally ```` ```tool_call ````, closer is ```` ``` ````
  (`ToolFenceScanner.OPEN` / `.CLOSE`).
- The body is a single JSON object with `name` (string) and `arguments` (object).
- `arguments` keys/enums must match `TOOL_SPECS` in
  [`../../../ide/extension/src/ai/tools.ts`](../../../ide/extension/src/ai/tools.ts).
- Nothing follows the closing fence in that assistant turn.

## Example categories (what the seed covers)

The seed (`seed.jsonl`) is deliberately varied so the model learns *routing*, not
one canned move:

1. **Single tool call** — read / list / git_save / explain / visualize.
2. **read → apply_edit** two-step (the "read before write" habit).
3. **run_command** for install / test / build.
4. **Multi-turn with a `tool` result** then a final plain-language wrap-up.
5. **Plain Q&A, NO tool** — concept questions + tiny snippets (teaches restraint).
6. **Beginner intent → right tool** — "save my work" → git_save, "explain like
   I'm 12" → explain kid, "draw how these connect" → visualize flowchart.

## Conventions

- **UTF-8, one object per line, no trailing blank line issues** — `build_dataset.py`
  validates this and will refuse malformed lines.
- Keep the `system` content **identical** on every line (copy from
  `system_prompt.md`). `build_dataset.py` can inject it for you if a seed line
  omits it (`--inject-system`), so seed lines may drop `system` to stay readable.
- Aim for **short** assistant turns. This is a small model; concise targets train
  better and match the "concise, beginner-friendly" persona.
- Target length ≤ `max_seq` (4096 in `train_config.yaml`). The builder warns on
  over-long lines.
