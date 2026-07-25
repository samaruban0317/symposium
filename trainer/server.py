"""Symposium training service — the Flutter app's window into training.

Usage:
    pip install -r trainer/requirements.txt        (from the repo root)
    uvicorn trainer.server:app --port 8765

API (all JSON):
    POST /runs                  start a run
                                body: {"preset":"nano","dataset":"tinyshakespeare",
                                       "steps":2000,"lr":3e-4,"batch_size":32,
                                       "device":"auto"}   (all optional)
                                → {"id": "...", ...status}
    GET  /runs                  list all runs (newest first)
    GET  /runs/latest           the newest run (IDE convenience; 404 if none)
    GET  /runs/{id}             one run's status + latest metrics
    WS   /runs/latest/metrics   live stream for the newest run — the IDE's
                                Engine Tracker uses this so it needn't track ids
    POST /runs/{id}/stop        request a graceful stop (checkpoint is saved)
    WS   /runs/{id}/metrics     live JSON events: {"kind":"metric",...},
                                {"kind":"sample",...}, {"kind":"status",...}
                                Replays history first, so a client connecting
                                late still gets the full loss curve.
    POST /runs/{id}/generate    body: {"prompt":"...", "max_new_tokens":200,
                                "temperature":0.8} → {"text":"..."}
                                Works mid-run: it loads the latest checkpoint,
                                so you can literally chat with a half-trained
                                model.

Design notes for readers:
  - Training runs on a plain background thread. PyTorch releases the GIL
    inside its C++ kernels, so the async server stays responsive.
  - Each run appends MetricEvents to an in-memory list. Appends are atomic
    under the GIL, so WebSocket handlers can read by index without locks:
    they replay 0..n, then poll for new entries. Simple beats clever here.
  - /generate reloads the checkpoint file rather than touching the live
    training model — no shared mutable state between threads.
"""

from __future__ import annotations

import asyncio
import threading
import time
import uuid

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel

from .common import MetricEvent, PRESETS, RunConfig
from .train import RUNS_DIR, Trainer, generate_from_checkpoint

app = FastAPI(title="Symposium trainer")


class Run:
    """Server-side record of one training run."""

    def __init__(self, cfg: RunConfig):
        self.id = uuid.uuid4().hex[:8]
        self.cfg = cfg
        self.created = time.time()
        self.status = "starting"
        self.events: list[MetricEvent] = []  # append-only; see module docstring
        self.trainer: Trainer | None = None
        self.thread: threading.Thread | None = None

    def on_event(self, ev: MetricEvent) -> None:
        if ev.kind == "status" and ev.status:
            self.status = ev.status
        self.events.append(ev)

    def latest_metric(self) -> dict | None:
        for ev in reversed(self.events):
            if ev.kind == "metric":
                return ev.to_dict()
        return None

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "status": self.status,
            "created": self.created,
            "config": self.cfg.__dict__,
            "preset_params": PRESETS[self.cfg.preset].approx_params,
            "latest": self.latest_metric(),
            "events": len(self.events),
        }


RUNS: dict[str, Run] = {}


class GenerateBody(BaseModel):
    prompt: str = ""
    max_new_tokens: int = 200
    temperature: float = 0.8


@app.post("/runs")
def start_run(config: dict | None = None):
    try:
        cfg = RunConfig.from_dict(config or {})
    except (ValueError, TypeError) as e:
        raise HTTPException(status_code=422, detail=str(e))
    run = Run(cfg)
    RUNS[run.id] = run

    def work() -> None:
        try:
            run.trainer = Trainer(run.id, cfg, run.on_event)
            run.trainer.train()
        except Exception as e:
            # Trainer already emitted an error event if the loop crashed;
            # this catches setup failures (bad download, OOM on init...).
            if run.status not in ("finished", "stopped") and not run.status.startswith("error"):
                run.on_event(MetricEvent(kind="status", step=-1, status=f"error: {e}"))

    run.thread = threading.Thread(target=work, name=f"train-{run.id}", daemon=True)
    run.thread.start()
    return run.to_dict()


@app.get("/runs")
def list_runs():
    return [r.to_dict() for r in sorted(RUNS.values(), key=lambda r: -r.created)]


def _get(run_id: str) -> Run:
    run = RUNS.get(run_id)
    if run is None:
        raise HTTPException(status_code=404, detail=f"no run {run_id!r}")
    return run


def _latest_run() -> Run | None:
    """The most recently created run, or None if nothing has been started.
    Lets the IDE watch "the current run" without tracking ids."""
    if not RUNS:
        return None
    return max(RUNS.values(), key=lambda r: r.created)


@app.get("/runs/latest")
def get_latest_run():
    run = _latest_run()
    if run is None:
        raise HTTPException(status_code=404, detail="no runs yet")
    return run.to_dict()


@app.get("/runs/{run_id}")
def get_run(run_id: str):
    return _get(run_id).to_dict()


@app.post("/runs/{run_id}/stop")
def stop_run(run_id: str):
    run = _get(run_id)
    if run.trainer is not None:
        run.trainer.should_stop = True
    return {"id": run.id, "status": "stop requested"}


async def _stream_events(ws: WebSocket, run: Run) -> None:
    """Replay a run's whole event history, then poll for new events, sending
    each as JSON. Returns when the run reaches a terminal state or the socket
    drops. Shared by the per-id and 'latest' metric sockets."""
    sent = 0
    try:
        while True:
            # Replay anything new since our last look (or all of history on
            # first iteration — that's what redraws the loss curve after a
            # reconnect).
            while sent < len(run.events):
                await ws.send_json(run.events[sent].to_dict())
                sent += 1
            terminal = run.status in ("finished", "stopped") or run.status.startswith("error")
            if terminal and sent == len(run.events):
                break
            await asyncio.sleep(0.2)
    except WebSocketDisconnect:
        return
    await ws.close()


@app.websocket("/runs/latest/metrics")
async def latest_metrics_ws(ws: WebSocket):
    run = _latest_run()
    await ws.accept()
    if run is None:
        await ws.close(code=4404, reason="no runs yet")
        return
    await _stream_events(ws, run)


@app.websocket("/runs/{run_id}/metrics")
async def metrics_ws(ws: WebSocket, run_id: str):
    run = RUNS.get(run_id)
    await ws.accept()
    if run is None:
        await ws.close(code=4404, reason=f"no run {run_id!r}")
        return
    await _stream_events(ws, run)


@app.post("/runs/{run_id}/generate")
def generate(run_id: str, body: GenerateBody):
    run = _get(run_id)
    try:
        text = generate_from_checkpoint(
            RUNS_DIR / run.id,
            body.prompt,
            max_new_tokens=body.max_new_tokens,
            temperature=body.temperature,
        )
    except FileNotFoundError as e:
        raise HTTPException(status_code=409, detail=str(e))
    return {"id": run.id, "text": text}
