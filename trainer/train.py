"""The training loop — usable by the server and standalone.

Standalone:  python -m trainer.train --preset nano --dataset tinyshakespeare --steps 500

Training a language model is a small loop repeated many times:
  1. grab a random batch of text windows,
  2. ask the model to predict every next byte in them,
  3. measure how wrong it was (cross-entropy loss),
  4. nudge every parameter downhill (AdamW step).
Everything else in this file is bookkeeping around those four lines:
device pick, checkpoints, metric callbacks, sampling "what does it sound
like right now" as it learns.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Callable

import torch

from .common import ByteTokenizer, MetricEvent, PRESETS, RunConfig, load_dataset
from .model import TinyGPT

RUNS_DIR = Path(__file__).parent / "runs"

# A callback receives every MetricEvent; the server forwards them to
# WebSockets, the CLI prints them. Same loop, two frontends.
MetricCallback = Callable[[MetricEvent], None]


def pick_device(requested: str) -> str:
    if requested != "auto":
        return requested
    return "cuda" if torch.cuda.is_available() else "cpu"


# Lazily-initialised NVML handle for GPU temperature. torch exposes VRAM but
# not temperature, so we reach for pynvml if it happens to be installed. None
# means "not available" — we just skip the temp field. Sentinel False = "not
# tried yet"; None = "tried, unavailable"; a handle = "ready".
_nvml_handle: object | None | bool = False


def gpu_stats(device: str) -> dict:
    """Best-effort VRAM (via torch) + temperature (via pynvml if present) for a
    CUDA device. Returns only the keys it can fill, so a CPU run yields {}."""
    global _nvml_handle
    if not device.startswith("cuda") or not torch.cuda.is_available():
        return {}
    out: dict = {}
    try:
        free, total = torch.cuda.mem_get_info()
        out["vram_used_mb"] = int((total - free) / (1024 * 1024))
        out["vram_total_mb"] = int(total / (1024 * 1024))
    except Exception:
        pass
    if _nvml_handle is False:  # first call — try to bring NVML up once
        try:
            import pynvml  # type: ignore

            pynvml.nvmlInit()
            _nvml_handle = pynvml.nvmlDeviceGetHandleByIndex(
                torch.cuda.current_device()
            )
        except Exception:
            _nvml_handle = None
    if _nvml_handle not in (False, None):
        try:
            import pynvml  # type: ignore

            out["gpu_temp_c"] = int(
                pynvml.nvmlDeviceGetTemperature(
                    _nvml_handle, pynvml.NVML_TEMPERATURE_GPU
                )
            )
        except Exception:
            pass
    return out


class Trainer:
    """Owns one training run: model, optimizer, data, checkpoints."""

    def __init__(self, run_id: str, cfg: RunConfig, on_event: MetricCallback):
        cfg.validate()
        self.run_id = run_id
        self.cfg = cfg
        self.on_event = on_event
        self.should_stop = False  # flipped by the server's /stop endpoint
        self.device = pick_device(cfg.device)
        self.tokenizer = ByteTokenizer()
        self.preset = PRESETS[cfg.preset]

        torch.manual_seed(cfg.seed)
        self.model = TinyGPT(self.preset).to(self.device)

        # The whole dataset lives in memory as one long tensor of bytes;
        # "a batch" is just batch_size random windows sliced out of it.
        text = load_dataset(cfg.dataset)
        self.data = torch.tensor(self.tokenizer.encode(text), dtype=torch.long)

        # AdamW is the default optimizer for transformers: per-parameter
        # adaptive step sizes + correctly-decoupled weight decay.
        self.opt = torch.optim.AdamW(self.model.parameters(), lr=cfg.lr)

        self.run_dir = RUNS_DIR / run_id
        self.run_dir.mkdir(parents=True, exist_ok=True)
        (self.run_dir / "config.json").write_text(json.dumps(cfg.__dict__, indent=2))

    def _batch(self) -> tuple[torch.Tensor, torch.Tensor]:
        cfg, block = self.cfg, self.preset.block_size
        ix = torch.randint(len(self.data) - block - 1, (cfg.batch_size,))
        x = torch.stack([self.data[i : i + block] for i in ix])
        # Targets are inputs shifted one byte left: at every position the
        # model learns "given everything so far, what byte comes next?"
        y = torch.stack([self.data[i + 1 : i + block + 1] for i in ix])
        return x.to(self.device), y.to(self.device)

    def _sample(self) -> str:
        # Seed generation with a newline byte and let it talk.
        start = torch.tensor([[10]], dtype=torch.long, device=self.device)
        out = self.model.generate(start, self.cfg.sample_length)
        self.model.train()
        return self.tokenizer.decode(out[0].tolist())

    def save_checkpoint(self) -> Path:
        path = self.run_dir / "ckpt.pt"
        torch.save(
            {"preset": self.cfg.preset, "model": self.model.state_dict()}, path
        )
        return path

    def train(self) -> None:
        cfg = self.cfg
        self.on_event(MetricEvent(kind="status", step=0, status="running"))
        self.model.train()
        t0 = time.time()
        tokens_seen = 0
        try:
            for step in range(1, cfg.steps + 1):
                if self.should_stop:
                    self.save_checkpoint()
                    self.on_event(MetricEvent(kind="status", step=step, status="stopped"))
                    return
                x, y = self._batch()
                _, loss = self.model(x, y)
                self.opt.zero_grad(set_to_none=True)
                loss.backward()
                # Clip gradients so one weird batch can't fling the weights.
                torch.nn.utils.clip_grad_norm_(self.model.parameters(), 1.0)
                self.opt.step()

                tokens_seen += x.numel()
                elapsed = time.time() - t0
                self.on_event(
                    MetricEvent(
                        kind="metric",
                        step=step,
                        loss=round(loss.item(), 4),
                        tok_per_sec=round(tokens_seen / elapsed, 1) if elapsed > 0 else 0.0,
                        lr=cfg.lr,
                        **gpu_stats(self.device),
                    )
                )
                if step % cfg.sample_interval == 0 or step == cfg.steps:
                    self.save_checkpoint()
                    self.on_event(
                        MetricEvent(kind="sample", step=step, text=self._sample())
                    )
            self.on_event(MetricEvent(kind="status", step=cfg.steps, status="finished"))
        except Exception as e:  # surface crashes on the metric stream too
            self.on_event(MetricEvent(kind="status", step=-1, status=f"error: {e}"))
            raise


def generate_from_checkpoint(
    run_dir: Path, prompt: str, max_new_tokens: int = 200, temperature: float = 0.8
) -> str:
    """Chat with whatever the run has learned so far (or finished with)."""
    ckpt_path = run_dir / "ckpt.pt"
    if not ckpt_path.exists():
        raise FileNotFoundError("no checkpoint yet — wait for the first sample_interval")
    ckpt = torch.load(ckpt_path, map_location="cpu")
    model = TinyGPT(PRESETS[ckpt["preset"]])
    model.load_state_dict(ckpt["model"])
    tok = ByteTokenizer()
    ids = tok.encode(prompt) or [10]
    idx = torch.tensor([ids], dtype=torch.long)
    out = model.generate(idx, max_new_tokens, temperature=temperature)
    return tok.decode(out[0].tolist()[len(ids):])


def main() -> None:
    p = argparse.ArgumentParser(description="Train a tiny GPT from the terminal.")
    p.add_argument("--preset", default="nano", choices=sorted(PRESETS))
    p.add_argument("--dataset", default="tinyshakespeare")
    p.add_argument("--steps", type=int, default=2000)
    p.add_argument("--lr", type=float, default=3e-4)
    p.add_argument("--batch-size", type=int, default=32)
    p.add_argument("--device", default="auto")
    args = p.parse_args()

    cfg = RunConfig(
        dataset=args.dataset,
        preset=args.preset,
        steps=args.steps,
        lr=args.lr,
        batch_size=args.batch_size,
        device=args.device,
    )

    def show(ev: MetricEvent) -> None:
        if ev.kind == "metric" and ev.step % 10 == 0:
            print(f"step {ev.step:>5}  loss {ev.loss:.4f}  {ev.tok_per_sec:,.0f} tok/s")
        elif ev.kind == "sample":
            print(f"\n--- sample @ step {ev.step} ---\n{ev.text}\n---\n")
        elif ev.kind == "status":
            print(f"[{ev.status}]")

    run_id = time.strftime("cli-%Y%m%d-%H%M%S")
    trainer = Trainer(run_id, cfg, show)
    print(
        f"run {run_id}: {cfg.preset} ({trainer.model.num_params():,} params) "
        f"on {trainer.device}, {cfg.steps} steps"
    )
    trainer.train()


if __name__ == "__main__":
    main()
