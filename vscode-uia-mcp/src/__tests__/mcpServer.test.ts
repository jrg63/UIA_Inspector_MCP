/**
 * Unit tests for toolDefinitions — tool names, schemas, and validation.
 *
 * These tests import the real toolDefinitions module (no vscode dependency).
 */

import {
    TOOL_NAMES,
    ToolName,
    buildToolDefinitions,
    ToolDefinition,
} from "../toolDefinitions";

// ── Tests: Tool Name Registry ──────────────────────────────────

describe("Tool Name Registry", () => {
    test("all 26 tools are in TOOL_NAMES", () => {
        expect(TOOL_NAMES).toHaveLength(26);
    });

    test("TOOL_NAMES has no duplicates", () => {
        const unique = new Set<string>(TOOL_NAMES);
        expect(unique.size).toBe(TOOL_NAMES.length);
    });

    test.each(TOOL_NAMES)(
        "tool name '%s' follows snake_case convention",
        (name) => {
            expect(name).toMatch(/^[a-z][a-z0-9_]+$/);
        }
    );

    test("tool name validation rejects unknown tools", () => {
        const validSet = new Set<string>(TOOL_NAMES);
        expect(validSet.has("nonexistent_tool")).toBe(false);
        expect(validSet.has("find_element")).toBe(true);
    });
});

// ── Tests: Tool Definitions ────────────────────────────────────

describe("Tool Definitions", () => {
    let tools: ToolDefinition[];

    beforeAll(() => {
        tools = buildToolDefinitions();
    });

    test("generates exactly 26 tool definitions", () => {
        expect(tools).toHaveLength(26);
    });

    test("every tool has a name, description, and inputSchema", () => {
        for (const tool of tools) {
            expect(tool.name).toBeTruthy();
            expect(tool.description).toBeTruthy();
            expect(tool.description.length).toBeGreaterThan(10);
            expect(tool.inputSchema).toBeDefined();
            expect(tool.inputSchema.type).toBe("object");
            expect(tool.inputSchema.properties).toBeDefined();
            expect(Array.isArray(tool.inputSchema.required)).toBe(true);
        }
    });

    test("tool names match TOOL_NAMES registry", () => {
        const toolNames = tools.map((t) => t.name).sort();
        const registryNames = [...TOOL_NAMES].sort();
        expect(toolNames).toEqual(registryNames);
    });

    test("no duplicate tool names in definitions", () => {
        const seen = new Set<string>();
        for (const tool of tools) {
            expect(seen.has(tool.name)).toBe(false);
            seen.add(tool.name);
        }
    });

    test("required fields in inputSchemas are subsets of properties", () => {
        for (const tool of tools) {
            const propKeys = Object.keys(tool.inputSchema.properties);
            const reqKeys = tool.inputSchema.required;
            for (const req of reqKeys) {
                expect(propKeys).toContain(req);
            }
        }
    });

    test("scope enum values are valid", () => {
        const validScopes = ["Descendants", "Children", "Subtree", "Element"];
        for (const tool of tools) {
            const scope = tool.inputSchema.properties["scope"];
            if (scope?.enum) {
                for (const v of scope.enum) {
                    expect(validScopes).toContain(v);
                }
            }
        }
    });

    test("matchMode enum values are valid", () => {
        const validModes = ["Exact", "Contains", "StartsWith", "EndsWith"];
        for (const tool of tools) {
            const mm = tool.inputSchema.properties["matchMode"];
            if (mm?.enum) {
                for (const v of mm.enum) {
                    expect(validModes).toContain(v);
                }
            }
        }
    });

    test("find_element requires condition", () => {
        const fe = tools.find((t) => t.name === "find_element")!;
        expect(fe.inputSchema.required).toContain("condition");
    });

    test("find_all_elements requires condition", () => {
        const fa = tools.find((t) => t.name === "find_all_elements")!;
        expect(fa.inputSchema.required).toContain("condition");
    });

    test("check_match_count requires condition", () => {
        const cmc = tools.find((t) => t.name === "check_match_count")!;
        expect(cmc.inputSchema.required).toContain("condition");
    });

    test("inspect_element_wait requires condition", () => {
        const wfe = tools.find((t) => t.name === "inspect_element_wait")!;
        expect(wfe.inputSchema.required).toContain("condition");
    });

    test("get_window_info requires hwnd", () => {
        const gwi = tools.find((t) => t.name === "get_window_info")!;
        expect(gwi.inputSchema.required).toContain("hwnd");
    });

    test("inspect_element_at_point requires x and y", () => {
        const gep = tools.find((t) => t.name === "inspect_element_at_point")!;
        expect(gep.inputSchema.required).toContain("x");
        expect(gep.inputSchema.required).toContain("y");
    });

    test("inspect_at_cursor has no required params", () => {
        const iac = tools.find(
            (t) => t.name === "inspect_element_at_cursor"
        )!;
        expect(iac.inputSchema.required).toEqual([]);
    });

    test("get_focused_element has no required params", () => {
        const gfe = tools.find((t) => t.name === "get_focused_element")!;
        expect(gfe.inputSchema.required).toEqual([]);
    });

    test("list_windows filter property is optional string", () => {
        const lw = tools.find((t) => t.name === "list_windows")!;
        expect(lw.inputSchema.properties["filter"]).toBeDefined();
        expect(lw.inputSchema.properties["filter"].type).toBe("string");
        expect(lw.inputSchema.required).not.toContain("filter");
    });

    test("inspect_element_wait has optional timeout number property", () => {
        const wfe = tools.find((t) => t.name === "inspect_element_wait")!;
        expect(wfe.inputSchema.properties["timeout"]).toBeDefined();
        expect(wfe.inputSchema.properties["timeout"].type).toBe("number");
        expect(wfe.inputSchema.required).not.toContain("timeout");
    });

    test("find_element has optional index number property", () => {
        const fe = tools.find((t) => t.name === "find_element")!;
        expect(fe.inputSchema.properties["index"]).toBeDefined();
        expect(fe.inputSchema.properties["index"].type).toBe("number");
        expect(fe.inputSchema.required).not.toContain("index");
    });

    // ── New Phase 1+2 tool tests ──────────────────────────

    test("uia_get_type_catalog has no required params", () => {
        const tc = tools.find((t) => t.name === "uia_get_type_catalog")!;
        expect(tc).toBeDefined();
        expect(tc.inputSchema.required).toEqual([]);
    });

    test("uia_get_pattern_catalog has no required params", () => {
        const pc = tools.find((t) => t.name === "uia_get_pattern_catalog")!;
        expect(pc).toBeDefined();
        expect(pc.inputSchema.required).toEqual([]);
    });

    test("uia_perform_action requires action", () => {
        const pa = tools.find((t) => t.name === "uia_perform_action")!;
        expect(pa.inputSchema.required).toContain("action");
        expect(pa.inputSchema.properties["action"].enum).toContain("Invoke");
        expect(pa.inputSchema.properties["action"].enum).toContain("SetValue");
        expect(pa.inputSchema.properties["action"].enum).toContain("Highlight");
    });

    test("uia_perform_action action enum has all 10 values", () => {
        const pa = tools.find((t) => t.name === "uia_perform_action")!;
        expect(pa.inputSchema.properties["action"].enum).toHaveLength(10);
    });

    test("uia_set_value requires value", () => {
        const sv = tools.find((t) => t.name === "uia_set_value")!;
        expect(sv.inputSchema.required).toContain("value");
    });

    test("uia_highlight_element has optional duration and color", () => {
        const hl = tools.find((t) => t.name === "uia_highlight_element")!;
        expect(hl.inputSchema.properties["duration"]).toBeDefined();
        expect(hl.inputSchema.properties["duration"].type).toBe("number");
        expect(hl.inputSchema.properties["color"]).toBeDefined();
        expect(hl.inputSchema.properties["color"].type).toBe("string");
        expect(hl.inputSchema.required).toEqual([]);
    });

    test("uia_dump_tree has optional hwnd and maxDepth", () => {
        const dt = tools.find((t) => t.name === "uia_dump_tree")!;
        expect(dt.inputSchema.properties["hwnd"]).toBeDefined();
        expect(dt.inputSchema.properties["maxDepth"]).toBeDefined();
        expect(dt.inputSchema.required).toEqual([]);
    });

    test("uia_wait_element_not_exist requires condition", () => {
        const wne = tools.find((t) => t.name === "uia_wait_element_not_exist")!;
        expect(wne.inputSchema.required).toContain("condition");
    });

    test("uia_element_exists requires condition", () => {
        const ee = tools.find((t) => t.name === "uia_element_exists")!;
        expect(ee.inputSchema.required).toContain("condition");
    });

    // ── Phase 3 tool tests ──────────────────────────

    test("uia_get_element_from_path requires hwnd and path", () => {
        const fp = tools.find((t) => t.name === "uia_get_element_from_path")!;
        expect(fp).toBeDefined();
        expect(fp.inputSchema.required).toContain("hwnd");
        expect(fp.inputSchema.required).toContain("path");
    });

    test("uia_get_root_element has no required params", () => {
        const re = tools.find((t) => t.name === "uia_get_root_element")!;
        expect(re).toBeDefined();
        expect(re.inputSchema.required).toEqual([]);
    });

    test("uia_element_from_chromium requires hwnd", () => {
        const efc = tools.find((t) => t.name === "uia_element_from_chromium")!;
        expect(efc).toBeDefined();
        expect(efc.inputSchema.required).toContain("hwnd");
    });
});

// ── Tests: Tool Name Mapping ───────────────────────────────────

describe("Tool Name Mapping", () => {
    test("every defined tool has a corresponding engine method name", () => {
        const tools = buildToolDefinitions();
        const engineMethods = new Set<string>(TOOL_NAMES);
        for (const tool of tools) {
            expect(engineMethods.has(tool.name)).toBe(true);
        }
    });
});
