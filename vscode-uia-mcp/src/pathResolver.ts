import * as path from "path";
import * as fs from "fs";
import * as os from "os";

// ── Path detection (pure logic, no vscode dependency) ──────────

export const AHK_CANDIDATES = [
    "C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe",
    "C:\\Program Files\\AutoHotkey\\AutoHotkey64.exe",
    path.join(
        os.homedir(),
        "AppData",
        "Local",
        "Programs",
        "AutoHotkey",
        "v2",
        "AutoHotkey64.exe"
    ),
];

/**
 * Resolve the AutoHotkey64.exe path.
 * @param userPath  Optional user-configured path from settings.
 * @param fsExists  Injectable fs.existsSync for testing (defaults to real fs).
 */
export function findAhkExe(
    userPath?: string,
    fsExists: (p: string) => boolean = fs.existsSync
): string {
    if (userPath && fsExists(userPath)) {
        return userPath;
    }
    for (const p of AHK_CANDIDATES) {
        if (fsExists(p)) {
            return p;
        }
    }
    throw new Error(
        "AutoHotkey64.exe not found. Set uia-mcp.ahkEnginePath in settings."
    );
}

/**
 * Resolve the UIA_MCP_Engine.ahk script path.
 * @param workspaceFolders  Absolute paths of open workspace folders.
 * @param extensionPath     VS Code extension install path.
 * @param userPath          Optional user-configured path from settings.
 * @param fsExists          Injectable fs.existsSync for testing.
 */
export function findEngineScript(
    workspaceFolders: string[],
    extensionPath: string,
    userPath?: string,
    fsExists: (p: string) => boolean = fs.existsSync
): string {
    if (userPath && fsExists(userPath)) {
        return userPath;
    }

    const candidates = [
        ...workspaceFolders.map((ws) => path.join(ws, "UIA_MCP_Engine.ahk")),
        path.join(extensionPath, "..", "UIA_MCP_Engine.ahk"),
        path.join(extensionPath, "..", "..", "UIA_MCP_Engine.ahk"),
        path.join(extensionPath, "UIA_MCP_Engine.ahk"),
    ];

    for (const p of candidates) {
        if (fsExists(p)) {
            return p;
        }
    }

    throw new Error(
        "UIA_MCP_Engine.ahk not found. Set uia-mcp.engineScriptPath in settings."
    );
}

/**
 * Return the path to the port file used for engine readiness signaling.
 */
export function getPortFile(): string {
    return path.join(os.tmpdir(), "UIA_MCP_Engine.port");
}
