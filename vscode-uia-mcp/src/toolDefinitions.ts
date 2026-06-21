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
    "inspect_bounding_rect",
    "inspect_element_wait",
    "inspect_element_at_point",
    "uia_get_type_catalog",
    "uia_get_pattern_catalog",
    "uia_perform_action",
    "uia_set_value",
    "uia_highlight_element",
    "uia_dump_tree",
    "uia_wait_element_not_exist",
    "uia_element_exists",
    "uia_get_element_from_path",
    "uia_get_root_element",
    "uia_element_from_chromium",
    "uia_get_state_enums",
    "uia_manage_window",
    "uia_capture_screenshot",
    "uia_get_code_recipe",
    "uia_get_element_code",
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
            name: "inspect_bounding_rect",
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
            name: "inspect_element_wait",
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
            name: "inspect_element_at_point",
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
        {
            name: "uia_get_type_catalog",
            description:
                "Get the full catalog of UIA control types (e.g. Button=50000, Edit=50004, CheckBox=50002, etc.). Returns a mapping of type name to integer ID. Use this to discover valid values for the Type field in conditions.",
            inputSchema: { type: "object", properties: {}, required: [] },
        },
        {
            name: "uia_get_pattern_catalog",
            description:
                "Get the full catalog of UIA patterns with their available methods and properties. Returns pattern name → {methods: [...], properties: [...]}. Use this to discover what actions (Invoke, Toggle, SetValue, etc.) are available on different pattern types.",
            inputSchema: { type: "object", properties: {}, required: [] },
        },
        {
            name: "uia_perform_action",
            description:
                "Perform an action on a UIA element: Invoke (press button), Toggle (checkbox), Click, Expand/Collapse, Select (list item), ScrollIntoView, SetFocus, Highlight (visual debug), or SetValue (type text). REQUIRES an element locator plus an action name. For SetValue, also provide a value parameter.",
            inputSchema: {
                type: "object",
                properties: {
                    hwnd: { type: "string", description: "Optional hex HWND" },
                    condition: {
                        type: "object",
                        description: "UIA condition to locate the element",
                    },
                    scope: {
                        type: "string",
                        enum: ["Descendants", "Children", "Subtree", "Element"],
                    },
                    matchMode: {
                        type: "string",
                        enum: ["Exact", "Contains", "StartsWith", "EndsWith"],
                    },
                    index: { type: "number" },
                    action: {
                        type: "string",
                        enum: [
                            "Invoke", "Toggle", "Click", "Expand", "Collapse",
                            "Select", "ScrollIntoView", "SetFocus", "Highlight",
                            "SetValue",
                        ],
                        description: "The action to perform on the element",
                    },
                    value: {
                        type: "string",
                        description: "Value for SetValue action (ignored for other actions)",
                    },
                },
                required: ["action"],
            },
        },
        {
            name: "uia_set_value",
            description:
                "Set the value of a UIA element (type text into an Edit field, set checkbox state, adjust slider position). Shorthand for uia_perform_action with action=SetValue.",
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
                    value: {
                        type: "string",
                        description: "The value to set (text for Edit fields, true/false for CheckBox)",
                    },
                },
                required: ["value"],
            },
        },
        {
            name: "uia_highlight_element",
            description:
                "Draw a colored highlight border around an element for visual confirmation. The highlight auto-clears after the specified duration (default 2000ms). Use this to verify you've located the correct element before generating code.",
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
                    duration: {
                        type: "number",
                        description: "Highlight duration in ms. Default: 2000.",
                    },
                    color: {
                        type: "string",
                        description: "Highlight color (e.g. 'red', '#FF0000'). Default: system highlight color.",
                    },
                },
                required: [],
            },
        },
        {
            name: "uia_dump_tree",
            description:
                "Get a comprehensive text dump of an element and all its descendants, including Type, Name, Value, LocalizedType, AutomationId, and ClassName for each node. Much more detailed than get_element_tree. Use this for deep exploration of complex UI structures.",
            inputSchema: {
                type: "object",
                properties: {
                    hwnd: {
                        type: "string",
                        description: "Hex HWND of the window to dump. If omitted, uses the focused element.",
                    },
                    maxDepth: {
                        type: "number",
                        description: "Maximum depth. Default: unlimited (full tree).",
                    },
                },
                required: [],
            },
        },
        {
            name: "uia_wait_element_not_exist",
            description:
                "Poll until an element matching the condition DISAPPEARS, or timeout. Returns {gone: true/false, elapsed: ms}. Use this to wait for loading spinners, modal dialogs, or progress bars to close before continuing.",
            inputSchema: {
                type: "object",
                properties: {
                    condition: {
                        type: "object",
                        description: "UIA condition for the element to wait to disappear",
                    },
                    hwnd: { type: "string" },
                    timeout: {
                        type: "number",
                        description: "Timeout in ms. Default: 5000.",
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
            name: "uia_element_exists",
            description:
                "Check if an element matching a condition exists WITHOUT throwing an error. Returns {exists: true/false, count: N, example: {...}}. If found, includes a summary of the first match. Use this as a safe alternative to find_element when the element might not be present.",
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
            name: "uia_get_element_from_path",
            description:
                "Navigate the UIA tree using path syntax. Supports comma-separated numeric paths (\"3,2\" = third child's second child), UIAViewer-encoded paths (\"bAx3\"), or condition arrays. Requires hwnd.",
            inputSchema: {
                type: "object",
                properties: {
                    hwnd: {
                        type: "string",
                        description: "Hex HWND of the window to navigate from",
                    },
                    path: {
                        type: "string",
                        description: "Navigation path: numeric \"3,2\", UIAViewer \"bAx3\", or JSON condition array",
                    },
                },
                required: ["hwnd", "path"],
            },
        },
        {
            name: "uia_get_root_element",
            description:
                "Get the desktop root element for cross-application UIA searches. Returns a summary of the root element. Use this as a starting point when you need to search across all applications (e.g., find a specific dialog that may belong to any process).",
            inputSchema: { type: "object", properties: {}, required: [] },
        },
        {
            name: "uia_element_from_chromium",
            description:
                "Get the Chromium content element (Chrome_RenderWidgetHostHWND1) from a Chrome/Edge/Brave window. Activates accessibility if needed. Returns full element info for the browser's rendered content. Use this when you need to inspect or automate web page content inside a browser.",
            inputSchema: {
                type: "object",
                properties: {
                    hwnd: {
                        type: "string",
                        description: "Hex HWND of the browser window",
                    },
                },
                required: ["hwnd"],
            },
        },
        {
            name: "uia_get_state_enums",
            description:
                "Get well-known UIA state value mappings (ToggleState, ExpandCollapseState, WindowVisualState, Orientation, etc.). Returns each state name mapped to its integer→string values. CRITICAL for code generation: without this, the LLM guesses whether ToggleState 1 means On or Off, producing broken conditional logic.",
            inputSchema: { type: "object", properties: {}, required: [] },
        },
        {
            name: "uia_manage_window",
            description:
                "Manage a window: Activate (bring to foreground), Minimize, Maximize, Restore, Close, Move (requires x,y), or Resize (requires width,height). Use this to control window lifecycle in automation workflows.",
            inputSchema: {
                type: "object",
                properties: {
                    hwnd: { type: "string", description: "Hex HWND of the target window" },
                    action: {
                        type: "string",
                        enum: ["Activate", "Minimize", "Maximize", "Restore", "Close", "Move", "Resize"],
                        description: "The window operation to perform",
                    },
                    x: { type: "number", description: "X coordinate for Move action" },
                    y: { type: "number", description: "Y coordinate for Move action" },
                    width: { type: "number", description: "Width for Resize action" },
                    height: { type: "number", description: "Height for Resize action" },
                },
                required: ["hwnd", "action"],
            },
        },
        {
            name: "uia_capture_screenshot",
            description:
                "Capture a screenshot of a window's client area and save as BMP. Returns the file path, width, and height. Use this to get visual context about the UI layout — the LLM can analyze the screenshot to understand spatial relationships, colors, and element positioning that are invisible to UIA text inspection.",
            inputSchema: {
                type: "object",
                properties: {
                    hwnd: { type: "string", description: "Hex HWND of the window to capture" },
                    filePath: { type: "string", description: "Optional output path. Default: %TEMP%/UIA_Screenshot_<timestamp>.bmp" },
                },
                required: ["hwnd"],
            },
        },
        {
            name: "uia_get_code_recipe",
            description:
                "Get a proven AHK v2 code template for a common automation scenario. Recipes: activate_window, find_and_click, menu_navigate, dialog_fill, tree_explore, grid_read, wait_and_click, combo_select, list_recipes. Use 'list_recipes' to see all available recipes.",
            inputSchema: {
                type: "object",
                properties: {
                    recipe: {
                        type: "string",
                        description: "Recipe name. Use 'list_recipes' to enumerate all options.",
                    },
                },
                required: ["recipe"],
            },
        },
        {
            name: "uia_get_element_code",
            description:
                "Generate a complete, runnable AHK v2 script that targets a specific UI element. Resolves the element via the standard locator (hwnd, condition, scope, matchMode, index), builds the condition string, infers the best action (Invoke, Click, SetValue, etc.), and returns a self-contained script with #Requires, #Include, Main(), and ExitApp. The generated code follows the same style as UIA_Inspector's Add Element button. Use this when you need a ready-to-run automation snippet for a specific button, field, or control.",
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
    ];
}
