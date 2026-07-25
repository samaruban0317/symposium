/**
 * Line-based Server-Sent-Events parsing over a `fetch` Response body.
 *
 * Every streaming provider (local host, OpenAI, Anthropic, Gemini) speaks SSE:
 * a stream of `data: <payload>` lines separated by blank lines, ending on a
 * `data: [DONE]` sentinel (OpenAI-style) or simply EOF. This helper owns the
 * chunk-decoding + buffering so each provider only deals with parsed payloads.
 *
 * The extension host owns all network I/O (mirrors `RigClient`); this runs in
 * the host, never a webview.
 */

/** The `data:` payload of one SSE line, minus the `data: ` prefix. */
export type SsePayload = string;

/**
 * Iterate the `data:` payloads of an SSE `Response`, honoring an AbortSignal.
 *
 * Uses the WHATWG stream reader (Node 18's global `fetch`). Non-`data:` lines
 * (comments `:`, `event:`, `id:`) are ignored — providers only need `data:`.
 * The `[DONE]` sentinel is NOT yielded; iteration simply ends after it.
 */
export async function* readSse(
  res: Response,
  signal?: AbortSignal
): AsyncGenerator<SsePayload, void, void> {
  if (!res.body) {
    return;
  }
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  try {
    while (true) {
      if (signal?.aborted) {
        return;
      }
      const { value, done } = await reader.read();
      if (done) {
        break;
      }
      buffer += decoder.decode(value, { stream: true });

      // SSE frames are newline-delimited; process every complete line and keep
      // the trailing partial in the buffer for the next chunk.
      let nl: number;
      while ((nl = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, nl).replace(/\r$/, "");
        buffer = buffer.slice(nl + 1);
        const payload = extractData(line);
        if (payload === undefined) {
          continue;
        }
        if (payload === "[DONE]") {
          return;
        }
        yield payload;
      }
    }
    // Flush any final line without a trailing newline (EOF-terminated stream).
    const tail = extractData(buffer.replace(/\r$/, ""));
    if (tail !== undefined && tail !== "[DONE]") {
      yield tail;
    }
  } finally {
    try {
      await reader.cancel();
    } catch {
      /* ignore — stream may already be closed */
    }
  }
}

/** Return the `data:` payload of one line, or `undefined` for non-data lines. */
function extractData(line: string): string | undefined {
  if (!line.startsWith("data:")) {
    return undefined;
  }
  // Spec allows an optional single space after the colon.
  return line.slice(line[5] === " " ? 6 : 5);
}

/** Safe JSON parse for one SSE payload; returns undefined on malformed JSON. */
export function tryParse<T = unknown>(payload: string): T | undefined {
  try {
    return JSON.parse(payload) as T;
  } catch {
    return undefined;
  }
}
