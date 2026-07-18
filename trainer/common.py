"""Torch-free building blocks: tokenizer, presets, datasets, run config.

Everything in this file is plain Python on purpose. The heavy modules
(model.py, train.py) need PyTorch installed, but the *ideas* — how text
becomes numbers, what a "preset" is, where data comes from — don't. Keeping
them here means they can be read, tested, and reused without a GPU or a
multi-gigabyte install.
"""

from __future__ import annotations

import dataclasses
import urllib.request
from pathlib import Path

# ---------------------------------------------------------------------------
# Tokenizer
# ---------------------------------------------------------------------------
#
# Real LLMs use subword tokenizers (BPE) with ~50k-200k entry vocabularies.
# We use a *byte-level* tokenizer instead: every possible byte 0..255 is a
# token. Why:
#   - zero training/fitting step — the vocab is fixed by definition,
#   - it can represent ANY text (emoji, Tamil, code) with no <unk> token,
#   - vocab of 256 keeps the embedding table tiny, which matters when the
#     whole model is under a million parameters.
# The cost: sequences are longer (one token per byte instead of per ~¾ word),
# so the model must learn spelling before it learns words. Watching it do
# exactly that — gibberish → letter pairs → words — is the point of the
# "watch it learn to talk" sample feed.


class ByteTokenizer:
    """Text ↔ token ids where a token is simply one UTF-8 byte."""

    vocab_size = 256

    def encode(self, text: str) -> list[int]:
        return list(text.encode("utf-8"))

    def decode(self, ids: list[int]) -> str:
        # errors="replace": a sampled sequence may split a multi-byte
        # character in half; show � rather than crash mid-training.
        return bytes(max(0, min(255, i)) for i in ids).decode("utf-8", errors="replace")


# ---------------------------------------------------------------------------
# Model presets
# ---------------------------------------------------------------------------
#
# A "preset" pins the architecture knobs. Parameter count is dominated by
# 12 * n_layer * n_embd^2 (the attention + MLP matrices), so these two knobs
# are what separate nano from micro.


@dataclasses.dataclass(frozen=True)
class ModelPreset:
    name: str
    n_layer: int   # how many transformer blocks are stacked
    n_head: int    # attention heads per block (must divide n_embd)
    n_embd: int    # width of the residual stream
    block_size: int  # context window in tokens (= bytes for us)

    @property
    def approx_params(self) -> int:
        """Back-of-envelope parameter count (embeddings tied with the head)."""
        return (
            12 * self.n_layer * self.n_embd**2
            + ByteTokenizer.vocab_size * self.n_embd   # token embedding (tied)
            + self.block_size * self.n_embd            # position embedding
        )


PRESETS: dict[str, ModelPreset] = {
    # ~0.85M params — trains visibly in minutes on CPU.
    "nano": ModelPreset("nano", n_layer=4, n_head=4, n_embd=128, block_size=256),
    # ~2.7M params — noticeably more coherent, wants a GPU to be pleasant.
    "micro": ModelPreset("micro", n_layer=6, n_head=6, n_embd=192, block_size=256),
}


# ---------------------------------------------------------------------------
# Datasets
# ---------------------------------------------------------------------------
#
# A dataset here is just "a text file we can download once and cache".
# tinyshakespeare (~1.1 MB of concatenated Shakespeare) is the classic
# first dataset: small enough to memorise the pipeline, structured enough
# that progress is obvious to the naked eye.

DATA_DIR = Path(__file__).parent / "data"

DATASETS: dict[str, str] = {
    "tinyshakespeare": (
        "https://raw.githubusercontent.com/karpathy/char-rnn/master/data/"
        "tinyshakespeare/input.txt"
    ),
}


def load_dataset(name: str) -> str:
    """Return the dataset's full text, downloading and caching on first use."""
    if name not in DATASETS:
        raise KeyError(f"unknown dataset {name!r}; have {sorted(DATASETS)}")
    path = DATA_DIR / f"{name}.txt"
    if not path.exists():
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(DATASETS[name], timeout=60) as resp:
            text = resp.read().decode("utf-8")
        path.write_text(text, encoding="utf-8")
    return path.read_text(encoding="utf-8")


# ---------------------------------------------------------------------------
# Run configuration & metric events
# ---------------------------------------------------------------------------


@dataclasses.dataclass
class RunConfig:
    """Everything needed to reproduce a training run."""

    dataset: str = "tinyshakespeare"
    preset: str = "nano"
    steps: int = 2000
    lr: float = 3e-4          # AdamW's sweet spot for small transformers
    batch_size: int = 32
    device: str = "auto"      # "auto" → cuda if available, else cpu
    sample_interval: int = 100  # generate a sample + checkpoint every N steps
    sample_length: int = 200    # bytes per sample generation
    seed: int = 1337

    def validate(self) -> None:
        if self.preset not in PRESETS:
            raise ValueError(f"unknown preset {self.preset!r}; have {sorted(PRESETS)}")
        if self.dataset not in DATASETS:
            raise ValueError(f"unknown dataset {self.dataset!r}; have {sorted(DATASETS)}")
        if self.steps <= 0 or self.batch_size <= 0 or self.lr <= 0:
            raise ValueError("steps, batch_size and lr must all be positive")

    @classmethod
    def from_dict(cls, d: dict) -> "RunConfig":
        allowed = {f.name for f in dataclasses.fields(cls)}
        unknown = set(d) - allowed
        if unknown:
            raise ValueError(f"unknown config keys: {sorted(unknown)}")
        cfg = cls(**d)
        cfg.validate()
        return cfg


@dataclasses.dataclass
class MetricEvent:
    """One event on the run's metric stream (sent to the app as JSON).

    kind is one of:
      "metric" — step/loss/tok_per_sec/lr for the live loss curve,
      "sample" — a generation from the current weights ("watch it learn"),
      "status" — lifecycle changes: running / stopped / finished / error.
    """

    kind: str
    step: int
    loss: float | None = None
    tok_per_sec: float | None = None
    lr: float | None = None
    text: str | None = None
    status: str | None = None

    def to_dict(self) -> dict:
        return {k: v for k, v in dataclasses.asdict(self).items() if v is not None}
