/**
 * Unit tests for pathResolver — path detection and state machine logic.
 *
 * These tests import the real pathResolver module and mock fs.existsSync
 * via the injectable fsExists parameter for full determinism.
 */

import * as path from "path";
import * as os from "os";
import * as fs from "fs";
import {
    findAhkExe,
    findEngineScript,
    getPortFile,
    AHK_CANDIDATES,
} from "../pathResolver";

// ── State machine (mirrors ahkDaemon.ts EngineState type) ──────

type EngineState =
    | "stopped"
    | "starting"
    | "running"
    | "error"
    | "admin_needed";

const VALID_TRANSITIONS: Record<EngineState, EngineState[]> = {
    stopped: ["starting"],
    starting: ["running", "error", "stopped"],
    running: ["stopped", "error", "admin_needed"],
    error: ["starting", "stopped"],
    admin_needed: ["stopped", "starting"],
};

function isValidTransition(from: EngineState, to: EngineState): boolean {
    return VALID_TRANSITIONS[from]?.includes(to) ?? false;
}

// ── Tests: findAhkExe ──────────────────────────────────────────

describe("findAhkExe", () => {
    test("user-supplied path that exists is returned", () => {
        const fakeExe = path.join(os.tmpdir(), "_test_ahk_.exe");
        fs.writeFileSync(fakeExe, "fake");
        try {
            const result = findAhkExe(fakeExe);
            expect(result).toBe(fakeExe);
        } finally {
            fs.unlinkSync(fakeExe);
        }
    });

    test("throws when no candidate exists and no user path", () => {
        // Use the injectable fsExists to simulate all paths missing
        const noSuchFile = () => false;
        expect(() =>
            findAhkExe("/nonexistent/path/ahk.exe", noSuchFile)
        ).toThrow(/not found/);
    });

    test("returns first candidate when user path missing but candidate exists", () => {
        // Simulate only the second candidate existing
        const fakeExists = (p: string) => p === AHK_CANDIDATES[1];
        const result = findAhkExe(undefined, fakeExists);
        expect(result).toBe(AHK_CANDIDATES[1]);
    });

    test("candidates array includes common paths", () => {
        expect(AHK_CANDIDATES.length).toBeGreaterThanOrEqual(2);
        expect(AHK_CANDIDATES[0]).toContain("AutoHotkey");
        expect(AHK_CANDIDATES[0]).toContain("AutoHotkey64.exe");
    });
});

// ── Tests: findEngineScript ────────────────────────────────────

describe("findEngineScript", () => {
    test("user-supplied path that exists is returned", () => {
        const fakeScript = path.join(os.tmpdir(), "_test_engine_.ahk");
        fs.writeFileSync(fakeScript, "#Requires AutoHotkey v2.0");
        try {
            const result = findEngineScript([], "/ext", fakeScript);
            expect(result).toBe(fakeScript);
        } finally {
            fs.unlinkSync(fakeScript);
        }
    });

    test("workspace folder is searched before extension path", () => {
        const wsDir = path.join(os.tmpdir(), "_test_ws_");
        const enginePath = path.join(wsDir, "UIA_MCP_Engine.ahk");
        try {
            fs.mkdirSync(wsDir, { recursive: true });
            fs.writeFileSync(enginePath, "test");
            const result = findEngineScript([wsDir], "/ext");
            expect(result).toBe(enginePath);
        } finally {
            fs.unlinkSync(enginePath);
            fs.rmSync(wsDir, { recursive: true });
        }
    });

    test("throws when no script found", () => {
        const noSuchFile = () => false;
        expect(() =>
            findEngineScript(
                ["/nonexistent/ws"],
                "/ext",
                "/no/script.ahk",
                noSuchFile
            )
        ).toThrow(/not found/);
    });

    test("user path takes priority over workspace and extension", () => {
        const wsDir = path.join(os.tmpdir(), "_test_ws_prio_");
        const wsEngine = path.join(wsDir, "UIA_MCP_Engine.ahk");
        const userEngine = path.join(os.tmpdir(), "_test_user_engine_.ahk");
        try {
            fs.mkdirSync(wsDir, { recursive: true });
            fs.writeFileSync(wsEngine, "workspace");
            fs.writeFileSync(userEngine, "user");
            // Even though workspace has it, user path wins
            const result = findEngineScript([wsDir], "/ext", userEngine);
            expect(result).toBe(userEngine);
        } finally {
            fs.unlinkSync(wsEngine);
            fs.rmSync(wsDir, { recursive: true });
            fs.unlinkSync(userEngine);
        }
    });
});

// ── Tests: getPortFile ─────────────────────────────────────────

describe("getPortFile", () => {
    test("returns path in temp directory", () => {
        const pf = getPortFile();
        expect(pf).toContain(os.tmpdir());
        expect(pf).toContain("UIA_MCP_Engine.port");
    });

    test("is a valid path", () => {
        const pf = getPortFile();
        expect(path.isAbsolute(pf)).toBe(true);
        expect(path.extname(pf)).toBe(".port");
    });
});

// ── Tests: Engine State Machine ────────────────────────────────

describe("Engine State Machine", () => {
    test("all valid transitions", () => {
        expect(isValidTransition("stopped", "starting")).toBe(true);
        expect(isValidTransition("starting", "running")).toBe(true);
        expect(isValidTransition("starting", "error")).toBe(true);
        expect(isValidTransition("starting", "stopped")).toBe(true);
        expect(isValidTransition("running", "stopped")).toBe(true);
        expect(isValidTransition("running", "error")).toBe(true);
        expect(isValidTransition("running", "admin_needed")).toBe(true);
        expect(isValidTransition("error", "starting")).toBe(true);
        expect(isValidTransition("error", "stopped")).toBe(true);
        expect(isValidTransition("admin_needed", "stopped")).toBe(true);
        expect(isValidTransition("admin_needed", "starting")).toBe(true);
    });

    test("invalid transitions are rejected", () => {
        expect(isValidTransition("stopped", "running")).toBe(false);
        expect(isValidTransition("stopped", "error")).toBe(false);
        expect(isValidTransition("running", "running")).toBe(false);
        expect(isValidTransition("running", "starting")).toBe(false);
        expect(isValidTransition("error", "running")).toBe(false);
        expect(isValidTransition("admin_needed", "running")).toBe(false);
        expect(isValidTransition("admin_needed", "error")).toBe(false);
        expect(isValidTransition("starting", "starting")).toBe(false);
    });

    test("all states have at least one valid outgoing transition", () => {
        const states: EngineState[] = [
            "stopped",
            "starting",
            "running",
            "error",
            "admin_needed",
        ];
        for (const s of states) {
            const outgoing = VALID_TRANSITIONS[s];
            expect(outgoing).toBeDefined();
            expect(outgoing.length).toBeGreaterThan(0);
        }
    });

    test("all states can eventually reach stopped", () => {
        expect(isValidTransition("starting", "stopped")).toBe(true);
        expect(isValidTransition("running", "stopped")).toBe(true);
        expect(isValidTransition("error", "stopped")).toBe(true);
        expect(isValidTransition("admin_needed", "stopped")).toBe(true);
    });
});

// ── Tests: JSON-RPC Response Parsing ───────────────────────────

describe("JSON-RPC Response Parsing", () => {
    test("parses success response", () => {
        const json = `{"jsonrpc":"2.0","result":{"Type":"Button","Name":"OK"},"id":42}`;
        const parsed = JSON.parse(json);
        expect(parsed.jsonrpc).toBe("2.0");
        expect(parsed.result).toBeDefined();
        expect(parsed.result.Type).toBe("Button");
        expect(parsed.id).toBe(42);
        expect(parsed.error).toBeUndefined();
    });

    test("parses error response", () => {
        const json = `{"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"},"id":42}`;
        const parsed = JSON.parse(json);
        expect(parsed.error).toBeDefined();
        expect(parsed.error.code).toBe(-32601);
        expect(parsed.error.message).toBe("Method not found");
        expect(parsed.result).toBeUndefined();
    });

    test("parses response without id (notification)", () => {
        const json = `{"jsonrpc":"2.0","result":"ok"}`;
        const parsed = JSON.parse(json);
        expect(parsed.jsonrpc).toBe("2.0");
        expect(parsed.result).toBe("ok");
        expect(parsed.id).toBeUndefined();
    });

    test("rejects non-JSON response", () => {
        expect(() => JSON.parse("not json")).toThrow();
    });
});

// ── Tests: Request Construction ────────────────────────────────

describe("Request Construction", () => {
    function buildRequest(
        method: string,
        params: Record<string, any> = {},
        id = 1
    ): string {
        return JSON.stringify({
            jsonrpc: "2.0",
            method,
            params,
            id,
        });
    }

    test("builds valid JSON-RPC 2.0 request", () => {
        const req = buildRequest("ping");
        const parsed = JSON.parse(req);
        expect(parsed.jsonrpc).toBe("2.0");
        expect(parsed.method).toBe("ping");
        expect(parsed.id).toBe(1);
    });

    test("request with params produces valid JSON", () => {
        const req = buildRequest("find_element", {
            condition: { Type: "Button", Name: "OK" },
            hwnd: "0x12345",
        });
        const parsed = JSON.parse(req);
        expect(parsed.params.condition.Type).toBe("Button");
        expect(parsed.params.hwnd).toBe("0x12345");
    });

    test("buildRequest includes all required JSON-RPC fields", () => {
        const req = buildRequest("list_windows", { filter: "Notepad" }, 99);
        const parsed = JSON.parse(req);
        expect(parsed).toHaveProperty("jsonrpc");
        expect(parsed).toHaveProperty("method");
        expect(parsed).toHaveProperty("params");
        expect(parsed).toHaveProperty("id");
        expect(parsed.jsonrpc).toBe("2.0");
        expect(parsed.id).toBe(99);
    });
});
