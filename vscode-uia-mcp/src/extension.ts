import * as vscode from "vscode";
import { AhkDaemonManager } from "./ahkDaemon";
import { UiaMcpServer } from "./mcpServer";

let daemon: AhkDaemonManager;
let mcpServer: UiaMcpServer;

export function activate(context: vscode.ExtensionContext) {
    const config = vscode.workspace.getConfiguration("uia-mcp");
    const outputChannel = vscode.window.createOutputChannel("UIA MCP");

    outputChannel.appendLine("UIA Inspector MCP extension activating...");

    // ── AHK Daemon Manager ─────────────────────
    daemon = new AhkDaemonManager(outputChannel, context);

    // ── MCP Server ─────────────────────────────
    mcpServer = new UiaMcpServer(daemon, outputChannel, context);

    // ── Register commands ──────────────────────
    context.subscriptions.push(
        vscode.commands.registerCommand("uia-mcp.startEngine", () => daemon.start()),
        vscode.commands.registerCommand("uia-mcp.stopEngine", () => daemon.stop()),
        vscode.commands.registerCommand("uia-mcp.restartEngine", () => daemon.restart()),
        vscode.commands.registerCommand("uia-mcp.showEngineStatus", () => daemon.showStatus())
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
