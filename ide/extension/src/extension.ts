import * as vscode from "vscode";
import { EngineTrackerViewProvider } from "./engineTrackerView";
import { LogsChannel } from "./logsChannel";
import { startRun } from "./train";

// Studio: AI core + panels.
import { createStudioSession } from "./ai/agent/loop";
import { VizToolRunner } from "./ai/agent/vizRunner";
import { addModelKey } from "./ai/addKey";
import { CoderViewProvider } from "./ai/panels/coderView";
import { ExplainViewProvider } from "./ai/panels/explainView";
import { CollabViewProvider } from "./ai/panels/collabView";
import { AdminViewProvider } from "./ai/panels/adminView";
import { MarketplaceViewProvider } from "./ai/panels/marketplaceView";

// Studio: git + collaboration + gpu.
import { GitService } from "./git/gitService";
import { GitToolRunner } from "./git/gitToolRunner";
import { RelayClient } from "./collab/relayClient";
import { connectGpu } from "./gpu/connectGpu";

const CFG = "symposium";

export function activate(context: vscode.ExtensionContext): void {
  const setActive = (active: boolean) =>
    vscode.commands.executeCommand("setContext", "symposium.active", active);

  // ---- Shared services ------------------------------------------------------
  const session = createStudioSession(context);
  const git = new GitService();
  const relay = new RelayClient();

  // Who authors merge requests / commits — best-effort identity.
  const author = (): string =>
    vscode.workspace.getConfiguration(CFG).get<string>("collab.email") || "me";

  // ---- Panels (webview views under the Symposium activity-bar container) -----
  const coder = new CoderViewProvider(context.extensionUri, session);
  const explain = new ExplainViewProvider(context.extensionUri, session);
  const collab = new CollabViewProvider(context.extensionUri, relay, git);
  const admin = new AdminViewProvider(context.extensionUri, relay, () => collab.currentRoomId());
  const marketplace = new MarketplaceViewProvider(context.extensionUri);
  const engineTracker = new EngineTrackerViewProvider(context.extensionUri);

  const register = (viewType: string, provider: vscode.WebviewViewProvider, retain = true) =>
    vscode.window.registerWebviewViewProvider(viewType, provider, {
      webviewOptions: { retainContextWhenHidden: retain }
    });

  context.subscriptions.push(
    register(CoderViewProvider.viewType, coder),
    register(ExplainViewProvider.viewType, explain),
    register(CollabViewProvider.viewType, collab),
    register(AdminViewProvider.viewType, admin),
    register(MarketplaceViewProvider.viewType, marketplace),
    register(EngineTrackerViewProvider.viewType, engineTracker),
    coder,
    explain,
    collab,
    admin,
    marketplace,
    engineTracker
  );

  // ---- Tool runners the agent can call --------------------------------------
  // EditRunner (read/edit/run) is registered by the session itself. Here we add
  // the feature-owned runners: git (Save & Share / merge requests) and viz
  // (explain / visualize). git_save is NOT claimed by EditRunner, so this wins.
  session.addToolRunner(new GitToolRunner(git, relay, () => collab.currentRoomId(), author));
  session.addToolRunner(new VizToolRunner());

  // ---- Rig logs output channel (unchanged) ----------------------------------
  const logsChannel = new LogsChannel();
  context.subscriptions.push(logsChannel);

  // ---- Commands -------------------------------------------------------------
  context.subscriptions.push(
    vscode.commands.registerCommand("symposium.startRun", () => startRun()),
    vscode.commands.registerCommand("symposium.connectLogs", () => logsChannel.connect()),
    vscode.commands.registerCommand("symposium.disconnectLogs", () => logsChannel.disconnect()),
    vscode.commands.registerCommand("symposium.addModelKey", () => addModelKey(context)),
    vscode.commands.registerCommand("symposium.explainSelection", () => explain.explainActiveEditor()),
    vscode.commands.registerCommand("symposium.saveAndShare", () => saveAndShare(git)),
    vscode.commands.registerCommand("symposium.connectGpu", () => connectGpu()),
    vscode.commands.registerCommand("symposium.openMarketplace", () =>
      vscode.commands.executeCommand("symposium.marketplace.focus")
    ),
    vscode.commands.registerCommand("symposium.newRoom", () =>
      vscode.commands.executeCommand("symposium.collab.focus")
    ),
    vscode.commands.registerCommand("symposium.joinRoom", () =>
      vscode.commands.executeCommand("symposium.collab.focus")
    )
  );

  void setActive(true);

  const autoConnect = vscode.workspace.getConfiguration(CFG).get<boolean>("rig.autoConnect", false);
  if (autoConnect) logsChannel.connect();
}

export function deactivate(): void {
  void vscode.commands.executeCommand("setContext", "symposium.active", false);
}

/** Beginner "Save & Share" from the command palette: ask for a message, commit. */
async function saveAndShare(git: GitService): Promise<void> {
  const message = await vscode.window.showInputBox({
    title: "Save & Share",
    prompt: "Describe what you changed (this becomes your commit message).",
    placeHolder: "e.g. Add the login screen"
  });
  if (!message) return;
  try {
    const result = await git.saveAndShare(message);
    vscode.window.showInformationMessage(result.message || "Saved & shared ✓");
  } catch (err) {
    vscode.window.showErrorMessage(`Could not save: ${err instanceof Error ? err.message : String(err)}`);
  }
}
