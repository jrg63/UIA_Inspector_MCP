import * as vscode from "vscode";
import * as net from "net";
import * as path from "path";
import * as fs from "fs";
import * as os from "os";
import { spawn, ChildProcess, execFile } from "child_process";
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
    /** true when this instance spawned the engine; false when we adopted an already-running engine */
    private ownsProcess = false;
    private enginePid: number | null = null;

    private static readonly GLOBAL_STATE_KEY = "lastEngineScriptPath";
    private static readonly LOCK_FILE = path.join(os.tmpdir(), "UIA_MCP_Engine.lock");
    private static readonly ERROR_DIALOG_DETECTOR = "C:\\Scripts\\DetectAHKErrorDialog.exe";

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

        try {
            const result = findEngineScript(wsPaths, this.context.extensionPath, configPath || undefined);
            // Remember for cross-workspace reuse
            this.context.globalState.update(AhkDaemonManager.GLOBAL_STATE_KEY, result);
            return result;
        } catch (err) {
            // Fall back to the last-known-good path stored in globalState
            const lastPath = this.context.globalState.get<string>(AhkDaemonManager.GLOBAL_STATE_KEY);
            if (lastPath && fs.existsSync(lastPath)) {
                this.output.appendLine(
                    `Engine script not found in workspace; reusing last-known path: ${lastPath}`
                );
                return lastPath;
            }
            throw err;
        }
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

        // ── PID lockfile: prevent duplicate engine instances ──
        // If a stale lockfile exists from a crashed engine, release it.
        // If a live engine holds it, wait briefly then force-release.
        await this.acquireEngineLock();

        // Before spawning a new engine, check if one is already
        // listening on our port (e.g. from another VS Code window).
        // If so, adopt it instead of starting a second instance.
        try {
            const alreadyRunning = await this.ping();
            if (alreadyRunning) {
                this.output.appendLine("Engine already listening on port — adopting.");
                this.ownsProcess = false;
                this.releaseEngineLock();
                this.setState("running");
                this.startHealthCheck();
                return;
            }
        } catch {
            // No engine running — proceed with spawn
        }

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

            this.enginePid = this.process.pid ?? null;
            if (this.enginePid) {
                this.writeEngineLock(this.enginePid);
            }

            this.process.stdout?.on("data", (data: Buffer) => {
                this.output.appendLine(`[AHK stdout] ${data.toString().trim()}`);
            });

            this.process.stderr?.on("data", (data: Buffer) => {
                this.output.appendLine(`[AHK stderr] ${data.toString().trim()}`);
            });

            this.process.on("exit", (code) => {
                this.output.appendLine(`Engine exited with code ${code}`);
                this.process = null;
                this.enginePid = null;
                this.releaseEngineLock();
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
            this.ownsProcess = true;
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
        if (!this.ownsProcess) {
            this.output.appendLine("Not stopping engine (adopted from another window).");
            this.stopHealthCheck();
            this.setState("stopped");
            return;
        }
        if (this.process) {
            this.output.appendLine("Stopping AHK engine...");
            this.stopHealthCheck();
            const oldProc = this.process;
            this.process = null;
            this.ownsProcess = false;

            try {
                await this.sendCommand("shutdown", {});
            } catch (_) {
                /* engine may already be down */
            }

            // Capture error dialog before force-killing
            if (this.enginePid) {
                this.captureErrorDialog(this.enginePid);
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
        this.releaseEngineLock();
        this.enginePid = null;
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
                    this.output.appendLine("Health check failed — attempting auto-restart.");
                    this.setState("stopped");
                    // Try to capture the error dialog before restarting
                    if (this.enginePid) {
                        await this.captureErrorDialog(this.enginePid);
                    }
                    // Auto-restart: the engine may have been killed by a
                    // COM crash on a legacy window.  Try to bring it back.
                    await this.start();
                    if (this.state !== "running") {
                        this.setState("error");
                    }
                }
            } catch {
                if (this.state === "running") {
                    this.output.appendLine("Health check exception — attempting auto-restart.");
                    this.setState("stopped");
                    if (this.enginePid) {
                        await this.captureErrorDialog(this.enginePid);
                    }
                    await this.start();
                    if (this.state !== "running") {
                        this.setState("error");
                    }
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

    // ── Error dialog capture ──────────────────

    /**
     * Run DetectAHKErrorDialog.exe against the engine PID to capture
     * any AHK error dialog text before the process is killed.
     * Writes captured text to the VS Code output channel.
     */
    private async captureErrorDialog(pid: number): Promise<void> {
        const detectorPath = AhkDaemonManager.ERROR_DIALOG_DETECTOR;
        if (!fs.existsSync(detectorPath)) {
            this.output.appendLine(
                `[ErrorCapture] Detector not found at ${detectorPath} — cannot capture error dialog.`
            );
            return;
        }

        try {
            await new Promise<void>((resolve) => {
                const proc = spawn(detectorPath, [String(pid)], {
                    windowsHide: true,
                    timeout: 5000,
                });

                let timedOut = false;
                const timer = setTimeout(() => {
                    timedOut = true;
                    try { proc.kill(); } catch { /* ignore */ }
                    resolve();
                }, 5000);

                proc.on("exit", (code) => {
                    clearTimeout(timer);
                    if (timedOut) return;

                    // Read captured error text
                    const outputPath = path.join(os.tmpdir(), "ahk_error_dialog.txt");
                    try {
                        if (fs.existsSync(outputPath)) {
                            const text = fs.readFileSync(outputPath, "utf-8").trim();
                            if (text) {
                                this.output.appendLine(
                                    `[ErrorCapture] AHK error dialog detected (exit=${code}):\n${text}`
                                );
                            }
                            try { fs.unlinkSync(outputPath); } catch { /* ignore */ }
                        } else if (code === 1) {
                            this.output.appendLine(
                                `[ErrorCapture] Detector exit=1 but no output file — dialog may have been dismissed.`
                            );
                        }
                    } catch {
                        // File read failed — nothing to report
                    }
                    resolve();
                });

                proc.on("error", (err) => {
                    clearTimeout(timer);
                    this.output.appendLine(`[ErrorCapture] Detector spawn failed: ${err.message}`);
                    resolve();
                });
            });
        } catch {
            // Swallow — error capture is best-effort
        }
    }

    // ── PID lockfile management ───────────────

    /**
     * Acquire the engine lockfile. Waits up to 5s if another engine
     * instance holds it. Releases stale locks from dead processes.
     */
    private async acquireEngineLock(): Promise<void> {
        try {
            if (fs.existsSync(AhkDaemonManager.LOCK_FILE)) {
                const raw = fs.readFileSync(AhkDaemonManager.LOCK_FILE, "utf-8").trim();
                const oldPid = parseInt(raw, 10);
                if (!isNaN(oldPid)) {
                    try {
                        // Signal 0 checks existence without killing
                        process.kill(oldPid, 0);
                        this.output.appendLine(
                            `Lockfile held by PID ${oldPid} — waiting for release...`
                        );
                        // Wait up to 5 seconds
                        for (let i = 0; i < 50; i++) {
                            await new Promise((r) => setTimeout(r, 100));
                            if (!fs.existsSync(AhkDaemonManager.LOCK_FILE)) {
                                return;
                            }
                        }
                        this.output.appendLine("Lockfile wait timed out — force-releasing.");
                    } catch {
                        // Process doesn't exist — stale lock
                        this.output.appendLine(
                            `Lockfile PID ${oldPid} is dead — releasing stale lock.`
                        );
                    }
                }
                // Remove stale or timed-out lock
                try { fs.unlinkSync(AhkDaemonManager.LOCK_FILE); } catch { /* ignore */ }
            }
        } catch {
            // Best-effort — proceed even if lockfile ops fail
        }
    }

    private writeEngineLock(pid: number): void {
        try {
            fs.writeFileSync(AhkDaemonManager.LOCK_FILE, String(pid));
        } catch {
            // Non-critical
        }
    }

    private releaseEngineLock(): void {
        try {
            if (fs.existsSync(AhkDaemonManager.LOCK_FILE)) {
                fs.unlinkSync(AhkDaemonManager.LOCK_FILE);
            }
        } catch {
            // Non-critical
        }
    }
}
