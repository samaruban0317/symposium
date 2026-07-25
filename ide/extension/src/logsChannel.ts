import * as vscode from "vscode";
import { RigClient, RigStatus } from "./rigClient";
import { rigEndpoints, rigToken } from "./rigUrls";
import { parseEvent, TrainerEvent } from "./trainerEvents";

/**
 * Tails the rig's live training run into an OutputChannel by connecting to
 * `/runs/latest/metrics`. The trainer streams `kind`-tagged JSON events; we
 * render each as a readable log line — metrics as a compact loss/throughput
 * line, samples as the "watch it learn to talk" text, and status transitions.
 */
export class LogsChannel implements vscode.Disposable {
  private readonly channel: vscode.OutputChannel;
  private client: RigClient | undefined;

  constructor() {
    this.channel = vscode.window.createOutputChannel("Symposium Rig");
  }

  private stamp(msg: string): string {
    const t = new Date().toISOString().slice(11, 19);
    return `[${t}] ${msg}`;
  }

  connect(): void {
    if (this.client) {
      // Already have a client; restart it so a URL/token change is picked up.
      this.client.stop();
    }
    this.channel.show(true);
    this.client = new RigClient({
      url: () => rigEndpoints().latestMetricsWs,
      token: () => rigToken(),
      onStatus: (status: RigStatus, detail?: string) => {
        switch (status) {
          case "connecting":
            this.channel.appendLine(this.stamp(`… connecting${detail ? ` (${detail})` : ""}`));
            break;
          case "live":
            this.channel.appendLine(this.stamp(`● connected to ${detail ?? "rig"}`));
            break;
          case "disconnected":
            this.channel.appendLine(this.stamp("○ disconnected"));
            break;
        }
      },
      onMessage: (data: string) => {
        const ev = parseEvent(data);
        if (ev) this.channel.appendLine(render(ev));
      }
    });
    this.client.start();
  }

  disconnect(): void {
    if (this.client) {
      this.client.stop();
      this.client = undefined;
    } else {
      this.channel.appendLine(this.stamp("○ not connected"));
    }
  }

  dispose(): void {
    this.client?.dispose();
    this.channel.dispose();
  }
}

function render(ev: TrainerEvent): string {
  switch (ev.kind) {
    case "metric": {
      const parts = [`step ${ev.step}`];
      if (typeof ev.loss === "number") parts.push(`loss ${ev.loss.toFixed(4)}`);
      if (typeof ev.tok_per_sec === "number") parts.push(`${ev.tok_per_sec.toFixed(0)} tok/s`);
      if (typeof ev.vram_used_mb === "number" && typeof ev.vram_total_mb === "number") {
        parts.push(`vram ${ev.vram_used_mb}/${ev.vram_total_mb}MB`);
      }
      if (typeof ev.gpu_temp_c === "number") parts.push(`${ev.gpu_temp_c}°C`);
      return parts.join("  ");
    }
    case "sample":
      return `── sample @ step ${ev.step} ──\n${ev.text ?? ""}`;
    case "status":
      return `● status: ${ev.status ?? "?"} (step ${ev.step})`;
    default:
      return JSON.stringify(ev);
  }
}
