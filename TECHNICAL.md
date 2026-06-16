# UIA Inspector MCP — Technical Reference

## Architecture Overview

The UIA Inspector MCP server is a **two-process system** that bridges VS Code's MCP (Model Context Protocol) API to the Windows UI Automation framework:

```
┌──────────────────────────────────────────────────────────────────┐
│  VS Code Process                                                  │
│  ┌─────────────────────┐     ┌─────────────────────────────┐     │
│  │  MCP Client (LLM)   │────▶│  UiaMcpServer                │     │
│  │  (Copilot/Chat)     │     │  • Tool definitions           │     │
│  │                     │     │  • Schema validation          │     │
│  │                     │     │  • Code-gen instructions      │     │
│  │                     │     │  • handleToolCall() bridge    │     │
│  └─────────────────────┘     └──────────┬──────────────────┘     │
│                                         │                        │
│                              ┌──────────▼──────────────────┐     │
│                              │  AhkDaemonManager            │     │
│                              │  • Process lifecycle         │     │
│                              │  • State machine (5 states)  │     │
│                              │  • TCP client to engine      │     │
│                              │  • Health check / idle mgmt  │     │
│                              │  • Path auto-detection       │     │
│                              └──────────┬──────────────────┘     │
└─────────────────────────────────────────┼────────────────────────┘
                                          │ TCP localhost:9876
                                          │ JSON-RPC 2.0 (newline-delimited)
┌─────────────────────────────────────────▼────────────────────────┐
│  AHK Process (AutoHotkey64.exe)                                   │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │  UIA_MCP_Engine.ahk                                       │    │
│  │  • TCP listener (AHK socket)                              │    │
│  │  • JSON-RPC dispatcher → 15 tool handlers                 │    │
│  │  • UIA library bindings (Descolada UIA-v2)                │    │
│  │  • cJSON for serialization                                │    │
│  │  • Idle timeout + port-file signaling                     │    │
│  └──────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

The VS Code extension never touches UIA directly — it sends JSON-RPC commands to the AHK engine, which performs the actual Windows UI Automation calls and returns results.

---

## Project File Layout

```
UIA_Inspector_MCP/
├── UIA_MCP_Engine.ahk          Headless AHK JSON-RPC daemon
├── lib/
│   └── cJSON.ahk               JSON serialize/parse (only dependency)
├── tests/
│   ├── test_engine.ps1          PowerShell integration test harness
│   └── test_engine_internals.ahk AHK unit tests for engine helpers
└── vscode-uia-mcp/
    ├── package.json             Extension manifest + test scripts
    ├── tsconfig.json            TypeScript config (Node16, ES2022)
    ├── jest.config.js           Jest config (ts-jest, 90% coverage threshold)
    ├── .vscodeignore            Files excluded from VSIX package
    └── src/
        ├── extension.ts          Activation entry point
        ├── ahkDaemon.ts          Process manager + state machine
        ├── mcpServer.ts          MCP provider + bridge + CODE_GEN_INSTRUCTIONS
        ├── pathResolver.ts       Pure path-detection logic (testable)
        ├── toolDefinitions.ts    Pure tool schemas + TOOL_NAMES (testable)
        └── __tests__/
            ├── daemon.test.ts    58 tests: path resolver, state machine, JSON-RPC
            └── mcpServer.test.ts Tests: tool schemas, validation, naming
```

### Module Dependency Graph

```
extension.ts ──▶ AhkDaemonManager ──▶ pathResolver.ts   (pure, testable)
     │                  │
     ▼                  ▼
  UiaMcpServer ──▶ handleToolCall() ──▶ daemon.sendCommand() ──TCP──▶ AHK engine
     │
     ▼
  toolDefinitions.ts  (pure, testable — no vscode dependency)
```

The two modules with `(pure, testable)` tags have zero `vscode` dependencies. They are the only modules covered by Jest unit tests — the vscode-dependent modules (`ahkDaemon.ts`, `mcpServer.ts`, `extension.ts`) are tested via PowerShell integration tests against a live engine.

---

## AHK Engine (`UIA_MCP_Engine.ahk`)

### Startup Sequence

1. Parse `--port` and `--idle-timeout` from command-line arguments
2. Include `<UIA>` (Descolada UIA-v2 library) and `<UIA_Inspector\cjson>` (JSON library)
3. Create a TCP listener on `127.0.0.1:<port>`
4. Write a port-file to `%TEMP%\UIA_MCP_Engine.port` (signals readiness to the extension)
5. Enter accept loop — each connection handled synchronously

### JSON-RPC Protocol

Newline-delimited JSON-RPC 2.0 over raw TCP. Every request/response is exactly one line of JSON followed by `\n`.

```json
{"jsonrpc":"2.0","method":"find_element","params":{"condition":{"Type":"Button","Name":"OK"},"hwnd":"0x12345"},"id":42}
```

```json
{"jsonrpc":"2.0","result":{"Type":"Button","Name":"OK","AutomationId":"okBtn",...},"id":42}
```

```json
{"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"},"id":42}
```

Standard JSON-RPC error codes used:
| Code | Meaning |
|------|---------|
| `-32700` | Parse error (invalid JSON) |
| `-32601` | Method not found |
| `-32602` | Invalid params |
| `-32000` | Engine-level error (UIA failure, etc.) |

### Idle Timeout

The engine tracks time since its last request. When the idle timeout expires (default 300s), it:
1. Deletes the port-file
2. Closes the TCP listener
3. Calls `ExitApp`

The extension can also send a `shutdown` method to gracefully stop the engine.

### UIA Helper Functions

| Function | Purpose |
|----------|---------|
| `_MakeCacheRequest()` | Pre-loads 35 UIA properties (22 element + 13 pattern-availability flags) into a `CacheRequest` with `Subtree` scope — used for tree walks to avoid per-element COM round-trips |
| `_ElementToMap(el)` | Converts a UIA element into a flat `Map` of ~16 key properties (Type, Name, AutomationId, ClassName, IsEnabled, BoundingRect, etc.) |
| `_ElementSummary(el)` | Lightweight version of `_ElementToMap` — only 6 fields (Type, Name, AutomationId, ClassName, IsEnabled, IsOffscreen) |
| `_BuildCondition(condObj)` | Converts an AHK condition object `{Type:"Button", Name:"OK"}` into a UIA `Map(propertyId → value)` using property ID mappings |
| `_GetPatterns(el)` | Enumerates available UIA patterns (Invoke, Toggle, ExpandCollapse, Value, SelectionItem, Selection, Scroll) with their current states |
| `_GetAncestorChain(el)` | Walks from an element up to the desktop root via `TreeWalkerTrue`, returning root-first array |
| `_DetermineAction(el)` | Heuristic to infer the best action: `Invoke()` > `Toggle()` > `Expand()`/`Collapse()` > `SetValue("")` > `Select()` > `Click()` |
| `_IsBrowserProcess(pid)` | Detects Chrome/Edge/Opera/Brave/Firefox processes (browsers have non-standard UIA trees) |

---

## VS Code Extension

### `extension.ts` — Activation

1. Creates an `OutputChannel` named `"UIA MCP"`
2. Instantiates `AhkDaemonManager` (manages the AHK child process)
3. Instantiates `UiaMcpServer` (registers MCP tools)
4. Registers four VS Code commands: `startEngine`, `stopEngine`, `restartEngine`, `showEngineStatus`
5. Creates a status bar item that reflects engine state:
   - ▶ running | ⟳ starting | ■ stopped | ⚠ error/admin
6. Auto-launches the engine if `uia-mcp.autoLaunch` is `true` (default)
7. Registers the MCP server via the VS Code `lm` API

### `ahkDaemon.ts` — Daemon Manager

**State Machine:**

```
                    ┌──────────┐
          ┌────────▶│  stopped │◀────────┐
          │         └────┬─────┘         │
          │              │ start()       │
          │         ┌────▼─────┐         │
          │         │ starting │─────────┤
          │         └────┬─────┘         │
          │         ┌────┼─────┐         │
          │         ▼    │     ▼         │
          │    ┌───────┐ │ ┌───────┐     │
          │    │ error │ │ │running│     │
          │    └───┬───┘ │ └───┬───┘     │
          │        │     │     │         │
          │        └─────┼─────┘         │
          │              │ stop() / exit │
          │              ▼               │
          │    ┌──────────────┐          │
          │    │ admin_needed │──────────┘
          │    └──────────────┘
          └────────────────────┘
```

**Key behaviors:**
- Starts AHK as a hidden child process (`windowsHide: true`)
- Pipes stdout/stderr to the VS Code output channel
- Waits for the port-file to appear (up to 15s), then sends a `ping` to confirm readiness
- Runs periodic health-check pings while running
- Sends JSON-RPC commands over TCP with a 30s timeout per request
- Tracks `pendingRequests` for idle management (currently the engine handles its own idle timeout)

### `mcpServer.ts` — MCP Server

Registers with VS Code's `vscode.lm.registerMcpServerDefinitionProvider` API. The provider returns:

- **Server ID**: `uia-inspector-mcp`
- **Server name**: `UIA Inspector`
- **15 tool definitions** (schemas + descriptions)
- **Code generation instructions** (`CODE_GEN_INSTRUCTIONS`) — a comprehensive prompt teaching the LLM how to generate AHK v2 automation code. Covers library setup, condition format, FindFirst/FindAll syntax, MatchMode/Scope, WaitElement, anchor chaining, all available actions, error handling patterns, and 7 best practices.

The `handleToolCall()` bridge validates the tool name against `TOOL_NAMES`, then forwards to `daemon.sendCommand()`.

### `pathResolver.ts` — Path Detection (testable)

Auto-detects `AutoHotkey64.exe` by checking (in order):
1. User-configured `uia-mcp.ahkEnginePath`
2. `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`
3. `C:\Program Files\AutoHotkey\AutoHotkey64.exe`
4. `%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe`

Auto-detects `UIA_MCP_Engine.ahk` by checking:
1. User-configured `uia-mcp.engineScriptPath`
2. Each open workspace folder
3. Extension install directory

Uses an injectable `fsExists` parameter so tests can supply a mock without touching the filesystem.

### `toolDefinitions.ts` — Tool Schemas (testable)

Contains `TOOL_NAMES` (the 15-method registry), the `ToolName` type, `ToolDefinition` interface, and `buildToolDefinitions()` which returns the full MCP tool schema array. Each tool definition includes JSON Schema `inputSchema` with typed `properties`, `required` fields, and `enum` constraints.

---

## Tool Reference

| # | Tool Name | Required Params | Optional Params |
|---|-----------|----------------|-----------------|
| 1 | `inspect_element_at_cursor` | — | — |
| 2 | `get_focused_element` | — | — |
| 3 | `find_element` | `condition` | `hwnd`, `scope`, `matchMode`, `index` |
| 4 | `find_all_elements` | `condition` | `hwnd`, `scope`, `matchMode` |
| 5 | `get_element_tree` | `hwnd` | `maxDepth` |
| 6 | `get_ancestor_chain` | — | `hwnd`, `condition`, `scope`, `matchMode`, `index` |
| 7 | `get_element_properties` | — | `hwnd`, `condition`, `scope`, `matchMode`, `index` |
| 8 | `get_element_patterns` | — | `hwnd`, `condition`, `scope`, `matchMode`, `index` |
| 9 | `list_windows` | — | `filter` |
| 10 | `get_window_info` | `hwnd` | — |
| 11 | `check_match_count` | `condition` | `hwnd`, `scope`, `matchMode` |
| 12 | `get_child_elements` | — | `hwnd`, `condition`, `scope`, `matchMode`, `index` |
| 13 | `get_bounding_rect` | — | `hwnd`, `condition`, `scope`, `matchMode`, `index` |
| 14 | `wait_for_element` | `condition` | `hwnd`, `timeout`, `scope`, `matchMode` |
| 15 | `get_element_at_point` | `x`, `y` | — |

**Shared optional parameters:**
- `scope`: `"Descendants"` (default), `"Children"`, `"Subtree"`, `"Element"`
- `matchMode`: `"Exact"` (default), `"Contains"`, `"StartsWith"`, `"EndsWith"`
- `index`: 1-based, used when multiple elements match a condition

---

## Testing

### Unit Tests (Jest / ts-jest)

**58 tests, 100% coverage** on testable modules. Run with `npm test` from `vscode-uia-mcp/`.

| Module | Tests | What's covered |
|--------|-------|----------------|
| `pathResolver.ts` | 8 | `findAhkExe` (user path, candidate fallback, missing), `findEngineScript` (user, workspace, extension, priority), `getPortFile` |
| `toolDefinitions.ts` | 20 | TOOL_NAMES registry (15 tools, no dupes, naming convention), tool definitions (schemas, required fields, enum values), specific tool constraints |
| State machine | 4 | All valid/invalid transitions, reachability, outgoing transitions for every state |
| JSON-RPC | 8 | Parse success/error/notification, request construction |
| Request construction | 3 | Valid request shape, params, field presence |

The tests use the injectable `fsExists` parameter on `findAhkExe`/`findEngineScript` to achieve full determinism without filesystem mocking libraries.

### Integration Tests (PowerShell + AHK)

- `tests/test_engine.ps1` — starts the engine, sends JSON-RPC commands, validates responses. Covers: sanity (ping, parse errors, method-not-found), windows, find, tree, focus, cursor, wait, point, elevation detection.
- `tests/test_engine_internals.ahk` — unit tests for AHK helper functions (`_EscapeStr`, `_Join`, `_BuildCondition`, `_ElementToMap`, `_GetPatterns`, etc.) using a simple `Assert`/`AssertEqual` framework. Exits with code 1 on failure.

These tests require a real Windows desktop with AutoHotkey v2 installed — they are not CI-runnable in standard cloud runners.

---

## Configuration Reference (`uia-mcp.*`)

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ahkEnginePath` | string | `""` | Path to `AutoHotkey64.exe`. Auto-detected if empty. |
| `engineScriptPath` | string | `""` | Path to `UIA_MCP_Engine.ahk`. Uses bundled copy if empty. |
| `enginePort` | number | `9876` | TCP port for JSON-RPC communication. |
| `autoLaunch` | boolean | `true` | Start the engine automatically when VS Code opens. |
| `engineIdleTimeout` | number | `300` | Seconds of inactivity before the engine shuts down. |

---

## Design Decisions

1. **Two-process architecture**: UIA requires a Windows message pump and COM apartment — running in a separate AHK process avoids blocking the VS Code extension host and isolates UIA crashes.

2. **JSON-RPC over raw TCP**: Deliberately simple protocol. No HTTP overhead, no WebSocket negotiation. Newline-delimited JSON frames are trivial to parse on both sides.

3. **Port-file readiness signal**: Instead of polling TCP `connect()`, the engine writes a sentinel file when the listener is ready. The extension waits for the file, then sends a `ping` for final confirmation.

4. **Pure logic extraction**: Path detection and tool definitions live in modules with no `vscode` dependency. This makes them unit-testable in plain Node.js/Jest without mocking the VS Code API.

5. **Code-gen instructions embedded in the server**: The LLM receives AHK v2 coding patterns directly from the MCP server definition, not from external documentation. This ensures the LLM always has accurate, version-matched code samples.

6. **Idle timeout in the engine, not the extension**: If VS Code crashes, the engine still shuts down on its own. The port-file deletion on exit prevents stale port-file issues on restart.
