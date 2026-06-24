#!/usr/bin/env node
/**
 * MCP stdio bridge — translates MCP JSON-RPC over stdin/stdout
 * to our AHK UIA engine over raw TCP.
 */
import * as net from "net";
import * as readline from "readline";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";

const ENGINE_PORT = parseInt(process.env.UIA_MCP_PORT || "9876", 10);
const ENGINE_HOST = "127.0.0.1";
const LOG_LEVEL = parseLogLevel(process.env.UIA_MCP_LOG_LEVEL);
const LOG_FILE = process.env.UIA_MCP_LOG_FILE || path.join(os.tmpdir(), "UIA_MCP_Bridge.log");
const SOCKET_TIMEOUT_MS = 60000;        // 60s — some UIA tree walks are slow
const MAX_RETRIES = 3;                  // retry transient failures
const RETRY_BACKOFF_MS = 1000;          // 1s between retries

function parseLogLevel(v?: string): number {
    switch (v) { case "debug": return 3; case "info": return 2; case "error": return 1; default: return 1; }
}

function log(level: number, msg: string): void {
    if (level > LOG_LEVEL) return;
    const labels = ["NONE", "ERROR", "INFO ", "DEBUG"];
    const ts = new Date().toISOString().replace("T", " ").slice(0, 19);
    const line = `[${ts}] ${labels[level]} [bridge] ${msg}\n`;
    try { fs.appendFileSync(LOG_FILE, line); } catch (_) {}
    try { process.stderr.write(line); } catch (_) {}
}

// ── Truncated JSON for debug logging ──────────
// Prevents log bloat from huge element-tree responses while
// still capturing enough context to replay failing requests.
const MAX_DEBUG_JSON = 4096;

function truncateJson(s: string): string {
    if (s.length <= MAX_DEBUG_JSON) return s;
    return s.slice(0, MAX_DEBUG_JSON) + `... (truncated, total ${s.length} bytes)`;
}

let _reqSeq = 0;
function nextReqSeq(): number { return ++_reqSeq; }

const TOOLS = [
    { name: "list_windows", description: "Enumerate all open top-level windows on the desktop.", inputSchema: { type: "object", properties: { filter: { type: "string" } }, required: [] } },
    { name: "get_window_info", description: "Get detailed information about a specific window.", inputSchema: { type: "object", properties: { hwnd: { type: "string" } }, required: ["hwnd"] } },
    { name: "get_focused_element", description: "Get the currently focused UI element.", inputSchema: { type: "object", properties: {}, required: [] } },
    { name: "inspect_element_at_cursor", description: "Capture the UI element under the mouse cursor.", inputSchema: { type: "object", properties: {}, required: [] } },
    { name: "find_element", description: "Find a single UI element matching a condition.", inputSchema: { type: "object", properties: { condition: { type: "object" }, hwnd: { type: "string" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] }, index: { type: "number" } }, required: ["condition"] } },
    { name: "find_all_elements", description: "Find all UI elements matching a condition.", inputSchema: { type: "object", properties: { condition: { type: "object" }, hwnd: { type: "string" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] } }, required: ["condition"] } },
    { name: "get_element_tree", description: "Get a compact text tree of the UIA hierarchy.", inputSchema: { type: "object", properties: { hwnd: { type: "string" }, maxDepth: { type: "number" } }, required: ["hwnd"] } },
    { name: "get_ancestor_chain", description: "Walk from an element up to the UIA tree root.", inputSchema: { type: "object", properties: { hwnd: { type: "string" }, condition: { type: "object" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] }, index: { type: "number" } }, required: [] } },
    { name: "get_element_properties", description: "Get all UIA properties for an element.", inputSchema: { type: "object", properties: { hwnd: { type: "string" }, condition: { type: "object" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] }, index: { type: "number" } }, required: [] } },
    { name: "get_element_patterns", description: "Get available UIA patterns for an element.", inputSchema: { type: "object", properties: { hwnd: { type: "string" }, condition: { type: "object" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] }, index: { type: "number" } }, required: [] } },
    { name: "check_match_count", description: "Count matching elements.", inputSchema: { type: "object", properties: { condition: { type: "object" }, hwnd: { type: "string" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] } }, required: ["condition"] } },
    { name: "get_child_elements", description: "Get direct children of an element.", inputSchema: { type: "object", properties: { hwnd: { type: "string" }, condition: { type: "object" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] }, index: { type: "number" } }, required: [] } },
    { name: "inspect_bounding_rect", description: "Get element bounding rectangle.", inputSchema: { type: "object", properties: { hwnd: { type: "string" }, condition: { type: "object" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] }, index: { type: "number" } }, required: [] } },
    { name: "inspect_element_wait", description: "Poll until element appears or timeout.", inputSchema: { type: "object", properties: { condition: { type: "object" }, hwnd: { type: "string" }, timeout: { type: "number" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] } }, required: ["condition"] } },
    { name: "inspect_element_at_point", description: "Get element at screen coordinates.", inputSchema: { type: "object", properties: { x: { type: "number" }, y: { type: "number" } }, required: ["x", "y"] } },
    { name: "uia_get_type_catalog", description: "Get all valid UIA control type names and IDs.", inputSchema: { type: "object", properties: {}, required: [] } },
    { name: "uia_get_pattern_catalog", description: "Get all UIA patterns with their methods and properties.", inputSchema: { type: "object", properties: {}, required: [] } },
    { name: "uia_perform_action", description: "Perform an action on a UIA element (Invoke, Toggle, Click, SetValue, etc.).", inputSchema: { type: "object", properties: { hwnd: { type: "string" }, condition: { type: "object" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] }, index: { type: "number" }, action: { type: "string", enum: ["Invoke","Toggle","Click","Expand","Collapse","Select","ScrollIntoView","SetFocus","Highlight","SetValue"] }, value: { type: "string" } }, required: ["action"] } },
    { name: "uia_set_value", description: "Set the value of a UIA element.", inputSchema: { type: "object", properties: { hwnd: { type: "string" }, condition: { type: "object" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] }, index: { type: "number" }, value: { type: "string" } }, required: ["value"] } },
    { name: "uia_highlight_element", description: "Highlight an element for visual confirmation.", inputSchema: { type: "object", properties: { hwnd: { type: "string" }, condition: { type: "object" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] }, index: { type: "number" }, duration: { type: "number" }, color: { type: "string" } }, required: [] } },
    { name: "uia_dump_tree", description: "Comprehensive text dump of element tree.", inputSchema: { type: "object", properties: { hwnd: { type: "string" }, maxDepth: { type: "number" } }, required: [] } },
    { name: "uia_wait_element_not_exist", description: "Poll until element disappears or timeout.", inputSchema: { type: "object", properties: { condition: { type: "object" }, hwnd: { type: "string" }, timeout: { type: "number" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] } }, required: ["condition"] } },
    { name: "uia_element_exists", description: "Check if element exists without throwing.", inputSchema: { type: "object", properties: { condition: { type: "object" }, hwnd: { type: "string" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] } }, required: ["condition"] } },
    { name: "uia_get_element_from_path", description: "Navigate UIA tree using path syntax.", inputSchema: { type: "object", properties: { hwnd: { type: "string" }, path: { type: "string" } }, required: ["hwnd", "path"] } },
    { name: "uia_get_root_element", description: "Get the desktop root element.", inputSchema: { type: "object", properties: {}, required: [] } },
    { name: "uia_element_from_chromium", description: "Get Chromium content element from browser.", inputSchema: { type: "object", properties: { hwnd: { type: "string" } }, required: ["hwnd"] } },
    { name: "uia_get_state_enums", description: "Get UIA state value mappings (ToggleState, ExpandCollapseState, etc.).", inputSchema: { type: "object", properties: {}, required: [] } },
    { name: "uia_manage_window", description: "Activate, minimize, maximize, restore, close, move, or resize a window.", inputSchema: { type: "object", properties: { hwnd: { type: "string" }, action: { type: "string", enum: ["Activate","Minimize","Maximize","Restore","Close","Move","Resize"] }, x: { type: "number" }, y: { type: "number" }, width: { type: "number" }, height: { type: "number" } }, required: ["hwnd", "action"] } },
    { name: "uia_capture_screenshot", description: "Capture a screenshot of a window.", inputSchema: { type: "object", properties: { hwnd: { type: "string" }, filePath: { type: "string" } }, required: ["hwnd"] } },
    { name: "uia_get_code_recipe", description: "Get AHK v2 code templates for common scenarios.", inputSchema: { type: "object", properties: { recipe: { type: "string" } }, required: ["recipe"] } },
];

function isTransient(err: Error): boolean {
    const msg = err.message.toLowerCase();
    return msg.includes("econnrefused") || msg.includes("engine timeout");
}

function sendToEngine(req: string, retries = MAX_RETRIES, seq?: number): Promise<string> {
    const label = seq != null ? `[#${seq}] ` : "";
    log(3, `${label}>> engine: ${truncateJson(req)}`);
    return new Promise((resolve, reject) => {
        const c = new net.Socket();
        let r = "";
        c.setTimeout(SOCKET_TIMEOUT_MS);
        c.connect(ENGINE_PORT, ENGINE_HOST, () => c.write(req + "\n"));
        c.on("data", (d: Buffer) => { r += d.toString("utf-8"); if (r.includes("\n")) { c.destroy(); log(3, `${label}<< engine: ${truncateJson(r.trim())}`); resolve(r.trim()); } });
        c.on("error", (e: Error) => {
            c.destroy();
            if (retries > 0 && isTransient(e)) {
                log(2, `Transient error (${e.message}), retrying in ${RETRY_BACKOFF_MS}ms (${retries} left)`);
                setTimeout(() => sendToEngine(req, retries - 1, seq).then(resolve, reject), RETRY_BACKOFF_MS);
            } else {
                reject(e);
            }
        });
        c.on("timeout", () => {
            c.destroy();
            if (retries > 0) {
                log(2, `Socket timeout, retrying in ${RETRY_BACKOFF_MS}ms (${retries} left)`);
                setTimeout(() => sendToEngine(req, retries - 1, seq).then(resolve, reject), RETRY_BACKOFF_MS);
            } else {
                reject(new Error("Engine timeout after retries"));
            }
        });
    });
}

// ── Request queue ──────────────────────────────
// The AHK engine handles one TCP connection at a time.
// Concurrent calls timeout, causing Copilot to disable tools.
// This queue serialises all engine requests.
let _queue: Promise<any> = Promise.resolve();

function enqueueEngine<T>(fn: () => Promise<T>): Promise<T> {
    return new Promise<T>((resolve, reject) => {
        _queue = _queue.then(() => fn().then(resolve, reject), () => fn().then(resolve, reject));
    });
}

function ok(id: any, result: any): string {
    return JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n";
}

function err(id: any, code: number, message: string): string {
    return JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }) + "\n";
}

async function handleInitialize(id: any, params: any): Promise<string> {
    log(2, `MCP initialize id=${id} client=${JSON.stringify(params?.clientInfo || {})}`);
    return ok(id, {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "UIA Inspector", version: "0.1.0" },
    });
}

async function handleToolsCall(id: any, params: any): Promise<string> {
    const seq = nextReqSeq();
    const toolName = params?.name || "?";
    const toolArgs = params?.arguments || {};

    // Log the full MCP request so it can be replayed after a fix
    log(2, `[#${seq}] tools/call id=${id} method=${toolName} args=${truncateJson(JSON.stringify(toolArgs))}`);

    const engineReq = JSON.stringify({ jsonrpc: "2.0", method: toolName, params: toolArgs, id: 1 });
    const t0 = Date.now();
    try {
        const engineResp = await enqueueEngine(() => sendToEngine(engineReq, MAX_RETRIES, seq));
        const elapsed = Date.now() - t0;
        const p = JSON.parse(engineResp);
        if (p.error) {
            log(1, `[#${seq}] Engine error [${toolName}] (${elapsed}ms): ${p.error.message} | args=${truncateJson(JSON.stringify(toolArgs))}`);
            // Return error as normal content (not isError) to avoid VS Code auto-disabling the tool
            return ok(id, { content: [{ type: "text", text: `Error: ${p.error.message}` }] });
        }
        log(2, `[#${seq}] Engine OK [${toolName}] (${elapsed}ms)`);
        return ok(id, { content: [{ type: "text", text: JSON.stringify(p.result, null, 2) }] });
    } catch (e: any) {
        const elapsed = Date.now() - t0;
        log(1, `[#${seq}] Bridge error [${toolName}] (${elapsed}ms): ${e.message} | args=${truncateJson(JSON.stringify(toolArgs))}`);
        // Return bridge error as normal content — VS Code won't auto-disable the tool
        return ok(id, { content: [{ type: "text", text: `Bridge error (engine may be restarting — try again): ${e.message}` }] });
    }
}

const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: false });

// ── Keep-alive: ping the engine every 60s to prevent idle timeout ──
// The engine shuts down after 300s of inactivity.  Without this,
// Copilot marks tools as "disabled" after the first failed call.
let keepAliveFailCount = 0;
const KEEPALIVE_MS = 60000;
setInterval(async () => {
    try {
        await enqueueEngine(() => sendToEngine(JSON.stringify({ jsonrpc: "2.0", method: "ping", params: {}, id: -1 }), 0));
        keepAliveFailCount = 0;
        log(3, "Keep-alive ping OK");
    } catch {
        keepAliveFailCount++;
        log(1, `Keep-alive ping FAILED (${keepAliveFailCount})`);
    }
}, KEEPALIVE_MS);
log(2, "Keep-alive started (every " + (KEEPALIVE_MS / 1000) + "s)");

rl.on("line", async (line: string) => {
    let req: any;
    try { req = JSON.parse(line); } catch { log(1, "JSON parse error on stdin: " + truncateJson(line)); process.stdout.write(err(null, -32700, "Parse error")); return; }
    try {
        switch (req.method) {
            case "initialize": process.stdout.write(await handleInitialize(req.id, req.params)); break;
            case "notifications/initialized": log(2, "MCP notifications/initialized"); break;
            case "tools/list": {
                log(2, `tools/list requested — returning ${TOOLS.length} tools`);
                const response = ok(req.id, { tools: TOOLS });
                log(3, `tools/list response size: ${response.length} bytes`);
                // Write to temp file for diagnostics
                try { fs.writeFileSync(path.join(os.tmpdir(), "UIA_MCP_ToolsList.json"), response); } catch (_) {}
                process.stdout.write(response);
                break;
            }
            case "tools/call": process.stdout.write(await handleToolsCall(req.id, req.params)); break;
            default:
                log(2, `Forwarding unknown method to engine: ${req.method} id=${req.id}`);
                process.stdout.write(await enqueueEngine(() => sendToEngine(line)) + "\n");
                break;
        }
    } catch (e: any) { log(1, "Unhandled error: " + e.message); process.stdout.write(err(req.id, -32603, e.message)); }
});

rl.on("close", () => process.exit(0));
