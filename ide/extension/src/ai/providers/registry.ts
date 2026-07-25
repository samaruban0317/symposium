/**
 * Provider registry — the one place that knows about every brain.
 *
 * `getProviders(ctx)` builds the five providers (local, symposium, anthropic,
 * gemini, openai). `providerInfos(ctx)` returns the UI-facing list, marking
 * each provider `available` — local/symposium if the host is reachable, cloud
 * providers only if a key is stored (so a keyless user never sees a dead
 * option in the dropdown).
 */
import type * as vscode from "vscode";
import type { AiProvider, ProviderInfo } from "../types";
import { LocalProvider } from "./local";
import { SymposiumProvider } from "./symposium";
import { AnthropicProvider } from "./anthropic";
import { GeminiProvider } from "./gemini";
import { OpenAiProvider } from "./openai";

/** Build the ordered provider list. Local is first ⇒ the natural default. */
export function getProviders(ctx: vscode.ExtensionContext): AiProvider[] {
  return [
    new LocalProvider(),
    new SymposiumProvider(),
    new AnthropicProvider(ctx),
    new GeminiProvider(ctx),
    new OpenAiProvider(ctx)
  ];
}

/** Look up one provider by id (falls back to the local default). */
export function getProvider(ctx: vscode.ExtensionContext, id: string): AiProvider {
  const list = getProviders(ctx);
  return list.find((p) => p.id === id) ?? list[0];
}

/** UI-facing list with a live `available` flag per provider. */
export async function providerInfos(ctx: vscode.ExtensionContext): Promise<ProviderInfo[]> {
  const providers = getProviders(ctx);
  // Availability probes run in parallel (each is a cheap key read or host ping).
  return Promise.all(
    providers.map(async (p): Promise<ProviderInfo> => ({
      id: p.id,
      label: p.label,
      needsKey: p.needsKey,
      available: await safeAvailable(p)
    }))
  );
}

/** Never let one provider's probe error break the whole dropdown. */
async function safeAvailable(p: AiProvider): Promise<boolean> {
  try {
    return await p.isAvailable();
  } catch {
    return false;
  }
}
