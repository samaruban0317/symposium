/**
 * Settings + secret access for Symposium Studio's AI layer.
 *
 * Mirrors `rigUrls.ts`: one place resolves configuration so nothing hand-builds
 * a URL or reads a raw setting. API keys live ONLY in VS Code SecretStorage —
 * never settings.json, never logged, never committed.
 */
import * as vscode from "vscode";

const CFG = "symposium";

/** SecretStorage keys, namespaced. Add-key command writes these. */
export const SECRET_KEYS = {
  anthropic: "symposium.key.anthropic",
  gemini: "symposium.key.gemini",
  openai: "symposium.key.openai"
} as const;

export type CloudProviderId = keyof typeof SECRET_KEYS;

function cfg() {
  return vscode.workspace.getConfiguration(CFG);
}

/** Primary local model endpoint (Symposium host proxy), then a fallback (raw Ollama). */
export function localEndpoints(): { primary: string; fallback: string } {
  return {
    primary: cfg().get<string>("ai.local.url", "http://127.0.0.1:47475").replace(/\/+$/, ""),
    fallback: cfg().get<string>("ai.local.fallbackUrl", "http://127.0.0.1:11434").replace(/\/+$/, "")
  };
}

/** 6-digit pairing code for the Symposium host proxy (blank ⇒ open/raw Ollama). */
export function localPairingCode(): string | undefined {
  return cfg().get<string>("ai.local.pairingCode") || undefined;
}

/** Which provider a fresh panel selects by default. */
export function defaultProviderId(): string {
  return cfg().get<string>("ai.defaultProvider", "local");
}

/** Configured model id for a cloud provider (blank ⇒ provider picks a sane default). */
export function cloudModel(id: CloudProviderId): string | undefined {
  return cfg().get<string>(`ai.cloudModel.${id}`) || undefined;
}

/** Read a stored API key. */
export async function getKey(ctx: vscode.ExtensionContext, id: CloudProviderId): Promise<string | undefined> {
  return ctx.secrets.get(SECRET_KEYS[id]);
}

/** Store / clear an API key. */
export async function setKey(ctx: vscode.ExtensionContext, id: CloudProviderId, value: string): Promise<void> {
  if (value) await ctx.secrets.store(SECRET_KEYS[id], value);
  else await ctx.secrets.delete(SECRET_KEYS[id]);
}

/** Collaboration relay/base — where the Supabase-backed roster+credits lives. */
export function collabRelayUrl(): string {
  return cfg().get<string>("collab.relayUrl", "http://127.0.0.1:47475").replace(/\/+$/, "");
}
