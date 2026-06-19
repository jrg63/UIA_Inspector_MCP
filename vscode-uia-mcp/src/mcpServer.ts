import * as vscode from "vscode";
import * as path from "path";
import * as fs from "fs";
import * as os from "os";
import { AhkDaemonManager } from "./ahkDaemon";
import { TOOL_NAMES, ToolName, buildToolDefinitions } from "./toolDefinitions";

const SERVER_ID = "uia-inspector-mcp";
const SERVER_NAME = "UIA Inspector";

/**
 * Find a real Node.js executable.
 *
 * On Windows, process.execPath is the Electron binary (Code.exe), which can't
 * run arbitrary .js scripts.  We need the actual node binary.
 */
function findNodeExe(): string {
    // 1) VS Code's bundled node (Windows: alongside Code.exe)
    const execDir = path.dirname(process.execPath);
    const bundled = process.platform === "win32"
        ? path.join(execDir, "node.exe")
        : path.join(execDir, "node");
    if (fs.existsSync(bundled)) {
        return bundled;
    }

    // 2) Electron's built-in Node (ships as a helper binary in some versions)
    //    e.g. alongside the framework .dll on macOS
    if (process.platform === "darwin") {
        const frameworkNode = path.join(
            execDir,
            "..",
            "Frameworks",
            "Electron Framework.framework",
            "Helpers",
            "node"
        );
        if (fs.existsSync(frameworkNode)) {
            return frameworkNode;
        }
    }

    // 3) "node" from PATH — the common case for Windows dev machines
    return "node";
}

const CODE_GEN_INSTRUCTIONS = `## AHK v2 UIA Automation Code Generation

When the user asks you to generate AHK v2 code to automate a Windows desktop UI, follow these rules.

### Library & Setup
\`\`\`ahk
#Requires AutoHotkey v2.0.2+
#Include <UIA>  ; Descolada UIA-v2 library

; Activate the target window
WinActivate("Window Title ahk_exe target.exe")
WinWaitActive("Window Title ahk_exe target.exe")

; Get the window UIA element
winEl := UIA.ElementFromHandle("Window Title ahk_exe target.exe")
\`\`\`

### Condition Format
Use CamelCase UIA property names in object literals:
\`\`\`ahk
{Type: "Button", Name: "OK"}
{AutomationId: "submitBtn"}
{Type: "Edit", ClassName: "Edit"}
{Type: "CheckBox", Name: "Enable logging"}
\`\`\`

Valid Type values: Button, Edit, Text, CheckBox, RadioButton, ComboBox, List, ListItem, TreeItem, Pane, Group, Document, Image, Hyperlink, Window, MenuItem, Tab, TabItem, DataItem, ToolBar, StatusBar, Custom, SplitButton, Thumb, Header, HeaderItem, Table, DataGrid, TitleBar, MenuBar, ScrollBar, Separator, SemanticZoom, AppBar.

### FindFirst / FindAll
\`\`\`ahk
; Find the first match (throws if not found)
el := winEl.FindFirst({Type: "Button", Name: "OK"})

; Find all matches, pick the Nth
buttons := winEl.FindAll({Type: "Button"})
third := buttons[3]
\`\`\`

### MatchMode & Scope
\`\`\`ahk
; MatchMode: "Exact" (default), "Contains", "StartsWith", "EndsWith"
el := winEl.FindFirst({Name: "Save"}, "Contains")

; Scope: UIA.TreeScope.Descendants (default), .Children, .Subtree, .Element
el := winEl.FindFirst({Type: "Button"},, UIA.TreeScope.Children)
\`\`\`

### WaitElement (with timeout)
\`\`\`ahk
; Wait up to 5 seconds for an element to appear
el := winEl.WaitElement({Type: "Window", Name: "Save As"},, 5000)
\`\`\`

### Anchor Chaining
\`\`\`ahk
; Find a stable ancestor first, then search within it
pane := winEl.FindFirst({Type: "Pane", AutomationId: "mainPanel"})
btn := pane.FindFirst({Type: "Button", Name: "OK"})
\`\`\`

### Actions
\`\`\`ahk
el.Click()                  ; Left click
el.MouseClick("right")       ; Right click
el.ControlClick()            ; ControlClick (works on background windows)
el.SetValue("new text")      ; Type text into an Edit
el.Invoke()                  ; Invoke pattern (buttons, hyperlinks)
el.Toggle()                  ; Toggle pattern (checkboxes, radio)
el.Expand()                  ; ExpandCollapse pattern
el.Collapse()                ; ExpandCollapse pattern
el.Select()                  ; SelectionItem pattern
el.ScrollIntoView()          ; Scroll into view
el.SetFocus()                ; Set keyboard focus
el.Highlight()               ; Draw colored overlay (visual debugging)
\`\`\`

### MCP Discovery Tools (use these to explore UI before generating code)
When exploring an unfamiliar application, use these MCP tools for interactive discovery:

- \`uia_get_type_catalog\` — get all valid UIA type names and IDs
- \`uia_get_pattern_catalog\` — get all UIA patterns with their methods/properties
- \`uia_perform_action\` — interact with elements to verify behavior (Invoke buttons, Toggle checkboxes, SetValue on edits, etc.)
- \`uia_highlight_element\` — visually confirm you found the right element
- \`uia_dump_tree\` — comprehensive tree dump (more detail than get_element_tree)
- \`uia_element_exists\` — safe check if an element is present (no throw)
- \`uia_wait_element_not_exist\` — wait for dialogs/spinners to close

Example workflow: call \`uia_perform_action\` with action="Invoke" to click through a menu, then \`list_windows\` to discover new windows that appear, then \`get_element_tree\` on the new window to explore its structure. This verifies the UI flow before you generate AHK code.

### Wait for Disappearance
\`\`\`ahk
; Wait for a dialog or loading spinner to close
winEl.WaitElementNotExist({Type: "Window", Name: "Loading..."}, 10000)
\`\`\`

### Safe Existence Check
\`\`\`ahk
; Non-throwing check — returns 0 if not found instead of throwing
el := winEl.ElementExist({Type: "Button", Name: "OptionalButton"})
if el
    el.Click()
\`\`\`

### DumpAll for Deep Exploration
\`\`\`ahk
; Dump the entire tree to a string for analysis
dump := winEl.DumpAll()
FileAppend(dump, "tree_dump.txt")
\`\`\`

### Error Handling
\`\`\`ahk
try {
    el := winEl.WaitElement({Type: "Button", Name: "Submit"},, 10000)
    el.Click()
    Sleep(200)
} catch as err {
    MsgBox("Failed: " err.Message)
}
\`\`\`

### Multi-Window Sequences
\`\`\`ahk
; Click a button that opens a new window
winEl.FindFirst({Type: "Button", Name: "Settings..."}).Click()
Sleep(500)

; Wait for and interact with the new window
settingsWin := UIA.ElementFromHandle("Settings ahk_exe target.exe")
settingsWin.WaitElement({Type: "CheckBox", Name: "Enable"},, 3000).Toggle()
\`\`\`
### Win32 / VB6 Menus
Win32 and VB6 applications (class \`#32768\`, \`ThunderRT6*\`, etc.) use native Windows menus. Submenus appear as **separate popup windows** (\`ahk_class #32768\`) — they are NOT children of the parent MenuItem and cannot be found with FindFirst on the parent window.

\`\`\`ahk
; Expand the top-level menu
featuresMenu := winEl.FindFirst({Type: "MenuItem", Name: "Features"})
featuresMenu.Expand()
Sleep(200)

; The submenu is a separate popup window — find it by class
popup := UIA.ElementFromHandle("ahk_class #32768")
; Or find the parent #32768 window via its title matching the menu name
popup := UIA.ElementFromHandle("Features ahk_class #32768")

; Now find and invoke the submenu item
subItem := popup.FindFirst({Type: "MenuItem", Name: "Reports"})
subItem.Invoke()
\`\`\`

For simple menu navigation, Send the accelerator key (e.g. \`Send("{F7}")\`) or use \`Send("!f r")\` for Alt+F then r (where \`r\` is the AccessKey shown in the UIA inspection).
### Best Practices
1. Always use WinActivate/WinWaitActive before UIA interaction
2. Prefer AutomationId over Name (AutomationId is usually stable across app versions)
3. Use WaitElement instead of FindFirst when the UI may lag (dialogs, loading screens)
4. Add Sleep(100-500) between actions to let the UI settle
5. Chain from stable ancestors when direct FindFirst matches too many elements
6. Use FindAll[N] with explicit index when N sibling elements share the same condition
7. Always include try/catch for production scripts
`;

export class UiaMcpServer {
    constructor(
        private daemon: AhkDaemonManager,
        private output: vscode.OutputChannel,
        private context: vscode.ExtensionContext,
        private debugChannel?: vscode.OutputChannel
    ) {}

    /**
     * Register via the VS Code MCP API using a stdio bridge.
     * VS Code spawns `node out/mcpBridge.js` which forwards MCP JSON-RPC
     * from stdin/stdout to our AHK engine over TCP.
     */
    register(context: vscode.ExtensionContext): void {
        this.output.appendLine("Registering UIA MCP server...");

        try {
            const api = (vscode as any).lm;
            if (!api || typeof api.registerMcpServerDefinitionProvider !== "function") {
                this.output.appendLine(
                    "lm.registerMcpServerDefinitionProvider not available — VS Code too old."
                );
                return;
            }

            const bridgePath = vscode.Uri.joinPath(
                context.extensionUri,
                "out",
                "mcpBridge.js"
            );

            const nodeExe = findNodeExe();
            this.output.appendLine(`MCP bridge node: ${nodeExe}`);
            this.output.appendLine(`MCP bridge script: ${bridgePath.fsPath}`);

            // McpStdioServerDefinition may be on vscode or vscode.lm depending
            // on VS Code version.  The constructor requires (label, command,
            // args?, env?, version?) — NOT property assignment.
            const McpDefClass: any =
                (vscode as any).McpStdioServerDefinition ??
                (vscode as any).lm?.McpStdioServerDefinition;

            // Cache the definition — VS Code may call provideMcpServerDefinitions
            // multiple times.  Creating a new definition each time triggers
            // tool re-registration, which causes "tools disabled" after a
            // few calls.  We create it once and return the same instance.
            let cachedDef: any = null;

            let callCount = 0;
            const provider = {
                provideMcpServerDefinitions: (_token: vscode.CancellationToken) => {
                    callCount++;
                    const ts = new Date().toISOString();
                    this.debugChannel?.appendLine(`[${ts}] provideMcpServerDefinitions called (#${callCount})`);
                    if (!McpDefClass) {
                        this.debugChannel?.appendLine(`[${ts}] McpDefClass not found — returning []`);
                        return [];
                    }
                    if (!cachedDef) {
                        const cfg = vscode.workspace.getConfiguration("uia-mcp");
                        const logLevel = cfg.get<string>("logLevel", "info") ?? "info";
                        const port = cfg.get<number>("enginePort", 9876) ?? 9876;
                        this.debugChannel?.appendLine(`[${ts}] Creating new McpStdioServerDefinition (port=${port}, logLevel=${logLevel})`);
                        cachedDef = new McpDefClass(
                            "UIA Inspector",
                            nodeExe,
                            [bridgePath.fsPath],
                            {
                                UIA_MCP_PORT: String(port),
                                UIA_MCP_LOG_LEVEL: logLevel,
                                UIA_MCP_LOG_FILE: path.join(os.tmpdir(), "UIA_MCP_Bridge.log"),
                            }
                        );
                        this.output.appendLine("MCP server definition created (cached).");
                    } else {
                        this.debugChannel?.appendLine(`[${ts}] Returning cached definition`);
                    }
                    return [cachedDef];
                },
            };

            context.subscriptions.push(
                api.registerMcpServerDefinitionProvider(SERVER_ID, provider)
            );

            this.output.appendLine(
                `MCP server "${SERVER_ID}" registered via stdio bridge.`
            );
        } catch (err: any) {
            this.output.appendLine(
                `MCP registration failed: ${err.message}`
            );
        }
    }

    /**
     * Define all 15 MCP tools with their schemas and handlers.
     * Delegates to the shared toolDefinitions module (no vscode dependency).
     */
    private getToolDefinitions(): any[] {
        return buildToolDefinitions();
    }

    dispose(): void {
        this.output.appendLine("Disposing UIA MCP server.");
    }
}
