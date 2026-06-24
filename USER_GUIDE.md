# UIA Inspector MCP — Installation & User Guide

## What It Does

UIA Inspector MCP lets AI coding assistants (GitHub Copilot, Claude, etc.) **inspect and interact with any Windows desktop application** through the UI Automation framework. The LLM can:

- See what windows are open
- Inspect buttons, text fields, menus, trees, and any UI element
- Find elements by type, name, automation ID, or class
- Walk the UI element tree
- Get exact coordinates and properties
- Generate ready-to-run AutoHotkey v2 automation code

This is the equivalent of giving an LLM "eyes" on your Windows desktop.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Windows 10 or 11** | UI Automation is a Windows-only framework |
| **VS Code** | Version 1.90 or later |
| **AutoHotkey v2** | Version 2.0.2 or later — [download from autohotkey.com](https://www.autohotkey.com/) |
| **UIA-v2 library** | Descolada's UIA library for AHK v2 — installed via AHK's package manager or manually |

### Installing AutoHotkey v2

1. Download the installer from https://www.autohotkey.com/
2. Choose the **v2** installer (not v1.1)
3. Install to the default location (`C:\Program Files\AutoHotkey\v2\`)

### Installing the UIA-v2 Library

The easiest method is to use **AHKpm** (the AHK package manager):

```powershell
# If you don't have AHKpm, install it first:
iwr -Uri https://raw.githubusercontent.com/nijikokun/ahkpm/main/install.ps1 | iex

# Then install the UIA library:
ahkpm install descolada/UIA-v2
```

Alternatively, download manually from https://github.com/Descolada/UIA-v2 and place `UIA.ahk` in your AHK Lib folder (typically `%USERPROFILE%\Documents\AutoHotkey\Lib\`).

The engine also needs the cJSON library — it's bundled in this project's `lib/` folder. Ensure `lib/cJSON.ahk` is accessible under your AHK Lib path as `Lib\UIA_Inspector\cJSON.ahk`. The easiest way is to symlink or copy the `lib/` folder from this project into your AHK Lib directory.

---

## Installation

### Option 1: From Source (Development)

```powershell
# 1. Clone the repository
git clone https://github.com/jrg63/UIA_Inspector.git
cd UIA_Inspector

# 2. Install VS Code extension dependencies
cd vscode-uia-mcp
npm install

# 3. Compile TypeScript
npm run compile

# 4. Run tests to verify everything works
npm test
```

### Option 2: Install as a VS Code Extension

If a `.vsix` package is available:

```powershell
code --install-extension vscode-uia-mcp-0.1.0.vsix
```

Or build it yourself:

```powershell
cd vscode-uia-mcp
npm install -g @vscode/vsce
vsce package
code --install-extension vscode-uia-mcp-0.1.0.vsix
```

---

## Setting Up the AHK Library Path

The engine needs to find `cJSON.ahk` via AHK's `#Include` system. The include directive is:

```ahk
#Include <UIA_Inspector\cjson>
```

This means AHK looks for the file at:
```
<AHK Lib folder>\UIA_Inspector\cJSON.ahk
```

The AHK Lib folder is typically one of:
- `%USERPROFILE%\Documents\AutoHotkey\Lib\`
- The folder containing `AutoHotkey64.exe`

**To set this up:**

```powershell
# Create the UIA_Inspector subfolder in your AHK Lib
$ahkLib = "$env:USERPROFILE\Documents\AutoHotkey\Lib"
New-Item -ItemType Directory -Force "$ahkLib\UIA_Inspector"

# Copy cJSON.ahk there
Copy-Item ".\lib\cJSON.ahk" "$ahkLib\UIA_Inspector\cJSON.ahk"
```

The same applies to `UIA.ahk` — it must be findable via `#Include <UIA>`.

---

## Configuration

All settings are in VS Code under **File → Preferences → Settings** → search "uia-mcp":

| Setting | Default | What It Does |
|---------|---------|--------------|
| `uia-mcp.autoLaunch` | `true` | Start the engine when VS Code opens |
| `uia-mcp.enginePort` | `9876` | TCP port (change only if port conflict) |
| `uia-mcp.ahkEnginePath` | `""` | Path to `AutoHotkey64.exe` (auto-detect if blank) |
| `uia-mcp.engineScriptPath` | `""` | Path to `UIA_MCP_Engine.ahk` (bundled if blank) |
| `uia-mcp.engineIdleTimeout` | `300` | Seconds before idle engine auto-shuts-down |

In most cases the defaults work. You only need to change `ahkEnginePath` if AHK is installed in a non-standard location.

---

## Verifying It Works

### 1. Check the Status Bar

After VS Code starts, look at the right side of the status bar. You should see:

```
▶ UIA MCP
```

If you see `■ UIA MCP` (stopped) or `⚠ UIA MCP` (error), click it and select **Start UIA MCP Engine**.

### 2. Check the Output Panel

Open **View → Output** (Ctrl+Shift+U), then select **UIA MCP** from the dropdown. You should see:

```
UIA Inspector MCP extension activating...
Starting AHK UIA engine...
AHK: C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe
Script: ...\UIA_MCP_Engine.ahk
Port: 9876
Engine started successfully.
Registering UIA MCP server...
MCP server "uia-inspector-mcp" registered via API.
```

### 3. Run the Integration Tests

```powershell
cd tests
.\test_engine.ps1
```

You should see a series of `PASS` results for sanity, window, find, tree, focus, and point tests.

### 4. Ask Copilot to Use It

In Copilot Chat, ask:

> *"List all open windows on my desktop"*

Copilot should invoke the `list_windows` tool and return the results. If it does, the MCP server is working.

---

## How to Use with an LLM

Once the engine is running, any MCP-aware LLM in VS Code can call the 15 inspection tools. Here are typical workflows:

### Inspect an Element You're Pointing At

> *"What element is under my mouse cursor?"*

The LLM calls `inspect_element_at_cursor` and returns the element type, name, properties, patterns, and a ready-to-use AHK condition string.

### Find a Specific Button

> *"Find the 'Save' button in Notepad and tell me its AutomationId"*

The LLM calls `find_element` with `{Type: "Button", Name: "Save"}` on the Notepad window HWND.

### Explore a Window's Structure

> *"Show me the UI tree of the current window up to depth 3"*

The LLM calls `get_element_tree` and returns a formatted tree showing all elements and their relationships.

### Generate Automation Code

> *"Write AHK code to click the OK button in the Save As dialog"*

The LLM uses `find_element` to locate the button, then generates code like:

```ahk
#Requires AutoHotkey v2.0.2+
#Include <UIA>

WinActivate("Save As ahk_exe notepad.exe")
WinWaitActive("Save As ahk_exe notepad.exe")
winEl := UIA.ElementFromHandle("Save As ahk_exe notepad.exe")
winEl.FindFirst({Type: "Button", Name: "OK"}).Click()
```

### Wait for a Dialog to Appear

> *"Wait for the Export dialog to open and then click Export"*

The LLM calls `wait_for_element` with `{Type: "Window", Name: "Export"}` and a timeout, then chains to `find_element` for the button.

### Debug a Selector

> *"How many edit fields are in this window?"*

The LLM calls `check_match_count` to verify a selector's specificity before using `find_element`.

### Check Element Position

> *"What's the bounding rectangle of the Submit button?"*

The LLM calls `get_bounding_rect` to get `{left, top, right, bottom}` coordinates.

---

## Troubleshooting

### Status bar shows "⚠ UIA MCP" (error)

1. Open the **UIA MCP** output panel (View → Output → UIA MCP)
2. Look for error messages:
   - `AutoHotkey64.exe not found` → Install AHK v2 or set `uia-mcp.ahkEnginePath`
   - `UIA_MCP_Engine.ahk not found` → Set `uia-mcp.engineScriptPath`
   - `Engine exited with code 1` → The AHK script crashed — check for missing `#Include` files (UIA.ahk or cJSON.ahk)

### Status bar shows "⚠ UIA MCP Admin"

The target application is running as Administrator but VS Code is not. Either:
- Restart VS Code as Administrator, or
- Use the MCP tools only on non-elevated applications

### Engine starts but LLM doesn't use the tools

Make sure:
1. The MCP server registered successfully (check output panel)
2. Your LLM/Copilot supports MCP tool calling (requires VS Code 1.90+)
3. The engine status bar shows `▶ UIA MCP`

### "Port 9876 already in use"

Another instance of the engine is running. Either:
- Kill it via Task Manager, or
- Change `uia-mcp.enginePort` to a different port

### Tests fail with "UIA.ahk not found"

The UIA-v2 library is not in your AHK Lib folder. Install it via AHKpm or manually place `UIA.ahk` in `%USERPROFILE%\Documents\AutoHotkey\Lib\`.

### cJSON.ahk include fails

AHK can't find `<UIA_Inspector\cjson>`. Copy `lib/cJSON.ahk` to `<AHK Lib>\UIA_Inspector\cJSON.ahk`.

---

## Security Considerations

- **Local-only**: The engine listens on `127.0.0.1` only — it cannot be accessed from other machines on the network.
- **No persistence**: The engine runs as a child process of VS Code and shuts down when VS Code exits (or after the idle timeout).
- **UIA permissions**: The engine can inspect any visible window the current user has access to. It cannot inspect windows from other user sessions or elevated processes (unless VS Code itself is elevated).
- **No automation without explicit intent**: The engine only *inspects* — it does not click, type, or modify. The LLM can *generate* automation code, but that code must be run separately by the user.
- **Port file**: The engine uses a temp-file readiness signal (`%TEMP%\UIA_MCP_Engine.port`). On clean shutdown this file is deleted.

---

## Available Commands

Open the Command Palette (Ctrl+Shift+P) and type "UIA MCP":

| Command | What It Does |
|---------|-------------|
| **Start UIA MCP Engine** | Launches the AHK engine process |
| **Stop UIA MCP Engine** | Gracefully shuts down the engine |
| **Restart UIA MCP Engine** | Stops then starts the engine |
| **Show UIA MCP Engine Status** | Displays current state and connection info |

---

## Quick Reference: All 15 Tools

| Tool | What It Does |
|------|-------------|
| `list_windows` | Shows all open windows with title, HWND, PID, exe |
| `get_window_info` | Details about one window: title, class, rect, elevation |
| `get_focused_element` | The element with keyboard focus |
| `inspect_element_at_cursor` | The element under your mouse pointer |
| `get_element_at_point` | Element at specific screen x,y coordinates |
| `find_element` | Find one matching element by condition |
| `find_all_elements` | Find all matching elements (summaries only) |
| `check_match_count` | Count how many elements match a condition |
| `get_element_properties` | Full property dump for a resolved element |
| `get_element_patterns` | Available UIA patterns with current states |
| `get_bounding_rect` | Screen coordinates {left, top, right, bottom} |
| `get_element_tree` | Text tree view of a window's UIA hierarchy |
| `get_ancestor_chain` | Walk from element to root (for anchor selectors) |
| `get_child_elements` | Direct children of an element |
| `wait_for_element` | Poll until element appears or timeout |
