// ── Tool name registry (pure data, no vscode dependency) ──────────

export const TOOL_NAMES = [
    "inspect_element_at_cursor",
    "get_focused_element",
    "find_element",
    "find_all_elements",
    "get_element_tree",
    "get_ancestor_chain",
    "get_element_properties",
    "get_element_patterns",
    "list_windows",
    "get_window_info",
    "check_match_count",
    "get_child_elements",
    "get_bounding_rect",
    "wait_for_element",
    "get_element_at_point",
] as const;

export type ToolName = (typeof TOOL_NAMES)[number];

// ── Tool definition types ────────────────────────────────────────

export interface ToolDefinition {
    name: string;
    description: string;
    inputSchema: {
        type: string;
        properties: Record<string, any>;
        required: string[];
    };
}

// ── Build tool definitions ───────────────────────────────────────

export function buildToolDefinitions(): ToolDefinition[] {
    return [
        {
            name: "inspect_element_at_cursor",
            description:
                "Capture the UI element currently under the mouse cursor. Returns full element properties, patterns, ancestor chain, and inferred action. Use this when the user asks to identify or inspect a specific element they're pointing at.",
            inputSchema: { type: "object", properties: {}, required: [] },
        },
        {
            name: "get_focused_element",
            description:
                "Get the currently focused UI element (the one with keyboard focus). Returns full element properties, patterns, and ancestor chain. Use this to find what the user is currently interacting with.",
            inputSchema: { type: "object", properties: {}, required: [] },
        },
        {
            name: "find_element",
            description:
                "Find a single UI element matching a condition. Returns full element details or null if not found. Use this to locate a specific button, field, or control by its Type, Name, AutomationId, or ClassName.",
            inputSchema: {
                type: "object",
                properties: {
                    condition: {
                        type: "object",
                        description:
                            'UIA condition object, e.g. {"Type":"Button","Name":"OK"} or {"AutomationId":"submitBtn"}',
                    },
                    hwnd: {
                        type: "string",
                        description:
                            "Optional hex HWND of the target window. If omitted, uses the focused element's window.",
                    },
                    scope: {
                        type: "string",
                        enum: ["Descendants", "Children", "Subtree", "Element"],
                        description: "Search scope. Default: Descendants.",
                    },
                    matchMode: {
                        type: "string",
                        enum: ["Exact", "Contains", "StartsWith", "EndsWith"],
                        description: "String match mode. Default: Exact.",
                    },
                    index: {
                        type: "number",
                        description:
                            "1-based index when multiple matches exist. Default: 1.",
                    },
                },
                required: ["condition"],
            },
        },
        {
            name: "find_all_elements",
            description:
                "Find all UI elements matching a condition. Returns an array of element summaries (Type, Name, AutomationId, ClassName, IsEnabled). Use this to discover how many matching elements exist before narrowing a selector.",
            inputSchema: {
                type: "object",
                properties: {
                    condition: {
                        type: "object",
                        description: 'UIA condition object, e.g. {"Type":"Button"}',
                    },
                    hwnd: {
                        type: "string",
                        description: "Optional hex HWND of the target window.",
                    },
                    scope: {
                        type: "string",
                        enum: ["Descendants", "Children", "Subtree", "Element"],
                    },
                    matchMode: {
                        type: "string",
                        enum: ["Exact", "Contains", "StartsWith", "EndsWith"],
                    },
                },
                required: ["condition"],
            },
        },
        {
            name: "get_element_tree",
            description:
                "Get a compact text representation of the UIA tree for a window. Shows element types, names, AutomationIds, and class names up to a specified depth. Use this to explore the structure of an application.",
            inputSchema: {
                type: "object",
                properties: {
                    hwnd: {
                        type: "string",
                        description: "Hex HWND of the window to explore.",
                    },
                    maxDepth: {
                        type: "number",
                        description:
                            "Maximum tree depth. Default: 4. Higher values produce large outputs.",
                    },
                },
                required: ["hwnd"],
            },
        },
        {
            name: "get_ancestor_chain",
            description:
                "Walk from an element up to the root of the UIA tree. Returns an array of ancestor summaries (root-first). Use this to identify stable ancestor elements for anchor-based selectors.",
            inputSchema: {
                type: "object",
                properties: {
                    hwnd: { type: "string" },
                    condition: { type: "object" },
                    scope: {
                        type: "string",
                        enum: ["Descendants", "Children", "Subtree", "Element"],
                    },
                    matchMode: {
                        type: "string",
                        enum: ["Exact", "Contains", "StartsWith", "EndsWith"],
                    },
                    index: { type: "number" },
                },
                required: [],
            },
        },
        {
            name: "get_element_properties",
            description:
                "Get all known UIA properties for a resolved element.",
            inputSchema: {
                type: "object",
                properties: {
                    hwnd: { type: "string" },
                    condition: { type: "object" },
                    scope: {
                        type: "string",
                        enum: ["Descendants", "Children", "Subtree", "Element"],
                    },
                    matchMode: {
                        type: "string",
                        enum: ["Exact", "Contains", "StartsWith", "EndsWith"],
                    },
                    index: { type: "number" },
                },
                required: [],
            },
        },
        {
            name: "get_element_patterns",
            description:
                "Get the available UIA patterns for an element.",
            inputSchema: {
                type: "object",
                properties: {
                    hwnd: { type: "string" },
                    condition: { type: "object" },
                    scope: {
                        type: "string",
                        enum: ["Descendants", "Children", "Subtree", "Element"],
                    },
                    matchMode: {
                        type: "string",
                        enum: ["Exact", "Contains", "StartsWith", "EndsWith"],
                    },
                    index: { type: "number" },
                },
                required: [],
            },
        },
        {
            name: "list_windows",
            description:
                "Enumerate all open top-level windows on the desktop. Returns title, HWND, PID, exe path, and visibility for each window.",
            inputSchema: {
                type: "object",
                properties: {
                    filter: { type: "string" },
                },
                required: [],
            },
        },
        {
            name: "get_window_info",
            description:
                "Get detailed information about a specific window including title, class, exe, PID, rect, and elevation status.",
            inputSchema: {
                type: "object",
                properties: {
                    hwnd: { type: "string" },
                },
                required: ["hwnd"],
            },
        },
        {
            name: "check_match_count",
            description:
                "Count how many elements match a condition. Use this before calling find_element or find_all_elements to understand the scope of matches.",
            inputSchema: {
                type: "object",
                properties: {
                    condition: { type: "object" },
                    hwnd: { type: "string" },
                    scope: {
                        type: "string",
                        enum: ["Descendants", "Children", "Subtree", "Element"],
                    },
                    matchMode: {
                        type: "string",
                        enum: ["Exact", "Contains", "StartsWith", "EndsWith"],
                    },
                },
                required: ["condition"],
            },
        },
        {
            name: "get_child_elements",
            description:
                "Get the direct children of an element. Returns summaries for each child.",
            inputSchema: {
                type: "object",
                properties: {
                    hwnd: { type: "string" },
                    condition: { type: "object" },
                    scope: {
                        type: "string",
                        enum: ["Descendants", "Children", "Subtree", "Element"],
                    },
                    matchMode: {
                        type: "string",
                        enum: ["Exact", "Contains", "StartsWith", "EndsWith"],
                    },
                    index: { type: "number" },
                },
                required: [],
            },
        },
        {
            name: "get_bounding_rect",
            description:
                "Get the bounding rectangle (left, top, right, bottom) of an element.",
            inputSchema: {
                type: "object",
                properties: {
                    hwnd: { type: "string" },
                    condition: { type: "object" },
                    scope: {
                        type: "string",
                        enum: ["Descendants", "Children", "Subtree", "Element"],
                    },
                    matchMode: {
                        type: "string",
                        enum: ["Exact", "Contains", "StartsWith", "EndsWith"],
                    },
                    index: { type: "number" },
                },
                required: [],
            },
        },
        {
            name: "wait_for_element",
            description:
                "Poll until an element matching the condition appears, or timeout. Returns {found: true, element: ...} or {found: false}.",
            inputSchema: {
                type: "object",
                properties: {
                    condition: { type: "object" },
                    hwnd: { type: "string" },
                    timeout: { type: "number" },
                    scope: {
                        type: "string",
                        enum: ["Descendants", "Children", "Subtree", "Element"],
                    },
                    matchMode: {
                        type: "string",
                        enum: ["Exact", "Contains", "StartsWith", "EndsWith"],
                    },
                },
                required: ["condition"],
            },
        },
        {
            name: "get_element_at_point",
            description:
                "Get the UI element at specific screen coordinates (x, y).",
            inputSchema: {
                type: "object",
                properties: {
                    x: { type: "number" },
                    y: { type: "number" },
                },
                required: ["x", "y"],
            },
        },
    ];
}
