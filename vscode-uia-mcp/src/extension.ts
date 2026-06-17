import * as vscode from "vscode";
import { AhkDaemonManager } from "./ahkDaemon";
import { UiaMcpServer } from "./mcpServer";

let daemon: AhkDaemonManager;
let mcpServer: UiaMcpServer;

export function activate(context: vscode.ExtensionContext) {
    const config = vscode.workspace.getConfiguration("uia-mcp");
    const outputChannel = vscode.window.createOutputChannel("UIA MCP");
    const mcpDebugChannel = vscode.window.createOutputChannel("MCP Debug");

    mcpDebugChannel.appendLine(`UIA Inspector MCP extension activating at ${new Date().toISOString()}`);
    mcpDebugChannel.appendLine(`VS Code version: ${vscode.version}`);
    outputChannel.appendLine("UIA Inspector MCP extension activating...");

    // ── AHK Daemon Manager ─────────────────────
    daemon = new AhkDaemonManager(outputChannel, context);

    // ── MCP Server ─────────────────────────────
    mcpServer = new UiaMcpServer(daemon, outputChannel, context, mcpDebugChannel);

    // ── Register commands ──────────────────────
    context.subscriptions.push(
        vscode.commands.registerCommand("uia-mcp.startEngine", () => daemon.start()),
        vscode.commands.registerCommand("uia-mcp.stopEngine", () => daemon.stop()),
        vscode.commands.registerCommand("uia-mcp.restartEngine", () => daemon.restart()),
        vscode.commands.registerCommand("uia-mcp.showEngineStatus", () => daemon.showStatus()),
        vscode.commands.registerCommand("uia-mcp.inspectAtCursor", () => inspectAtCursor(daemon, outputChannel))
    );

    // ── Status bar ─────────────────────────────
    const statusBar = vscode.window.createStatusBarItem(
        vscode.StatusBarAlignment.Right,
        100
    );
    statusBar.command = "uia-mcp.showEngineStatus";
    daemon.onStateChange((state) => {
        switch (state) {
            case "running":
                statusBar.text = "$(debug-start) UIA MCP";
                statusBar.tooltip = "UIA MCP Engine is running";
                statusBar.backgroundColor = undefined;
                break;
            case "starting":
                statusBar.text = "$(sync~spin) UIA MCP";
                statusBar.tooltip = "UIA MCP Engine starting...";
                break;
            case "stopped":
                statusBar.text = "$(debug-stop) UIA MCP";
                statusBar.tooltip = "UIA MCP Engine stopped";
                statusBar.backgroundColor = new vscode.ThemeColor(
                    "statusBarItem.warningBackground"
                );
                break;
            case "error":
                statusBar.text = "$(error) UIA MCP";
                statusBar.tooltip = "UIA MCP Engine error";
                statusBar.backgroundColor = new vscode.ThemeColor(
                    "statusBarItem.errorBackground"
                );
                break;
            case "admin_needed":
                statusBar.text = "$(warning) UIA MCP Admin";
                statusBar.tooltip =
                    "Target is elevated — restart VS Code as Administrator";
                statusBar.backgroundColor = new vscode.ThemeColor(
                    "statusBarItem.warningBackground"
                );
                break;
        }
        statusBar.show();
    });
    context.subscriptions.push(statusBar);

    // ── Auto-launch ────────────────────────────
    if (config.get<boolean>("autoLaunch", true)) {
        daemon.start();
    }

    // ── Register MCP server ────────────────────
    mcpServer.register(context);

    outputChannel.appendLine("UIA Inspector MCP extension activated.");
}

export function deactivate() {
    daemon?.stop();
    mcpServer?.dispose();
}

// ── inspectAtCursor command ────────────────────
// Bound to a user hotkey; sends the cursor position
// to the AHK engine and shows the result inline.

async function inspectAtCursor(
    daemon: AhkDaemonManager,
    output: vscode.OutputChannel
) {
    if (daemon.getState() !== "running") {
        vscode.window.showWarningMessage("UIA MCP engine not running. Start it first.");
        return;
    }
    try {
        const result = await daemon.sendCommand("inspect_element_at_cursor", {});
        const text = JSON.stringify(result, null, 2);
        output.appendLine(`[inspectAtCursor] ${text}`);

        if (result.error) {
            // Graceful engine error (e.g. browser element not UIA-accessible)
            vscode.window.showWarningMessage(
                `UIA: ${result.message || "Not accessible"}`,
                { modal: false, detail: text },
                "Copy"
            ).then((choice) => {
                if (choice === "Copy") {
                    vscode.env.clipboard.writeText(text);
                }
            });
            return;
        }

        vscode.window.showInformationMessage(
            `Element: ${result.Type || "?"} "${result.Name || ""}"`,
            { modal: false, detail: text },
            "Copy"
        ).then((choice) => {
            if (choice === "Copy") {
                vscode.env.clipboard.writeText(text);
            }
        });
    } catch (err: any) {
        vscode.window.showErrorMessage(`UIA inspect failed: ${err.message}`);
    }
}
