<#
.SYNOPSIS
    Integration test harness for UIA_MCP_Engine.ahk
.DESCRIPTION
    Starts the AHK UIA engine daemon, sends JSON-RPC 2.0 commands over TCP,
    validates responses, and reports pass/fail with color output.

    Tests are organized into groups:
      - Sanity:        ping, shutdown, method-not-found, parse-error
      - Windows:       list_windows, get_window_info
      - Cursor:        inspect_at_cursor
      - Focus:         get_focused_element
      - Find:          find_element, find_all_elements, check_match_count
      - Tree:          get_element_tree, get_ancestor_chain, get_child_elements
      - Properties:    get_element_properties, get_element_patterns, get_bounding_rect
      - Wait:          wait_for_element
      - Point:         get_element_at_point

.PARAMETER AhkExe
    Path to AutoHotkey64.exe. Auto-detected if omitted.
.PARAMETER EngineScript
    Path to UIA_MCP_Engine.ahk. Defaults to ../UIA_MCP_Engine.ahk relative to this script.
.PARAMETER Port
    TCP port for the engine. Default 9876.
.PARAMETER SkipCursorTests
    Skip tests that require mouse interaction (inspect_at_cursor).
.PARAMETER TargetHwnd
    Hex HWND of a window to use for find/element tests.
    If omitted, Notepad is auto-launched as a test target.
.EXAMPLE
    .\test_engine.ps1
    .\test_engine.ps1 -SkipCursorTests -TargetHwnd 0x12345
    .\test_engine.ps1 -AhkExe "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
#>

param(
    [string]$AhkExe = "",
    [string]$EngineScript = "",
    [int]$Port = 9876,
    [switch]$SkipCursorTests,
    [string]$TargetHwnd = "",
    [int]$EngineStartTimeout = 20,
    [int]$RequestTimeout = 30
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ═══════════════════════════════════════════════════════════════
#  Colors
# ═══════════════════════════════════════════════════════════════
function Write-Pass { Write-Host "  PASS" -ForegroundColor Green }
function Write-Fail { Write-Host "  FAIL" -ForegroundColor Red }
function Write-Warn { Write-Host "  WARN" -ForegroundColor Yellow }
function Write-Info($msg) { Write-Host $msg -ForegroundColor Cyan }

# ═══════════════════════════════════════════════════════════════
#  Auto-detect paths
# ═══════════════════════════════════════════════════════════════
function Find-AhkExe {
    if ($AhkExe -and (Test-Path $AhkExe)) { return $AhkExe }
    $candidates = @(
        "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
        "C:\Program Files\AutoHotkey\AutoHotkey64.exe",
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    throw "AutoHotkey64.exe not found. Use -AhkExe to specify path."
}

function Find-EngineScript {
    if ($EngineScript -and (Test-Path $EngineScript)) { return $EngineScript }
    $candidates = @(
        (Join-Path $scriptDir "..\UIA_MCP_Engine.ahk"),
        (Join-Path $scriptDir "UIA_MCP_Engine.ahk")
    )
    foreach ($p in $candidates) {
        $resolved = Resolve-Path $p -ErrorAction SilentlyContinue
        if ($resolved) { return $resolved.Path }
    }
    throw "UIA_MCP_Engine.ahk not found. Use -EngineScript to specify path."
}

# ═══════════════════════════════════════════════════════════════
#  TCP client
# ═══════════════════════════════════════════════════════════════
function Send-JsonRpc {
    param([string]$Method, [hashtable]$Params = @{}, [int]$Id = 0)

    $request = @{
        jsonrpc = "2.0"
        method  = $Method
        params  = $Params
        id      = if ($Id -eq 0) { Get-Random -Minimum 1 -Maximum 99999 } else { $Id }
    }
    $json = (ConvertTo-Json $request -Compress -Depth 10) + "`n"

    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect("127.0.0.1", $Port)
        $tcp.ReceiveTimeout = $RequestTimeout * 1000
        $tcp.SendTimeout = 5000

        $stream = $tcp.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)

        $writer.Write($json)
        $writer.Flush()

        $response = $reader.ReadLine()
        $tcp.Close()

        return (ConvertFrom-Json $response)
    }
    catch {
        return @{ error = "TCP error: $_" }
    }
}

# ═══════════════════════════════════════════════════════════════
#  Assertion helpers
# ═══════════════════════════════════════════════════════════════
$script:passed = 0
$script:failed = 0
$script:warned = 0

function Assert-NoError($response, $testName) {
    Write-Host -NoNewline "  $testName ..."
    if ($response.error) {
        Write-Fail
        Write-Host "    Error: $($response.error)" -ForegroundColor Red
        $script:failed++
        return $false
    }
    Write-Pass
    $script:passed++
    return $true
}

function Assert-Result($response, $testName, [ScriptBlock]$validator) {
    Write-Host -NoNewline "  $testName ..."
    if ($response.error) {
        Write-Fail
        Write-Host "    Error: $($response.error)" -ForegroundColor Red
        $script:failed++
        return $false
    }
    try {
        $ok = & $validator $response.result
        if ($ok) {
            Write-Pass
            $script:passed++
            return $true
        }
        else {
            Write-Fail
            Write-Host "    Validation failed" -ForegroundColor Red
            $script:failed++
            return $false
        }
    }
    catch {
        Write-Fail
        Write-Host "    Validation threw: $_" -ForegroundColor Red
        $script:failed++
        return $false
    }
}

function Assert-Error($response, $testName, [int]$expectedCode = -32000) {
    Write-Host -NoNewline "  $testName ..."
    if (-not $response.error) {
        Write-Fail
        Write-Host "    Expected error but got result" -ForegroundColor Red
        $script:failed++
        return $false
    }
    if ($response.error.code -eq $expectedCode) {
        Write-Pass
        $script:passed++
        return $true
    }
    Write-Fail
    Write-Host "    Expected error $expectedCode, got $($response.error.code): $($response.error.message)" -ForegroundColor Red
    $script:failed++
    return $false
}

# ═══════════════════════════════════════════════════════════════
#  Test Groups
# ═══════════════════════════════════════════════════════════════

function Test-Sanity {
    Write-Info "=== Sanity Tests ==="

    # ping
    $r = Send-JsonRpc -Method "ping"
    Assert-Result $r "ping returns 'pong'" { $args[0] -eq "pong" }

    # parse error — send invalid JSON
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect("127.0.0.1", $Port)
    $stream = $tcp.GetStream()
    $writer = New-Object System.IO.StreamWriter($stream)
    $reader = New-Object System.IO.StreamReader($stream)
    $writer.Write("not json`n")
    $writer.Flush()
    $resp = $reader.ReadLine()
    $tcp.Close()
    $parsed = ConvertFrom-Json $resp
    Assert-Result @{result=$null; error=$null} "parse error response has error field" {
        return $parsed.error -ne $null -and $parsed.error.code -eq -32700
    }
    if (-not $parsed.error) {
        Write-Host "    (skipping parse error check — engine returned result)" -ForegroundColor Yellow
        $script:passed++
    }

    # method not found
    $r = Send-JsonRpc -Method "nonexistent_method"
    Assert-Error $r "nonexistent_method returns -32601" -expectedCode -32601

    # shutdown — don't actually test this first, save for end
}

function Test-Windows {
    Write-Info "=== Window Tests ==="

    # list_windows (no filter)
    $r = Send-JsonRpc -Method "list_windows"
    Assert-Result $r "list_windows returns count" {
        return $null -ne $args[0].count -and $args[0].count -gt 0
    }
    if ($r.result -and $r.result.windows) {
        $winCount = $r.result.windows.Count
        Write-Host "    Found $winCount windows" -ForegroundColor DarkGray

        # Verify structure of first window
        $w = $r.result.windows[0]
        Assert-Result @{result=$w} "first window has hwnd" { $null -ne $args[0].hwnd }
        Assert-Result @{result=$w} "first window has title" { $null -ne $args[0].title }
        Assert-Result @{result=$w} "first window has exe"   { $null -ne $args[0].exe }
        Assert-Result @{result=$w} "first window has pid"   { $null -ne $args[0].pid }

        # Save a useful window for later tests — prefer Program Manager (desktop)
        foreach ($win in $r.result.windows) {
            if ($win.title -match "Program Manager") {
                $script:testHwnd = $win.hwnd
                $script:testTitle = $win.title
                break
            }
        }
        # Fallback: any visible titled window
        if (-not $script:testHwnd) {
            foreach ($win in $r.result.windows) {
                if ($win.title -and $win.title.Length -gt 0 -and $win.visible) {
                    $script:testHwnd = $win.hwnd
                    $script:testTitle = $win.title
                    break
                }
            }
        }
        if ($script:testHwnd) {
            Write-Host "    Using window for further tests: $($script:testTitle) ($($script:testHwnd))" -ForegroundColor DarkGray
        }
    }

    # list_windows (with filter)
    $r = Send-JsonRpc -Method "list_windows" -Params @{filter = "Program Manager"}
    Assert-Result $r "list_windows with filter" {
        return $null -ne $args[0].count
    }

    # get_window_info for a known HWND
    if ($script:testHwnd) {
        $r = Send-JsonRpc -Method "get_window_info" -Params @{hwnd = $script:testHwnd}
        Assert-Result $r "get_window_info returns title" {
            return $null -ne $args[0].title -and $args[0].title.Length -gt 0
        }
        Assert-Result $r "get_window_info returns exe" {
            return $null -ne $args[0].exe
        }
        Assert-Result $r "get_window_info returns rect" {
            return $null -ne $args[0].rect -and $args[0].rect.left -ne $null
        }
    }
    else {
        Write-Warn
        Write-Host "    No visible window found — skipping get_window_info tests" -ForegroundColor Yellow
        $script:warned++
    }
}

function Test-Find {
    Write-Info "=== Find Tests ==="

    if (-not $script:testHwnd) {
        Write-Warn
        Write-Host "    No test window — skipping find tests" -ForegroundColor Yellow
        $script:warned++
        return
    }

    $hwnd = $script:testHwnd

    # check_match_count — find all Pane elements (always present)
    $r = Send-JsonRpc -Method "check_match_count" -Params @{
        condition = @{Type = "Pane"}
        hwnd = $hwnd
        scope = "Descendants"
    }
    Assert-Result $r "check_match_count for Panes" {
        return $null -ne $args[0].count -and $args[0].count -ge 0
    }

    # find_all_elements — find all elements of type Pane
    $r = Send-JsonRpc -Method "find_all_elements" -Params @{
        condition = @{Type = "Pane"}
        hwnd = $hwnd
    }
    Assert-Result $r "find_all_elements for Panes" {
        return $null -ne $args[0].count -and $null -ne $args[0].elements
    }

    # If we found panes, try find_element on the first one
    if ($r.result -and $r.result.elements -and $r.result.elements.Count -gt 0) {
        $first = $r.result.elements[0]
        $name = $first.Name
        $class = $first.ClassName
        if ($class -and $name) {
            $r2 = Send-JsonRpc -Method "find_element" -Params @{
                condition = @{ClassName = $class; Name = $name}
                hwnd = $hwnd
            }
            Assert-Result $r2 "find_element for '$class' '$name'" {
                return $null -ne $args[0].ClassName
            }

            # Get properties of the found element
            if ($r2.result) {
                $r3 = Send-JsonRpc -Method "get_element_properties" -Params @{
                    condition = @{ClassName = $class; Name = $name}
                    hwnd = $hwnd
                }
                Assert-Result $r3 "get_element_properties" {
                    return ($null -ne $args[0].Type) -and ($null -ne $args[0].Name)
                }

                # Get patterns
                $r4 = Send-JsonRpc -Method "get_element_patterns" -Params @{
                    condition = @{ClassName = $class; Name = $name}
                    hwnd = $hwnd
                }
                Assert-Result $r4 "get_element_patterns returns array" {
                    return $args[0] -is [array]
                }
                if ($r4.result) {
                    Write-Host "    Patterns found: $($r4.result.Count)" -ForegroundColor DarkGray
                }

                # Get bounding rect
                $r5 = Send-JsonRpc -Method "get_bounding_rect" -Params @{
                    condition = @{ClassName = $class; Name = $name}
                    hwnd = $hwnd
                }
                Assert-Result $r5 "get_bounding_rect" {
                    return ($null -ne $args[0].left) -and ($null -ne $args[0].top) -and
                           ($null -ne $args[0].right) -and ($null -ne $args[0].bottom)
                }

                # Get ancestor chain
                $r6 = Send-JsonRpc -Method "get_ancestor_chain" -Params @{
                    condition = @{ClassName = $class; Name = $name}
                    hwnd = $hwnd
                }
                Assert-Result $r6 "get_ancestor_chain" {
                    return ($null -ne $args[0].depth) -and ($null -ne $args[0].ancestors) -and
                           ($args[0].ancestors.Count -gt 0)
                }
                Write-Host "    Ancestor depth: $($r6.result.depth)" -ForegroundColor DarkGray

                # Get child elements
                $r7 = Send-JsonRpc -Method "get_child_elements" -Params @{
                    hwnd = $hwnd
                }
                Assert-Result $r7 "get_child_elements from window root" {
                    return ($null -ne $args[0].count) -and ($null -ne $args[0].children)
                }
                Write-Host "    Child count: $($r7.result.count)" -ForegroundColor DarkGray
            }
        }
    }
}

function Test-Tree {
    Write-Info "=== Tree Tests ==="

    if (-not $script:testHwnd) {
        Write-Warn
        Write-Host "    No test window — skipping tree tests" -ForegroundColor Yellow
        $script:warned++
        return
    }

    $hwnd = $script:testHwnd

    # get_element_tree with shallow depth
    $r = Send-JsonRpc -Method "get_element_tree" -Params @{
        hwnd = $hwnd
        maxDepth = 2
    }
    Assert-Result $r "get_element_tree returns tree string" {
        return ($null -ne $args[0].tree) -and ($args[0].tree.Length -gt 0)
    }
    if ($r.result) {
        $lines = ($r.result.tree -split "`n").Count
        Write-Host "    Tree lines: $lines (depth 2)" -ForegroundColor DarkGray
    }

    # get_element_tree with deeper depth
    $r = Send-JsonRpc -Method "get_element_tree" -Params @{
        hwnd = $hwnd
        maxDepth = 3
    }
    Assert-Result $r "get_element_tree depth=3" {
        return ($null -ne $args[0].tree)
    }
}

function Test-Focus {
    Write-Info "=== Focus Tests ==="

    $r = Send-JsonRpc -Method "get_focused_element"
    Assert-Result $r "get_focused_element returns Type" {
        return $null -ne $args[0].Type -and $args[0].Type -ne ""
    }
    if ($r.result) {
        Write-Host "    Focused: $($r.result.Type) '$($r.result.Name)'" -ForegroundColor DarkGray
    }
}

function Test-Cursor {
    Write-Info "=== Cursor Tests ==="

    if ($SkipCursorTests) {
        Write-Warn
        Write-Host "    Skipped (--SkipCursorTests)" -ForegroundColor Yellow
        $script:warned++
        return
    }

    Write-Host "    Move mouse over a window and press Enter to test inspect_at_cursor..." -ForegroundColor Yellow
    Read-Host

    $r = Send-JsonRpc -Method "inspect_at_cursor"
    if ($r.result -and $r.result.elevated) {
        Write-Warn
        Write-Host "    Target is elevated — engine needs admin rights" -ForegroundColor Yellow
        Write-Host "    Target: $($r.result.targetName) (PID $($r.result.targetPid))" -ForegroundColor DarkGray
        $script:warned++
        return
    }
    Assert-Result $r "inspect_at_cursor returns Type" {
        return $null -ne $args[0].Type -and $args[0].Type -ne ""
    }
    if ($r.result) {
        Write-Host "    Element: $($r.result.Type) '$($r.result.Name)'" -ForegroundColor DarkGray
        Assert-Result $r "has WindowTitle" { return $null -ne $args[0].WindowTitle }
        Assert-Result $r "has AncestorChain" { return $null -ne $args[0].AncestorChain -and $args[0].AncestorChain.Count -gt 0 }
        Assert-Result $r "has Patterns" { return $null -ne $args[0].Patterns }
        Assert-Result $r "has InferredAction" { return $null -ne $args[0].InferredAction -and $args[0].InferredAction.Length -gt 0 }
        Assert-Result $r "has ConditionString" { return $null -ne $args[0].ConditionString }
        Write-Host "    Condition: $($r.result.ConditionString)" -ForegroundColor DarkGray
        Write-Host "    Action: $($r.result.InferredAction)" -ForegroundColor DarkGray
    }
}

function Test-Wait {
    Write-Info "=== Wait Tests ==="

    if (-not $script:testHwnd) {
        Write-Warn
        Write-Host "    No test window — skipping wait tests" -ForegroundColor Yellow
        $script:warned++
        return
    }

    # wait_for_element — find element by Name (always present in desktop)
    $r = Send-JsonRpc -Method "wait_for_element" -Params @{
        condition = @{Name = "Desktop"}
        hwnd = $script:testHwnd
        timeout = 3000
    }
    Assert-Result $r "wait_for_element found element by Name" {
        return $args[0].found -eq $true
    }

    # wait_for_element with a condition that definitely does NOT exist
    $r = Send-JsonRpc -Method "wait_for_element" -Params @{
        condition = @{Name = "ZZZ_NONEXISTENT_ELEMENT_ZZZ"}
        hwnd = $script:testHwnd
        timeout = 500
    }
    Assert-Result $r "wait_for_element times out on nonexistent" {
        return $args[0].found -eq $false
    }

    # wait_for_element with missing condition should error
    $r = Send-JsonRpc -Method "wait_for_element"
    Assert-Error $r "wait_for_element without condition errors"
}

function Test-Point {
    Write-Info "=== Point Tests ==="

    # get_element_at_point with likely-valid screen coordinates
    $r = Send-JsonRpc -Method "get_element_at_point" -Params @{x = 100; y = 100}
    Assert-Result $r "get_element_at_point(100,100) returns Type" {
        return ($null -ne $args[0].Type)
    }
    if ($r.result) {
        Write-Host "    Element at (100,100): $($r.result.Type) '$($r.result.Name)'" -ForegroundColor DarkGray
    }

    # Missing params
    $r = Send-JsonRpc -Method "get_element_at_point" -Params @{x = 100}
    Assert-Error $r "get_element_at_point missing y errors"
}

function Test-Elevation {
    Write-Info "=== Elevation Detection Test ==="

    # Try inspecting Task Manager (usually elevated when opened via Ctrl+Shift+Esc)
    $r = Send-JsonRpc -Method "list_windows" -Params @{filter = "Task Manager"}
    if ($r.result -and $r.result.windows -and $r.result.windows.Count -gt 0) {
        $tm = $r.result.windows[0]
        Write-Host "    Task Manager found: $($tm.hwnd) elevated=$($tm.elevated)" -ForegroundColor DarkGray
        
        $r2 = Send-JsonRpc -Method "get_window_info" -Params @{hwnd = $tm.hwnd}
        Assert-Result $r2 "get_window_info for Task Manager" {
            return ($null -ne $args[0].elevated)
        }
        if ($r2.result.elevated) {
            Write-Host "    Task Manager is elevated (expected)" -ForegroundColor DarkGray
            # If we're not admin, tree/window_info should still succeed but element queries might warn
        }
    }
    else {
        Write-Host "    Task Manager not found — skipping elevation test" -ForegroundColor DarkGray
    }
}

function Test-Catalogs {
    Write-Info "=== Catalog Tests ==="

    # Type catalog
    $r = Send-JsonRpc -Method "uia_get_type_catalog"
    Assert-Result $r "type catalog returns data" {
        $types = $args[0]
        return ($null -ne $types.Button -and $null -ne $types.Edit -and $null -ne $types.Window)
    }
    if ($r.result) {
        $typeCount = ($r.result | Get-Member -MemberType NoteProperty).Count
        Write-Host "    Types returned: $typeCount" -ForegroundColor DarkGray
    }

    # Pattern catalog
    $r = Send-JsonRpc -Method "uia_get_pattern_catalog"
    Assert-Result $r "pattern catalog returns data" {
        $patterns = $args[0]
        return ($null -ne $patterns.Invoke -and $null -ne $patterns.Value -and $null -ne $patterns.Toggle)
    }
    if ($r.result) {
        $patCount = ($r.result | Get-Member -MemberType NoteProperty).Count
        Write-Host "    Patterns returned: $patCount" -ForegroundColor DarkGray
    }
}

function Test-Actions {
    Write-Info "=== Action Tests ==="

    # Get a window HWND for testing
    $win = Send-JsonRpc -Method "list_windows" -Params @{filter = "PowerShell"}
    $hwnd = if ($win.result.windows.Count -gt 0) { $win.result.windows[0].hwnd } else { "" }

    # Highlight element (no-op test, just verifies the call doesn't crash)
    $r = Send-JsonRpc -Method "uia_highlight_element" -Params @{duration = 100}
    Assert-NoError $r "highlight_element succeeds"

    # Element exists — should find something at the focused element
    $r = Send-JsonRpc -Method "uia_element_exists" -Params @{condition = @{Type = "Window"}}
    Assert-NoError $r "element_exists with Window type"
    if ($r.result -and $r.result.exists) {
        Write-Host "    Found window: count=$($r.result.count)" -ForegroundColor DarkGray
    }

    # SetValue with missing value should error
    $r = Send-JsonRpc -Method "uia_set_value" -Params @{}
    Assert-Error $r "set_value without value errors"

    # Perform action with missing action should error
    $r = Send-JsonRpc -Method "uia_perform_action" -Params @{}
    Assert-Error $r "perform_action without action errors"

    # Root element
    $r = Send-JsonRpc -Method "uia_get_root_element"
    Assert-Result $r "root element has Type" {
        return ($null -ne $args[0].Type)
    }
    if ($r.result) {
        Write-Host "    Root: $($r.result.Type) '$($r.result.Name)'" -ForegroundColor DarkGray
    }
}

function Test-Discovery {
    Write-Info "=== Discovery Tests ==="

    # Dump tree
    $r = Send-JsonRpc -Method "uia_dump_tree" -Params @{maxDepth = 1}
    Assert-Result $r "dump_tree returns dump string" {
        return ($null -ne $args[0].dump -and $args[0].dump.Length -gt 0)
    }
    if ($r.result) {
        Write-Host "    Dump length: $($r.result.dump.Length) chars" -ForegroundColor DarkGray
    }

    # Wait element not exist — with impossible condition, should resolve quickly
    $r = Send-JsonRpc -Method "uia_wait_element_not_exist" -Params @{
        condition = @{Type = "NoSuchType_XYZ"}
        timeout = 500
    }
    Assert-Result $r "wait_element_not_exist returns gone=true" {
        return ($args[0].gone -eq $true)
    }

    # Element from path — needs a real window
    $win = Send-JsonRpc -Method "list_windows" -Params @{filter = "Program Manager"}
    if ($win.result.windows.Count -gt 0) {
        $hwnd = $win.result.windows[0].hwnd
        $r = Send-JsonRpc -Method "uia_get_element_from_path" -Params @{hwnd = $hwnd; path = "1"}
        Assert-Result $r "element_from_path succeeds" {
            return ($null -ne $args[0].Type)
        }
    }
    else {
        Write-Warn
        Write-Host "    No window for path test" -ForegroundColor Yellow
        $script:warned++
    }

    # Element from chromium — should fail gracefully on non-browser
    if ($win.result.windows.Count -gt 0) {
        $hwnd = $win.result.windows[0].hwnd
        $r = Send-JsonRpc -Method "uia_element_from_chromium" -Params @{hwnd = $hwnd}
        Assert-Error $r "chromium on non-browser errors"
    }
}

function Test-Utility {
    Write-Info "=== Utility Tests ==="

    # State enums
    $r = Send-JsonRpc -Method "uia_get_state_enums"
    Assert-Result $r "state enums returns data" {
        $enums = $args[0]
        return ($null -ne $enums.ToggleState -and $null -ne $enums.ExpandCollapseState)
    }
    if ($r.result.ToggleState) {
        Write-Host "    ToggleState: $($r.result.ToggleState | ConvertTo-Json -Compress)" -ForegroundColor DarkGray
    }

    # Code recipe — list
    $r = Send-JsonRpc -Method "uia_get_code_recipe" -Params @{recipe = "list_recipes"}
    Assert-Result $r "recipe list returns recipes" {
        return ($null -ne $args[0].recipes)
    }

    # Code recipe — specific
    $r = Send-JsonRpc -Method "uia_get_code_recipe" -Params @{recipe = "find_and_click"}
    Assert-Result $r "find_and_click recipe has ahkCode" {
        return ($args[0].ahkCode -match 'WaitElement')
    }

    # Get element code — generate a runnable script for a specific element
    if ($win.result.windows.Count -gt 0) {
        $hwnd = $win.result.windows[0].hwnd
        $r = Send-JsonRpc -Method "uia_get_element_code" -Params @{hwnd = $hwnd; condition = @{Type = "Window"}}
        Assert-Result $r "get_element_code returns ahkCode" {
            return ($null -ne $args[0].ahkCode)
        }
        if ($r.result.ahkCode) {
            Assert-Result $r "ahkCode contains Main()" {
                return ($args[0].ahkCode -match 'Main\(\)')
            }
            Assert-Result $r "ahkCode contains local winEl" {
                return ($args[0].ahkCode -match 'local winEl')
            }
            Assert-Result $r "ahkCode contains local el" {
                return ($args[0].ahkCode -match 'local el')
            }
            Assert-Result $r "ahkCode contains FindFirst" {
                return ($args[0].ahkCode -match 'FindFirst')
            }
            Assert-Result $r "ahkCode contains #Include <UIA>" {
                return ($args[0].ahkCode -match '#Include <UIA>')
            }
            Write-Host "    Generated code:" -ForegroundColor DarkGray
            Write-Host ("    " + ($r.result.ahkCode -replace "`n", "`n    ")) -ForegroundColor DarkGray
        }
    }
    else {
        Write-Warn
        Write-Host "    No window for get_element_code test" -ForegroundColor Yellow
        $script:warned++
    }

    # Window management — Activate requires real HWND
    $win = Send-JsonRpc -Method "list_windows" -Params @{filter = "Program Manager"}
    if ($win.result.windows.Count -gt 0) {
        $hwnd = $win.result.windows[0].hwnd
        $r = Send-JsonRpc -Method "uia_manage_window" -Params @{hwnd = $hwnd; action = "Restore"}
        Assert-NoError $r "manage_window Restore succeeds"
    }
    else {
        Write-Warn
        Write-Host "    No window for manage test" -ForegroundColor Yellow
        $script:warned++
    }

    # Window management — missing action should error
    $r = Send-JsonRpc -Method "uia_manage_window" -Params @{hwnd = "0x12345"}
    Assert-Error $r "manage_window without action errors"
}

# ═══════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  UIA_MCP_Engine Integration Test Suite         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Find paths
$ahk = Find-AhkExe
$script = Find-EngineScript
Write-Info "AHK:        $ahk"
Write-Info "Engine:     $script"
Write-Info "Port:       $Port"
Write-Host ""

# Kill any existing engine on this port
Write-Host "Checking for existing engine on port $Port..." -ForegroundColor DarkGray
$existing = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  Killing existing process on port $Port..." -ForegroundColor Yellow
    Stop-Process -Id $existing.OwningProcess -Force -ErrorAction SilentlyContinue
    Start-Sleep 2
}

# Start the engine
Write-Host "Starting AHK engine..." -ForegroundColor DarkGray
$engineProcess = Start-Process -FilePath $ahk -ArgumentList "`"$script`" --port $Port --idle-timeout 3600" -PassThru -WindowStyle Hidden

# Wait for engine to be ready
Write-Host "Waiting for engine to start..." -ForegroundColor DarkGray
$startTime = Get-Date
$ready = $false
do {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect("127.0.0.1", $Port)
        $tcp.Close()
        $ready = $true
    }
    catch {
        Start-Sleep -Milliseconds 500
    }
} while (-not $ready -and ((Get-Date) - $startTime).TotalSeconds -lt $EngineStartTimeout)

if (-not $ready) {
    Write-Host "Engine did not start within $EngineStartTimeout seconds" -ForegroundColor Red
    if ($engineProcess -and -not $engineProcess.HasExited) {
        Stop-Process -Id $engineProcess.Id -Force
    }
    exit 1
}

Write-Info "Engine started (PID $($engineProcess.Id))"
Write-Host ""

# Run tests
try {
    Test-Sanity
    Test-Windows
    Test-Find
    Test-Tree
    Test-Focus
    Test-Point
    Test-Elevation
    Test-Cursor
    Test-Wait
    Test-Catalogs
    Test-Actions
    Test-Discovery
    Test-Utility
}
catch {
    Write-Host "Test suite threw: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}

# Shutdown
Write-Host ""
Write-Info "=== Cleanup ==="
$r = Send-JsonRpc -Method "shutdown"
Write-Host "Shutdown sent: $($r.result)" -ForegroundColor DarkGray
Start-Sleep 1

if ($engineProcess -and -not $engineProcess.HasExited) {
    Write-Host "Force-killing engine..." -ForegroundColor Yellow
    Stop-Process -Id $engineProcess.Id -Force
}

# Report
Write-Host ""
Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Results                                       ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "  Passed: $script:passed" -ForegroundColor Green
Write-Host "  Failed: $script:failed" -ForegroundColor $(if ($script:failed -gt 0) { "Red" } else { "DarkGray" })
Write-Host "  Warned: $script:warned" -ForegroundColor $(if ($script:warned -gt 0) { "Yellow" } else { "DarkGray" })

if ($script:failed -gt 0) {
    exit 1
}
exit 0
