import WebSocket from "ws";

export type RigStatus = "disconnected" | "connecting" | "live";

export interface RigClientOptions {
  /** How to obtain the current WebSocket URL (read fresh on each (re)connect so config edits take effect). */
  url: () => string;
  /** Optional bearer token supplier, sent as an Authorization header on the handshake. */
  token?: () => string | undefined;
  /** Called with every text message frame received. */
  onMessage: (data: string) => void;
  /** Called whenever the connection status changes. */
  onStatus?: (status: RigStatus, detail?: string) => void;
  /** Base backoff in ms (default 1000). Grows exponentially, capped at maxBackoffMs. */
  baseBackoffMs?: number;
  /** Max backoff in ms (default 15000). */
  maxBackoffMs?: number;
}

/**
 * A small reconnecting WebSocket wrapper for the extension host.
 * The extension host — never the webview — owns the socket.
 * Auto-reconnects with capped exponential backoff until stop() is called.
 */
export class RigClient {
  private ws: WebSocket | undefined;
  private closedByUser = false;
  private attempt = 0;
  private reconnectTimer: NodeJS.Timeout | undefined;
  private status: RigStatus = "disconnected";

  constructor(private readonly opts: RigClientOptions) {}

  get currentStatus(): RigStatus {
    return this.status;
  }

  start(): void {
    this.closedByUser = false;
    this.connect();
  }

  stop(): void {
    this.closedByUser = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = undefined;
    }
    if (this.ws) {
      // Detach handlers so the close event does not trigger a reconnect.
      this.ws.removeAllListeners();
      try {
        this.ws.close();
      } catch {
        /* ignore */
      }
      this.ws = undefined;
    }
    this.setStatus("disconnected");
  }

  dispose(): void {
    this.stop();
  }

  private setStatus(status: RigStatus, detail?: string): void {
    this.status = status;
    this.opts.onStatus?.(status, detail);
  }

  private connect(): void {
    if (this.closedByUser) {
      return;
    }
    const url = this.opts.url();
    this.setStatus("connecting", url);

    const headers: Record<string, string> = {};
    const token = this.opts.token?.();
    if (token) {
      headers["Authorization"] = `Bearer ${token}`;
    }

    let ws: WebSocket;
    try {
      ws = new WebSocket(url, { headers });
    } catch (err) {
      this.scheduleReconnect(err instanceof Error ? err.message : String(err));
      return;
    }
    this.ws = ws;

    ws.on("open", () => {
      this.attempt = 0;
      this.setStatus("live", url);
    });

    ws.on("message", (data: WebSocket.RawData) => {
      this.opts.onMessage(data.toString());
    });

    ws.on("error", (err: Error) => {
      // 'close' fires after 'error'; let close drive the reconnect.
      this.setStatus("connecting", err.message);
    });

    ws.on("close", () => {
      this.ws = undefined;
      if (!this.closedByUser) {
        this.scheduleReconnect();
      }
    });
  }

  private scheduleReconnect(detail?: string): void {
    if (this.closedByUser) {
      return;
    }
    const base = this.opts.baseBackoffMs ?? 1000;
    const max = this.opts.maxBackoffMs ?? 15000;
    const delay = Math.min(max, base * Math.pow(2, this.attempt));
    this.attempt += 1;
    this.setStatus("connecting", detail ? `${detail} — retrying in ${Math.round(delay / 1000)}s` : undefined);
    this.reconnectTimer = setTimeout(() => this.connect(), delay);
  }
}
