import * as vscode from "vscode";
import * as net from "net";
import * as path from "path";
import * as fs from "fs";
import * as os from "os";
import { spawn, ChildProcess } from "child_process";
import { findAhkExe, findEngineScript, getPortFile } from "./pathResolver";

export type EngineState =
    | "stopped"
    | "starting"
    | "running"
    | "error"
    | "admin_needed";

export class AhkDaemonManager {
    private process: ChildProcess | null = null;
    private state: EngineState = "stopped";
    private listeners: Array<(state: EngineState) => void> = [];
    private port: number;
    private idleTimer: NodeJS.Timeout | null = null;
    private healthCheckTimer: NodeJS.Timeout | null = null;
    private pendingRequests = 0;

    constructor(
        private output: vscode.OutputChannel,
        private context: vscode.ExtensionContext
    ) {
        this.port =
            vscode.workspace
                .getConfiguration("uia-mcp")
                .get<number>("enginePort", 9876) ?? 9876;
    }

    getState(): EngineState {
        return this.state;
    }

    onStateChange(cb: (state: EngineState) => void) {
        this.listeners.push(cb);
    }

    private setState(state: EngineState) {
        this.state = state;
        for (const cb of this.listeners) {
            try {
                cb(state);
            } catch (_) {
                /* ignore */
            }
        }
    }

    private findAhkExe(): string {
        const configPath = vscode.workspace
            .getConfiguration("uia-mcp")
            .get<string>("ahkEnginePath", "");
        return findAhkExe(configPath || undefined);
    }

    private findEngineScript(): string {
        const configPath = vscode.workspace
            .getConfiguration("uia-mcp")
            .get<string>("engineScriptPath", "");
        const workspaceFolders = vscode.workspace.workspaceFolders;
        const wsPaths: string[] = workspaceFolders
            ? workspaceFolders.map((f) => f.uri.fsPath)
            : [];
        return findEngineScript(wsPaths, this.context.extensionPath, configPath || undefined);
    }

    private getPortFile(): string {
        return getPortFile();
    }

    async start(): Promise<void> {
        if (this.state === "running" || this.state === "starting") {
            this.output.appendLine("Engine already running.");
            return;
        }

        this.setState("starting");
        this.output.appendLine("Starting AHK UIA engine...");

        try {
            const ahkExe = this.findAhkExe();
            const scriptPath = this.findEngineScript();
            const cfg = vscode.workspace.getConfiguration("uia-mcp");
            const idleTimeout = cfg.get<number>("engineIdleTimeout", 300) ?? 300;
            const logLevel = cfg.get<string>("logLevel", "info") ?? "info";
            const inspectHotkey = cfg.get<string>("inspectHotkey", "^+I") ?? "^+I";

            this.output.appendLine(`AHK: ${ahkExe}`);
            this.output.appendLine(`Script: ${scriptPath}`);
            this.output.appendLine(`Port: ${this.port}`);

            // Clean up stale port file
            const portFile = this.getPortFile();
            try {
                fs.unlinkSync(portFile);
            } catch (_) {
                /* doesn't exist */
            }

            this.process = spawn(ahkExe, [
                scriptPath,
                "--port",
                String(this.port),
                "--idle-timeout",
                String(idleTimeout),
                "--log-level",
                logLevel,
                "--inspect-hotkey",
                inspectHotkey,
                "--log-file",
                path.join(os.tmpdir(), "UIA_MCP_Engine.log"),
            ], {
                stdio: ["ignore", "pipe", "pipe"],
                windowsHide: true,
            });

            this.process.stdout?.on("data", (data: Buffer) => {
                this.output.appendLine(`[AHK stdout] ${data.toString().trim()}`);
            });

            this.process.stderr?.on("data", (data: Buffer) => {
                this.output.appendLine(`[AHK stderr] ${data.toString().trim()}`);
            });

            this.process.on("exit", (code) => {
                this.output.appendLine(`Engine exited with code ${code}`);
                this.process = null;
                this.setState("stopped");
                this.stopHealthCheck();
            });

            this.process.on("error", (err) => {
                this.output.appendLine(`Engine error: ${err.message}`);
                this.setState("error");
                this.stopHealthCheck();
            });

            // Wait for the engine to be ready (port file appears)
            await this.waitForReady();
            this.setState("running");
            this.startHealthCheck();
            this.output.appendLine("Engine started successfully.");
        } catch (err: any) {
            this.output.appendLine(`Failed to start engine: ${err.message}`);
            this.setState("error");
            vscode.window.showErrorMessage(
                `UIA MCP: Failed to start engine — ${err.message}`
            );
        }
    }

    private async waitForReady(timeoutMs = 15000): Promise<void> {
        const start = Date.now();
        const portFile = this.getPortFile();

        while (Date.now() - start < timeoutMs) {
            try {
                if (fs.existsSync(portFile)) {
                    // Verify the port is actually listening
                    await this.ping();
                    return;
                }
            } catch (_) {
                /* engine not ready yet */
            }
            await new Promise((r) => setTimeout(r, 250));
        }

        throw new Error("Engine did not start within timeout.");
    }

    async stop(): Promise<void> {
        if (this.process) {
            this.output.appendLine("Stopping AHK engine...");
            this.stopHealthCheck();
            const oldProc = this.process;

            try {
                await this.sendCommand("shutdown", {});
            } catch (_) {
                /* engine may already be down */
            }

            // Force kill if still alive after 3s.
            // exitCode is null while running; set when process exits.
            setTimeout(() => {
                if (oldProc && oldProc.exitCode === null) {
                    this.output.appendLine("Force-killing engine.");
                    oldProc.kill();
                }
            }, 3000);
        }
        this.setState("stopped");
    }

    async restart(): Promise<void> {
        await this.stop();
        await new Promise((r) => setTimeout(r, 1000));
        await this.start();
    }

    showStatus(): void {
        const info = [
            `State: ${this.state}`,
            `Port: ${this.port}`,
            `Pending requests: ${this.pendingRequests}`,
        ].join("\n");
        vscode.window.showInformationMessage(
            `UIA MCP Engine: ${this.state}`,
            { modal: false, detail: info },
            "Restart"
        ).then((choice) => {
            if (choice === "Restart") {
                this.restart();
            }
        });
    }

    // ── TCP command interface ──────────────────

    /**
     * Send a JSON-RPC command to the engine and return the response.
     * Tracks pending requests for the idle timer.
     */
    async sendCommand(
        method: string,
        params: Record<string, any> = {}
    ): Promise<any> {
        this.pendingRequests++;

        try {
            const request = JSON.stringify({
                jsonrpc: "2.0",
                method,
                params,
                id: Date.now(),
            }) + "\n";

            const response = await this.tcpSend(request);
            const parsed = JSON.parse(response);

            if (parsed.error) {
                throw new Error(
                    `Engine error [${parsed.error.code}]: ${parsed.error.message}`
                );
            }

            return parsed.result;
        } finally {
            this.pendingRequests--;
            this.resetIdleTimer();
        }
    }

    private tcpSend(data: string): Promise<string> {
        return new Promise((resolve, reject) => {
            const client = new net.Socket();
            let response = "";

            client.setTimeout(30000);

            client.connect(this.port, "127.0.0.1", () => {
                client.write(data);
            });

            client.on("data", (chunk: Buffer) => {
                response += chunk.toString("utf-8");
                // Response is newline-delimited JSON
                if (response.includes("\n")) {
                    client.destroy();
                    resolve(response.trim());
                }
            });

            client.on("error", (err: Error) => {
                client.destroy();
                reject(err);
            });

            client.on("timeout", () => {
                client.destroy();
                reject(new Error("Engine request timed out"));
            });
        });
    }

    async ping(): Promise<boolean> {
        try {
            const result = await this.sendCommand("ping", {});
            return result === "pong";
        } catch {
            return false;
        }
    }

    // ── Idle timer ─────────────────────────────

    private resetIdleTimer(): void {
        if (this.idleTimer) {
            clearTimeout(this.idleTimer);
        }
        // The engine handles its own idle timeout — we just track
    }

    // ── Health check ───────────────────────────

    private startHealthCheck(): void {
        this.stopHealthCheck();
        this.healthCheckTimer = setInterval(async () => {
            try {
                const ok = await this.ping();
                if (!ok && this.state === "running") {
                    this.output.appendLine("Health check failed — engine may be down.");
                    this.setState("error");
                }
            } catch {
                if (this.state === "running") {
                    this.setState("error");
                }
            }
        }, 30000);
    }

    private stopHealthCheck(): void {
        if (this.healthCheckTimer) {
            clearInterval(this.healthCheckTimer);
            this.healthCheckTimer = null;
        }
    }
}
