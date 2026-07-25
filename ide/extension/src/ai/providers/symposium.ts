/**
 * SymposiumProvider — our OWN fine-tuned coding model, served through the same
 * local host proxy as any other local model. It is a thin `LocalProvider`
 * pinned to a fixed model name plus a Symposium system preamble, so it inherits
 * the entire local transport (SSE streaming, tok/s, tool-fence fallback) and
 * only differs in identity + persona.
 *
 * Keyless (needsKey=false) — it runs on the user's Symposium host.
 */
import { LocalProvider } from "./local";

/** The model id the Symposium host serves our fine-tune under. */
const SYMPOSIUM_MODEL = "symposium-coder";

/** Persona/system preamble injected ahead of every Symposium turn. */
const SYMPOSIUM_PREAMBLE = [
  "You are Symposium Coder, Visionary Sparks' own fine-tuned coding assistant",
  "running locally inside Symposium Studio. You are agentic: when tools are",
  "offered, prefer reading files before editing and propose edits as full-file",
  "replacements. Be concise, correct, and beginner-friendly."
].join(" ");

export class SymposiumProvider extends LocalProvider {
  constructor() {
    super({
      id: "symposium",
      label: "Symposium Coder (fine-tuned)",
      pinnedModel: SYMPOSIUM_MODEL,
      preamble: SYMPOSIUM_PREAMBLE
    });
  }
}
