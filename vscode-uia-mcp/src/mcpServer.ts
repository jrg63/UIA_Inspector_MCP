import * as vscode from "vscode";
import { AhkDaemonManager } from "./ahkDaemon";
import { TOOL_NAMES, ToolName, buildToolDefinitions } from "./toolDefinitions";

const SERVER_ID = "uia-inspector-mcp";
const SERVER_NAME = "UIA Inspector";

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
        private context: vscode.ExtensionContext
    ) {}

    /**
     * Register the MCP server with VS Code.
     * Uses the vscode.lm.registerMcpServerDefinitionProvider API if available,
     * or falls back to the lm.tools contribution point.
     */
    register(context: vscode.ExtensionContext): void {
        this.output.appendLine("Registering UIA MCP server...");

        // Check for VS Code MCP API availability
        const api = (vscode as any).lm;
        if (api && typeof api.registerMcpServerDefinitionProvider === "function") {
            this.registerViaApi(context);
        } else {
            this.output.appendLine(
                "MCP API not available — using tool-based registration."
            );
            this.registerToolsDirectly(context);
        }
    }

    /**
     * Register via the VS Code MCP server definition provider API.
     */
    private registerViaApi(context: vscode.ExtensionContext): void {
        const api = (vscode as any).lm;

        const provider = {
            provideMcpServerDefinitions: () => {
                return [
                    {
                        id: SERVER_ID,
                        name: SERVER_NAME,
                        description:
                            "Windows UI Automation inspector — interrogate desktop UIs, find selectors, generate AHK v2 code",
                        tools: this.getToolDefinitions(),
                        instructions: CODE_GEN_INSTRUCTIONS,
                        // Bridge: when a tool is invoked, call our handler
                        invokeTool: async (name: string, params: Record<string, any>) => {
                            return this.handleToolCall(name, params);
                        },
                    },
                ];
            },
        };

        context.subscriptions.push(
            api.registerMcpServerDefinitionProvider(provider)
        );

        this.output.appendLine(
            `MCP server "${SERVER_ID}" registered via API.`
        );
    }

    /**
     * Handle a tool invocation from the LLM via MCP.
     * Bridges the call to the AHK engine daemon.
     */
    async handleToolCall(
        toolName: string,
        params: Record<string, any>
    ): Promise<any> {
        this.output.appendLine(
            `Tool call: ${toolName}(${JSON.stringify(params)})`
        );

        // Validate tool name
        if (!(TOOL_NAMES as readonly string[]).includes(toolName)) {
            throw new Error(`Unknown tool: ${toolName}`);
        }

        // Forward to the AHK engine
        return this.daemon.sendCommand(toolName, params);
    }

    /**
     * Fallback: register LM tools directly for Copilot Chat.
     */
    private registerToolsDirectly(context: vscode.ExtensionContext): void {
        this.output.appendLine(
            "Direct tool registration not fully implemented — MCP API is the primary path."
        );
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
