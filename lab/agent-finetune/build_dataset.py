#!/usr/bin/env python3
"""Build the Symposium agent training file from the hand-written seed.

Turns ``dataset/seed.jsonl`` into the exact ``{"messages": [...]}`` chat JSONL
that the lab's existing trainer (``lab/finetune_unsloth.py``) already consumes —
so this is dataset prep ONLY, not a new pipeline. The trainer does
``load_dataset("json", ...)`` then ``apply_chat_template(example["messages"])``;
we produce lines shaped exactly for that.

Pure standard library (json / argparse / pathlib) — no heavy deps. Runs on any
box, no GPU, in the lab's Python 3.11 venv (or any 3.8+).

Typical use (from the ``lab/`` directory):

    python agent-finetune/build_dataset.py \
        --seed agent-finetune/dataset/seed.jsonl \
        --out  data/symposium_agent.jsonl

What it does, in order:
  1. Reads the seed JSONL line by line.
  2. For any line whose first message isn't a ``system`` turn, injects the
     canonical Symposium system prompt (kept in ``system_prompt.md``) so every
     training conversation starts identically — that's what over-teaches the
     persona + tool protocol. Disable with ``--no-inject-system``.
  3. Validates each conversation: role order, that assistant ``tool_call`` fences
     are well-formed JSON with a ``name``, and a rough token-length check against
     ``--max-seq``. Bad lines are reported and skipped (or fail with --strict).
  4. Writes the cleaned lines to ``--out`` (one JSON object per line, UTF-8).

The system prompt is derived from ``system_prompt.md`` but kept as a constant
here too, so the builder has no runtime dependency on that markdown file.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# --- Canonical system prompt -------------------------------------------------
# Mirrors lab/agent-finetune/system_prompt.md and the runtime preamble in
# ide/extension/src/ai/providers/symposium.ts + local.ts's toolFallbackPrompt.
# Keep these three in sync when the tool set changes.
SYSTEM_PROMPT = (
    "You are Symposium Coder, Visionary Sparks' own fine-tuned coding assistant, "
    "running locally inside Symposium Studio, a VS Code-based IDE for young "
    "learners. You are agentic and beginner-friendly: correct, concise, and never "
    "condescending.\n\n"
    "You can use tools. When a task needs to touch the workspace, git, or the "
    "Explainer panel, call a tool by outputting EXACTLY one fenced block:\n"
    "```tool_call\n"
    '{"name":"<tool>","arguments":{ ... }}\n'
    "```\n"
    "Emit nothing after the closing fence in that turn. The IDE runs the tool and "
    "sends back a result. apply_edit and run_command are side-effecting and the "
    "user approves them in the IDE; just propose the call. Always read_file before "
    "you apply_edit, and propose edits as full-file replacements.\n\n"
    "Available tools:\n"
    "- read_file {path}: read a workspace file (do this before editing).\n"
    "- list_files {dir}: list files under a workspace-relative dir (\"\" = root).\n"
    "- apply_edit {path, content, why?}: propose a full-file replacement; user "
    "approves a diff.\n"
    "- run_command {command, why?}: run a shell command (install/build/test); "
    "user approves.\n"
    "- git_save {message}: beginner-friendly Save & Share (stage all + commit). "
    "This answers \"how do I save/back up/share my work\".\n"
    "- explain {path?, audience?}: explain a file/selection in plain language at "
    "kid | student | engineer level.\n"
    "- visualize {target, kind}: Mermaid diagram (flowchart | sequence | class) "
    "of how code/files relate; target is a file path or \"workspace\".\n\n"
    "For plain questions (concepts, small snippets, debugging advice) just answer "
    "in prose — do NOT emit a tool call when no workspace action is needed."
)

VALID_ROLES = {"system", "user", "assistant", "tool"}

# The tool names the model is allowed to emit — must match TOOL_SPECS in
# ide/extension/src/ai/tools.ts. Used only to warn on typos in the seed.
KNOWN_TOOLS = {
    "read_file",
    "list_files",
    "apply_edit",
    "run_command",
    "git_save",
    "explain",
    "visualize",
}

# Matches the ```tool_call ... ``` fence exactly as local.ts's scanner keys on it.
TOOL_FENCE_RE = re.compile(r"```tool_call\s*(.*?)```", re.DOTALL)


def approx_tokens(text: str) -> int:
    """Very rough token estimate (~4 chars/token). Good enough for a length gate."""
    return max(1, len(text) // 4)


def validate_messages(messages: list, max_seq: int) -> list[str]:
    """Return a list of problem strings for one conversation ([] == clean)."""
    problems: list[str] = []
    if not isinstance(messages, list) or not messages:
        return ["'messages' is missing or empty"]

    total_chars = 0
    prev_role = None
    for i, m in enumerate(messages):
        if not isinstance(m, dict):
            problems.append(f"message #{i} is not an object")
            continue
        role = m.get("role")
        content = m.get("content", "")
        if role not in VALID_ROLES:
            problems.append(f"message #{i} has bad role {role!r}")
        if not isinstance(content, str):
            problems.append(f"message #{i} content is not a string")
            content = ""
        total_chars += len(content)

        # A 'tool' turn should follow an assistant turn (it answers a tool call).
        if role == "tool" and prev_role != "assistant":
            problems.append(f"message #{i} is a tool result not preceded by assistant")

        # Validate any tool_call fences inside assistant turns.
        if role == "assistant":
            for raw in TOOL_FENCE_RE.findall(content):
                try:
                    obj = json.loads(raw.strip())
                except json.JSONDecodeError as e:
                    problems.append(f"message #{i} tool_call is invalid JSON: {e}")
                    continue
                name = obj.get("name")
                if not name:
                    problems.append(f"message #{i} tool_call has no 'name'")
                elif name not in KNOWN_TOOLS:
                    problems.append(f"message #{i} tool_call uses unknown tool {name!r}")
                if "arguments" in obj and not isinstance(obj["arguments"], dict):
                    problems.append(f"message #{i} tool_call 'arguments' is not an object")
        prev_role = role

    if approx_tokens_total := approx_tokens("x" * total_chars):
        if approx_tokens_total > max_seq:
            problems.append(
                f"conversation ~{approx_tokens_total} tokens exceeds max_seq={max_seq}"
            )
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description="Build the Symposium agent training JSONL")
    here = Path(__file__).resolve().parent
    ap.add_argument(
        "--seed",
        default=str(here / "dataset" / "seed.jsonl"),
        help="hand-written seed JSONL (default: dataset/seed.jsonl)",
    )
    ap.add_argument(
        "--out",
        default=str(here.parent / "data" / "symposium_agent.jsonl"),
        help="output training JSONL (default: lab/data/symposium_agent.jsonl)",
    )
    ap.add_argument(
        "--no-inject-system",
        dest="inject_system",
        action="store_false",
        help="do NOT prepend the canonical system prompt to lines lacking one",
    )
    ap.add_argument("--max-seq", type=int, default=4096, help="length gate (train_config.yaml)")
    ap.add_argument("--strict", action="store_true", help="fail on any invalid line instead of skipping")
    args = ap.parse_args()

    seed_path = Path(args.seed)
    out_path = Path(args.out)
    if not seed_path.exists():
        print(f"error: seed not found: {seed_path}", file=sys.stderr)
        return 2

    out_path.parent.mkdir(parents=True, exist_ok=True)

    kept = 0
    skipped = 0
    with seed_path.open("r", encoding="utf-8") as fin, out_path.open("w", encoding="utf-8", newline="\n") as fout:
        for lineno, line in enumerate(fin, 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as e:
                msg = f"line {lineno}: not valid JSON: {e}"
                if args.strict:
                    print(f"error: {msg}", file=sys.stderr)
                    return 1
                print(f"skip: {msg}", file=sys.stderr)
                skipped += 1
                continue

            messages = obj.get("messages")
            if not isinstance(messages, list):
                print(f"skip: line {lineno}: no 'messages' array", file=sys.stderr)
                skipped += 1
                continue

            # Inject the canonical system prompt if the line doesn't start with one.
            if args.inject_system and not (messages and messages[0].get("role") == "system"):
                messages = [{"role": "system", "content": SYSTEM_PROMPT}, *messages]

            problems = validate_messages(messages, args.max_seq)
            if problems:
                head = f"line {lineno}: " + "; ".join(problems)
                if args.strict:
                    print(f"error: {head}", file=sys.stderr)
                    return 1
                print(f"skip: {head}", file=sys.stderr)
                skipped += 1
                continue

            fout.write(json.dumps({"messages": messages}, ensure_ascii=False) + "\n")
            kept += 1

    print(f"wrote {kept} conversations -> {out_path}  ({skipped} skipped)")
    if kept == 0:
        print("warning: no conversations written", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
