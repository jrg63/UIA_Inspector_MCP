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
    { name: "get_bounding_rect", description: "Get element bounding rectangle.", inputSchema: { type: "object", properties: { hwnd: { type: "string" }, condition: { type: "object" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] }, index: { type: "number" } }, required: [] } },
    { name: "wait_for_element", description: "Poll until element appears or timeout.", inputSchema: { type: "object", properties: { condition: { type: "object" }, hwnd: { type: "string" }, timeout: { type: "number" }, scope: { type: "string", enum: ["Descendants","Children","Subtree","Element"] }, matchMode: { type: "string", enum: ["Exact","Contains","StartsWith","EndsWith"] } }, required: ["condition"] } },
    { name: "get_element_at_point", description: "Get element at screen coordinates.", inputSchema: { type: "object", properties: { x: { type: "number" }, y: { type: "number" } }, required: ["x", "y"] } },
];

function sendToEngine(req: string): Promise<string> {
    return new Promise((resolve, reject) => {
        const c = new net.Socket();
        let r = "";
        c.setTimeout(30000);
        c.connect(ENGINE_PORT, ENGINE_HOST, () => c.write(req + "\n"));
        c.on("data", (d: Buffer) => { r += d.toString("utf-8"); if (r.includes("\n")) { c.destroy(); resolve(r.trim()); } });
        c.on("error", (e: Error) => { c.destroy(); reject(e); });
        c.on("timeout", () => { c.destroy(); reject(new Error("Engine timeout")); });
    });
}

function ok(id: any, result: any): string {
    return JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n";
}

function err(id: any, code: number, message: string): string {
    return JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }) + "\n";
}

async function handleInitialize(id: any): Promise<string> {
    log(2, "MCP initialize");
    return ok(id, {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "UIA Inspector", version: "0.1.0" },
    });
}

async function handleToolsCall(id: any, params: any): Promise<string> {
    const engineReq = JSON.stringify({ jsonrpc: "2.0", method: params.name, params: params.arguments || {}, id: 1 });
    log(3, "Calling engine: " + params.name);
    try {
        const engineResp = await sendToEngine(engineReq);
        const p = JSON.parse(engineResp);
        if (p.error) {
            log(1, `Engine error [${params.name}]: ${p.error.message}`);
            return ok(id, { content: [{ type: "text", text: `Error: ${p.error.message}` }], isError: true });
        }
        log(3, "Engine OK: " + params.name);
        return ok(id, { content: [{ type: "text", text: JSON.stringify(p.result, null, 2) }] });
    } catch (e: any) {
        log(1, `Bridge error [${params.name}]: ${e.message}`);
        return ok(id, { content: [{ type: "text", text: `Bridge error: ${e.message}` }], isError: true });
    }
}

const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: false });

rl.on("line", async (line: string) => {
    let req: any;
    try { req = JSON.parse(line); } catch { log(1, "JSON parse error"); process.stdout.write(err(null, -32700, "Parse error")); return; }
    try {
        switch (req.method) {
            case "initialize": process.stdout.write(await handleInitialize(req.id)); break;
            case "notifications/initialized": break;
            case "tools/list": log(3, "tools/list requested"); process.stdout.write(ok(req.id, { tools: TOOLS })); break;
            case "tools/call": process.stdout.write(await handleToolsCall(req.id, req.params)); break;
            default: process.stdout.write(await sendToEngine(line) + "\n"); break;
        }
    } catch (e: any) { log(1, "Unhandled error: " + e.message); process.stdout.write(err(req.id, -32603, e.message)); }
});

rl.on("close", () => process.exit(0));
