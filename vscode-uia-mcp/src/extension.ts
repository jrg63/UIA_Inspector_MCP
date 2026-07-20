import * as vscode from "vscode";
import * as path from "path";
import * as fs from "fs";
import * as os from "os";
import { AhkDaemonManager } from "./ahkDaemon";
import { UiaMcpServer } from "./mcpServer";

let daemon: AhkDaemonManager;
let mcpServer: UiaMcpServer;

/** Key used in the user's mcp.json to identify this server. */
const MCP_SERVER_KEY = "jrg63/vscode-uia-mcp";

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
    // Start the daemon eagerly so the bridge spawned by VS Code (from
    // mcp.json) can connect immediately.  The engine has its own idle
    // timeout so it won't waste resources when unused.
    if (config.get<boolean>("autoLaunch", false)) {
        daemon.start();
    }

    // ── Register in mcp.json ───────────────────
    // Instead of the mcpServerDefinitionProviders API (which shows the
    // server under the regular Extensions list), we write the server
    // definition directly into the user's mcp.json so it appears in
    // "MCP SERVERS - INSTALLED" — the same mechanism Chrome DevTools MCP
    // and Playwright MCP use.
    registerMcpJsonServer(context, outputChannel, config);

    outputChannel.appendLine("UIA Inspector MCP extension activated.");
}

export function deactivate() {
    daemon?.stop();
    mcpServer?.dispose();
}

// ── mcp.json management ────────────────────────

function findNodeExeForMcp(): string {
    const execDir = path.dirname(process.execPath);
    const bundled = process.platform === "win32"
        ? path.join(execDir, "node.exe")
        : path.join(execDir, "node");
    if (fs.existsSync(bundled)) { return bundled; }
    return "node";
}

function getMcpJsonPath(): string {
    return path.join(os.homedir(), "AppData", "Roaming", "Code", "User", "mcp.json");
}

/**
 * Ensure the UIA Inspector MCP server appears in the user's mcp.json.
 * This is what makes it visible under "MCP SERVERS - INSTALLED" in the
 * Extensions view, and what lets users toggle it on/off.
 */
function registerMcpJsonServer(
    context: vscode.ExtensionContext,
    output: vscode.OutputChannel,
    config: vscode.WorkspaceConfiguration
): void {
    const mcpJsonPath = getMcpJsonPath();
    output.appendLine(`Updating MCP config: ${mcpJsonPath}`);

    try {
        const bridgePath = path.join(context.extensionPath, "out", "mcpBridge.js");
        const nodeExe = findNodeExeForMcp();
        const port = config.get<number>("enginePort", 9876) ?? 9876;
        const logLevel = config.get<string>("logLevel", "info") ?? "info";

        // Read existing mcp.json (preserve other servers)
        let mcpConfig: any = { servers: {}, inputs: [] };
        try {
            if (fs.existsSync(mcpJsonPath)) {
                mcpConfig = JSON.parse(fs.readFileSync(mcpJsonPath, "utf-8"));
                if (!mcpConfig.servers) { mcpConfig.servers = {}; }
                if (!mcpConfig.inputs) { mcpConfig.inputs = []; }
            }
        } catch {
            output.appendLine("Could not parse existing mcp.json — creating fresh config.");
        }

        // Check if our entry is already up to date
        const existing = mcpConfig.servers[MCP_SERVER_KEY];
        if (existing && existing.command === nodeExe && existing.args?.[0] === bridgePath) {
            output.appendLine(`MCP server "${MCP_SERVER_KEY}" already configured in mcp.json.`);
            return;
        }

        // Add / update our server entry
        mcpConfig.servers[MCP_SERVER_KEY] = {
            type: "stdio",
            command: nodeExe,
            args: [bridgePath],
            env: {
                UIA_MCP_PORT: String(port),
                UIA_MCP_LOG_LEVEL: logLevel,
                UIA_MCP_LOG_FILE: path.join(os.tmpdir(), "UIA_MCP_Bridge.log"),
            },
        };

        // Write back
        const dir = path.dirname(mcpJsonPath);
        if (!fs.existsSync(dir)) { fs.mkdirSync(dir, { recursive: true }); }
        fs.writeFileSync(mcpJsonPath, JSON.stringify(mcpConfig, null, "\t") + "\n");

        output.appendLine(`MCP server "${MCP_SERVER_KEY}" written to mcp.json.`);
        output.appendLine("Reload the VS Code window for the server to appear in MCP SERVERS.");
    } catch (err: any) {
        output.appendLine(`Failed to update mcp.json: ${err.message}`);
        vscode.window.showWarningMessage(
            `UIA Inspector MCP: Could not add server to mcp.json — ${err.message}`
        );
    }
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
