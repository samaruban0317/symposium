/**
 * `Symposium: Add AI Model Key…` — lets a user connect their OWN cloud model
 * (Claude / Gemini / OpenAI) by pasting an API key. The key is stored in VS
 * Code SecretStorage only (never settings.json, never logged, never committed);
 * once stored, that provider appears in the AI Coder dropdown. Users pay their
 * own provider — no key ⇒ the provider stays hidden and only local models run.
 */
import * as vscode from "vscode";
import { setKey, getKey, type CloudProviderId } from "./config";

interface Choice {
  id: CloudProviderId;
  label: string;
  detail: string;
}

const CHOICES: Choice[] = [
  { id: "anthropic", label: "Claude (Anthropic)", detail: "console.anthropic.com → API keys" },
  { id: "gemini", label: "Gemini (Google)", detail: "aistudio.google.com → Get API key" },
  { id: "openai", label: "ChatGPT (OpenAI)", detail: "platform.openai.com → API keys" }
];

export async function addModelKey(ctx: vscode.ExtensionContext): Promise<void> {
  const items = await Promise.all(
    CHOICES.map(async (c) => ({
      ...c,
      description: (await getKey(ctx, c.id)) ? "key saved ✓ — pick to replace or clear" : "no key yet"
    }))
  );

  const pick = await vscode.window.showQuickPick(items, {
    title: "Connect an AI model",
    placeHolder: "Which model provider's key do you want to add?"
  });
  if (!pick) return;

  const hasKey = Boolean(await getKey(ctx, pick.id));
  const value = await vscode.window.showInputBox({
    title: `${pick.label} API key`,
    prompt: `Paste your ${pick.label} API key. It is stored securely on this device only.${
      hasKey ? " Leave blank to CLEAR the saved key." : ""
    }`,
    password: true,
    ignoreFocusOut: true,
    placeHolder: pick.detail
  });
  if (value === undefined) return; // cancelled

  const trimmed = value.trim();
  await setKey(ctx, pick.id, trimmed);
  if (trimmed) {
    vscode.window.showInformationMessage(`${pick.label} connected — it's now available in the AI Coder.`);
  } else if (hasKey) {
    vscode.window.showInformationMessage(`${pick.label} key cleared.`);
  }
}
