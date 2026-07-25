/**
 * The event shapes the Symposium `trainer/` service streams over
 * `ws://<rig>/runs/latest/metrics`. One JSON object per frame, tagged by
 * `kind`. Fields are snake_case (Python side) and mostly optional — the server
 * omits any it can't fill (e.g. GPU stats on a CPU run).
 */
export interface TrainerEvent {
  kind: "metric" | "sample" | "status";
  step: number;
  // kind === "metric"
  loss?: number;
  tok_per_sec?: number;
  lr?: number;
  vram_used_mb?: number;
  vram_total_mb?: number;
  gpu_temp_c?: number;
  // kind === "sample"
  text?: string;
  // kind === "status"
  status?: string;
}

/** The flat frame the Engine Tracker webview renders (camelCase). */
export interface MetricFrame {
  step?: number;
  loss?: number;
  tokPerSec?: number;
  vramUsedMb?: number;
  vramTotalMb?: number;
  gpuTempC?: number;
}

export function parseEvent(raw: string): TrainerEvent | undefined {
  try {
    const j = JSON.parse(raw);
    if (j && typeof j === "object" && typeof j.kind === "string") return j as TrainerEvent;
  } catch {
    /* ignore non-JSON frames */
  }
  return undefined;
}

/** Translate a trainer `kind:"metric"` event into the webview's flat frame. */
export function metricToFrame(ev: TrainerEvent): MetricFrame {
  return {
    step: ev.step,
    loss: ev.loss,
    tokPerSec: ev.tok_per_sec,
    vramUsedMb: ev.vram_used_mb,
    vramTotalMb: ev.vram_total_mb,
    gpuTempC: ev.gpu_temp_c
  };
}
