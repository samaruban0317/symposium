import * as vscode from "vscode";
import { EngineTrackerViewProvider } from "./engineTrackerView";
import { LogsChannel } from "./logsChannel";
import { startRun } from "./train";

const CFG = "symposium";

export function activate(context: vscode.ExtensionContext): void {
  // Context key so the Ctrl+Shift+T keybinding only overrides VS Code's
  // "reopen closed editor" when a Symposium view/context is active.
  const setActive = (active: boolean) =>
    vscode.commands.executeCommand("setContext", "symposium.active", active);

  // Engine Tracker webview view.
  const engineTracker = new EngineTrackerViewProvider(context.extensionUri);
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider(EngineTrackerViewProvider.viewType, engineTracker, {
      webviewOptions: { retainContextWhenHidden: true }
    }),
    engineTracker
  );

  // Rig logs output channel.
  const logsChannel = new LogsChannel();
  context.subscriptions.push(logsChannel);

  // Commands.
  context.subscriptions.push(
    vscode.commands.registerCommand("symposium.startRun", () => startRun()),
    vscode.commands.registerCommand("symposium.connectLogs", () => logsChannel.connect()),
    vscode.commands.registerCommand("symposium.disconnectLogs", () => logsChannel.disconnect())
  );

  // Mark Symposium active when the Engine Tracker view becomes visible, so the
  // keybinding is scoped. We flip it on activation (the view container exists)
  // and keep it true for the session — the additional `editorTextFocus` and the
  // command's own guard keep the behaviour safe.
  void setActive(true);

  // Auto-connect logs on activation if configured.
  const autoConnect = vscode.workspace.getConfiguration(CFG).get<boolean>("rig.autoConnect", false);
  if (autoConnect) {
    logsChannel.connect();
  }
}

export function deactivate(): void {
  // Disposables registered in context.subscriptions are cleaned up by VS Code.
  void vscode.commands.executeCommand("setContext", "symposium.active", false);
}
