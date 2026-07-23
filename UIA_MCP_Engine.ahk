#Requires AutoHotkey v2.0.2+
#SingleInstance Force
DetectHiddenWindows true

; ══════════════════════════════════════════════════════════════════
; UIA_MCP_Engine.ahk — Headless JSON-RPC UIA inspection daemon
;
; Listens on TCP localhost for JSON-RPC 2.0 requests. Dispatches to
; UIA inspection commands and returns JSON responses. No GUI, no
; hotkeys — pure headless engine for the VS Code UIA MCP extension.
;
; Usage:
;   AutoHotkey64.exe UIA_MCP_Engine.ahk [--port PORT] [--idle-timeout SECONDS] [--log-level LEVEL]
;
; Defaults:  port=9876  idle-timeout=300  log-level=info
; Log levels: none, error, info, debug
; ══════════════════════════════════════════════════════════════════

#Include <UIA>
#Include <Logger>
#Include <UIA_Inspector\cjson>

; ── cJSON configuration ───────────────────────
; Ensure booleans serialize as true/false, not 0/1
JSON.BoolsAsInts := 0

; ── Configuration ─────────────────────────────
global ENGINE_PORT      := 9876
global IDLE_TIMEOUT_MS  := 300000   ; 5 minutes
global INSPECT_HOTKEY   := "^+I"    ; Ctrl+Shift+I
global PORT_FILE         := A_Temp "\UIA_MCP_Engine.port"

; ── Logger ─────────────────────────────────────
global engineLog := Logger("UIAEngine", A_Temp "\UIA_MCP_Engine.log", Logger.LEVEL_INFO, false)
; debugOut=false because we write to file only (no OutputDebug in daemon context)

; ── Unhandled Error Handler ────────────────────
; AHK v2 shows a GUI error dialog for unhandled exceptions. As a
; headless daemon, that dialog hangs the process indefinitely —
; there's no user to click OK.  OnError lets us log the full error
; to file and suppress the dialog so the engine can exit cleanly.
; The daemon's health check will detect the exit and auto-restart.
_OnUnhandledError(err, mode)
{
    global engineLog
    ; Capture full error detail before any dialog can appear
    try
    {
        errMsg := err.HasProp("Message") ? err.Message : String(err)
        errWhat := err.HasProp("What") ? " (" err.What ")" : ""
        errFile := err.HasProp("File") ? " in " err.File : ""
        errLine := err.HasProp("Line") ? " line " err.Line : ""
        stack  := err.HasProp("Stack") ? "`nStack: " err.Stack : ""
        engineLog.Error("UNHANDLED ERROR (mode=" mode "): " errMsg errWhat errFile errLine stack)
        ; Also write to a dedicated crash log so errors survive
        ; engine restarts which may rotate the main log.
        try FileAppend(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
            . " UNHANDLED (mode=" mode "): " errMsg errWhat errFile errLine "`n" stack "`n`n"
            , A_Temp "\UIA_MCP_Engine_crash.log")
    }
    catch Error as e
    {
        ; Last resort: write to a separate crash file
        try FileAppend(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
            . " UNHANDLED: " (err.HasProp("Message") ? err.Message : String(err))
            . "`n", A_Temp "\UIA_MCP_Engine_crash.log")
    }
    ; Return non-zero to suppress the default error dialog.
    ; The engine will exit; the daemon's health check will restart it.
    return 1
}
OnError(_OnUnhandledError, 1)  ; mode 1 = catch Error as e all unhandled exceptions

; Parse command-line args
for i, arg in A_Args
{
    if (arg = "--port" && A_Args.Has(i + 1))
        ENGINE_PORT := Integer(A_Args[i + 1])
    if (arg = "--idle-timeout" && A_Args.Has(i + 1))
        IDLE_TIMEOUT_MS := Integer(A_Args[i + 1]) * 1000
    if (arg = "--inspect-hotkey" && A_Args.Has(i + 1))
        INSPECT_HOTKEY := A_Args[i + 1]
    if (arg = "--log-file" && A_Args.Has(i + 1))
        engineLog.FilePath := A_Args[i + 1]
    if (arg = "--log-level" && A_Args.Has(i + 1)) {
        switch A_Args[i + 1], 0 {
            case "none":  engineLog.SetLevel(Logger.LEVEL_OFF)
            case "error": engineLog.SetLevel(Logger.LEVEL_ERROR)
            case "info":  engineLog.SetLevel(Logger.LEVEL_INFO)
            case "debug": engineLog.SetLevel(Logger.LEVEL_DEBUG)
        }
    }
}

; ══════════════════════════════════════════════════════════════════
;  JSON-RPC Helpers
; ══════════════════════════════════════════════════════════════════

/**
 * Build a JSON-RPC 2.0 success response.
 * @param id - the request id (mirrored)
 * @param result - the result value (any AHK value / object)
 */
_RpcResult(id, result)
{
    return JSON.Stringify({
        jsonrpc: "2.0",
        result: result,
        id: id
    }, 0) "`n"
}

/**
 * Build a JSON-RPC 2.0 error response.
 * @param id - the request id (mirrored), or null for parse errors
 * @param code - integer error code (-32700 for parse, -32601 for method not found, etc.)
 * @param message - human-readable error string
 * @param data - optional extra error detail
 */
_RpcError(id, code, message, data := "")
{
    err := {code: code, message: message}
    if (data)
        err.data := data
    return JSON.Stringify({
        jsonrpc: "2.0",
        error: err,
        id: id
    }, 0) "`n"
}

; ══════════════════════════════════════════════════════════════════
;  UIA Helpers
; ══════════════════════════════════════════════════════════════════

/**
 * Build a cache request for bulk property retrieval during tree walks.
 * Pre-loads ~22 element properties + ~13 Is*PatternAvailable flags.
 */
_MakeCacheRequest()
{
    global UIA, UIA_TreeScope
    cr := UIA.CreateCacheRequest()
    cr.TreeScope := UIA_TreeScope.Subtree
    for propId in [30002, 30003, 30004, 30005, 30006, 30007, 30009,
                   30010, 30011, 30012, 30013, 30016, 30017, 30019,
                   30020, 30021, 30022, 30023, 30024, 30025, 30026,
                   30001]
        cr.AddProperty(propId)
    for propId in [30027, 30028, 30031, 30033, 30034, 30036, 30037,
                   30040, 30041, 30042, 30043, 30044, 30090]
        cr.AddProperty(propId)
    return(cr)
}

/**
 * Convert a UIA element to a Map of all its known properties.
 * Mirrors the property list used in UIA_Inspector's PopulateProperties.
 */
_ElementToMap(el)
{
    global UIA
    m := Map()
    m["Type"]           := _PropStr(el, 30003)
    m["LocalizedType"]   := _PropStr(el, 30004)
    m["Name"]           := _PropStr(el, 30005)
    m["AutomationId"]   := _PropStr(el, 30011)
    m["ClassName"]      := _PropStr(el, 30012)
    m["FrameworkId"]    := _PropStr(el, 30024)
    m["IsEnabled"]      := _PropBool(el, 30010)
    m["IsOffscreen"]    := _PropBool(el, 30022)
    m["IsKeyboardFocusable"] := _PropBool(el, 30009)
    m["IsPassword"]     := _PropBool(el, 30019)
    m["IsControlElement"] := _PropBool(el, 30016)
    m["IsContentElement"] := _PropBool(el, 30017)
    m["HelpText"]       := _PropStr(el, 30013)
    m["ItemType"]       := _PropStr(el, 30021)
    m["ItemStatus"]     := _PropStr(el, 30026)
    m["Orientation"]    := _PropInt(el, 30023)
    m["AccessKey"]      := _PropStr(el, 30007)
    m["AcceleratorKey"] := _PropStr(el, 30006)
    m["ProcessId"]      := _PropInt(el, 30002)
    m["NativeWindowHandle"] := _PropHwnd(el, 30020)

    ; BoundingRectangle
    try
    {
        raw := el.GetPropertyValue(30001)
        if (IsObject(raw))
            m["BoundingRect"] := {left: raw.l, top: raw.t, right: raw.r, bottom: raw.b}
        else
            m["BoundingRect"] := ""
    } catch Error as e
        m["BoundingRect"] := ""

    ; Resolve element HWND via fallback chain
    try m["HWND"] := _ResolveElementHwnd(el)
    catch Error as e
        m["HWND"] := "0"

    return(m)
}

_PropStr(el, propId)
{
    try
    {
        return String(el.GetPropertyValue(propId))
    }
    catch Error as e
    {
        return("")
    }
}

_PropBool(el, propId)
{
    try
    {
        return(el.GetPropertyValue(propId) ? true : false)
    }
    catch Error as e
    {
        return(false)
    }
}

_PropInt(el, propId)
{
    try
    {
        return Integer(el.GetPropertyValue(propId))
    }
    catch Error as e
    {
        return(0)
    }
}

_PropHwnd(el, propId)
{
    try
    {
        raw := el.GetPropertyValue(propId)
        return(raw ? Format("0x{:X}", raw) : "0")
    }
    catch Error as e
    {
        return("0")
    }
}

/**
 * Resolve a concrete HWND for `el` — NativeWindowHandle → WinId + DeepChild search.
 */
_ResolveElementHwnd(el)
{
    try
    {
        nwh := el.GetPropertyValue(30020)
        if (nwh)
            return Format("0x{:X}", nwh)
    }
    try
    {
        winId := WinExist("ahk_id " el.ProcessId)
        if (winId) {
            deep := _FindDeepestHWND(winId, el)
            if (deep)
                return Format("0x{:X}", deep)
            return Format("0x{:X}", winId)
        }
    }
    return("0")
}

_FindDeepestHWND(hwnd, el)
{
    try
    {
        rect := el.GetPropertyValue(30001)
        if (!IsObject(rect))
            return(0)
        targetLeft := rect.l, targetTop := rect.t, targetRight := rect.r, targetBottom := rect.b
    }
    catch Error as e
    {
        return(0)
    }
    bestMatch := 0
    bestArea := 0
    EnumChildWindows(hwnd, _EnumChildFunc.Bind(&bestMatch, &bestArea, targetLeft, targetTop, targetRight, targetBottom))
    return(bestMatch)
}

_EnumChildFunc(&bestMatch, &bestArea, tL, tT, tR, tB, hwnd)
{
    try
    {
        WinGetPos(&x, &y, &w, &h, hwnd)
        left := Max(x, tL), top := Max(y, tT)
        right := Min(x + w, tR), bottom := Min(y + h, tB)
        if (left < right && top < bottom) {
            area := (right - left) * (bottom - top)
            if (area > bestArea) {
                bestArea := area
                bestMatch := hwnd
            }
        }
    }
    return(true)
}

EnumChildWindows(hwnd, fn)
{
    DllCall("EnumChildWindows", "Ptr", hwnd, "Ptr", CallbackCreate(fn, "Fast"), "Ptr", 0)
}

/**
 * Build a condition Map from a JSON-like condition object.
 * Accepts: {Type:"Button", Name:"OK", AutomationId:"foo", ClassName:"bar"}
 *          or numeric property IDs: {30003:"Button"}
 * Returns a Map suitable for FindFirst/FindAll.
 */
_BuildCondition(condObj)
{
    condMap := Map()
    nameToId := Map(
        "Type", 30003,
        "LocalizedType", 30004,
        "Name", 30005,
        "AutomationId", 30011,
        "ClassName", 30012,
        "FrameworkId", 30024,
        "ItemType", 30021,
        "AccessKey", 30007,
        "HelpText", 30013
    )
    for key, val in condObj
    {
        if (val = "")
            continue
        propId := 0
        if (nameToId.Has(key))
            propId := nameToId[key]
        else {
            try propId := Integer(key)
            catch Error as e
                propId := 0
        }
        if (propId) {
            ; For Type property, convert name to integer ID (e.g. "Pane" → 50033)
            if (propId = 30003 && val is String) {
                try
                {
                    typeId := UIA_Type.%val%
                    condMap[propId] := typeId
                }
                catch Error as e
                {
                    condMap[propId] := String(val)
                }
            }
            else
            {
                condMap[propId] := String(val)
            }
        }
    }
    ; Convert Map to Object — UIA.CreateCondition requires Object, not Map
    if (!condMap.Count)
        return("")
    condObj2 := {}
    for k, v in condMap
        condObj2.%k% := v
    return(condObj2)
}

/**
 * Convert an element to a summary map (Type + Name + AutomationId + ClassName + BoundingRect).
 * Used for find_all_elements and children lists to keep responses compact.
 */
_ElementSummary(el)
{
    return {
        Type:          _PropStr(el, 30003),
        Name:          _PropStr(el, 30005),
        AutomationId:  _PropStr(el, 30011),
        ClassName:     _PropStr(el, 30012),
        IsEnabled:     _PropBool(el, 30010),
        IsOffscreen:   _PropBool(el, 30022)
    }
}

/**
 * Resolve a TreeScope from a string name. Falls back to Descendants.
 */
_ResolveScope(scopeName)
{
    switch scopeName {
        case "Children":      return UIA_TreeScope.Children
        case "Subtree":       return UIA_TreeScope.Subtree
        case "Element":       return UIA_TreeScope.Element
        case "Descendants":   return UIA_TreeScope.Descendants
        default:              return UIA_TreeScope.Descendants
    }
}

/**
 * Resolve a MatchMode from a string.
 */
_ResolveMatchMode(mode)
{
    switch mode {
        case "Contains":   return 2
        case "StartsWith": return 1
        case "EndsWith":   return 3
        default:           return ""   ; exact
    }
}

/**
 * Walk ancestor chain from `el` → root via TreeWalkerTrue.
 * Returns array of element summary objects, root-first.
 */
_GetAncestorChain(el)
{
    global UIA
    chain := []
    try
    {
        walker := UIA.TreeWalkerTrue
        cur := el
        while (cur)
        {
            chain.InsertAt(1, {
                Type:          _PropStr(cur, 30003),
                Name:          _PropStr(cur, 30005),
                AutomationId:  _PropStr(cur, 30011),
                ClassName:     _PropStr(cur, 30012),
                FrameworkId:   _PropStr(cur, 30024),
                IsEnabled:     _PropBool(cur, 30010)
            })
            cur := walker.GetParentElement(cur)
        }
    }
    return(chain)
}

/**
 * Build a compact text tree from a window element.
 * Marks the selected element with `<<< SELECTED` if matched.
 */
_BuildTreeSnippet(windowEl, selectedEl := "", maxDepth := 4)
{
    out := ""
    _WalkTree(windowEl, selectedEl, 0, maxDepth, &out)
    return(out)
}

_WalkTree(el, selectedEl, depth, maxDepth, &out)
{
    if (depth > maxDepth)
        return
    prefix := ""
    loop depth
        prefix .= "  "
    typ := _PropStr(el, 30003)
    name := _PropStr(el, 30005)
    aid := _PropStr(el, 30011)
    cls := _PropStr(el, 30012)
    marker := ""
    try
    {
        if (selectedEl && el.Compare(selectedEl))
            marker := " <<< SELECTED"
    }
    line := prefix "[" typ "]"
    if (name)
        line .= " Name='" name "'"
    if (aid)
        line .= " AutomationId='" aid "'"
    if (cls)
        line .= " ClassName='" cls "'"
    line .= marker "`n"
    out .= line

    ; Walk children
    try
    {
        child := UIA.TreeWalkerTrue.GetFirstChildElement(el)
        while (child)
        {
            _WalkTree(child, selectedEl, depth + 1, maxDepth, &out)
            child := UIA.TreeWalkerTrue.GetNextSiblingElement(child)
        }
    }
}

/**
 * Return the available patterns for an element as an array of objects,
 * each with optional sub-properties (e.g. ToggleState, Value).
 */
_GetPatterns(el)
{
    global UIA
    patterns := []
    ; Invoke
    try
    {
        if (el.GetPropertyValue(30031))
            patterns.Push({name: "Invoke"})
    }
    ; Toggle
    try
    {
        if (el.GetPropertyValue(30041)) {
            p := {name: "Toggle"}
            try p.state := el.GetPattern("Toggle").ToggleState
            patterns.Push(p)
        }
    }
    ; ExpandCollapse
    try
    {
        if (el.GetPropertyValue(30028)) {
            p := {name: "ExpandCollapse"}
            try p.state := Map(0, "Collapsed", 1, "Expanded", 2, "PartiallyExpanded")[el.GetPattern("ExpandCollapse").ExpandCollapseState]
            patterns.Push(p)
        }
    }
    ; Value
    try
    {
        if (el.GetPropertyValue(30043)) {
            p := {name: "Value"}
            try p.value := el.GetPattern("Value").Value
            try p.isReadOnly := el.GetPattern("Value").IsReadOnly
            patterns.Push(p)
        }
    }
    ; SelectionItem
    try
    {
        if (el.GetPropertyValue(30036)) {
            p := {name: "SelectionItem"}
            try p.isSelected := el.GetPattern("SelectionItem").IsSelected
            patterns.Push(p)
        }
    }
    ; Selection
    try
    {
        if (el.GetPropertyValue(30037)) {
            p := {name: "Selection"}
            try p.canSelectMultiple := el.GetPattern("Selection").CanSelectMultiple
            patterns.Push(p)
        }
    }
    ; Scroll
    try
    {
        if (el.GetPropertyValue(30034)) {
            p := {name: "Scroll"}
            try p.horizontallyScrollable := el.GetPattern("Scroll").HorizontallyScrollable
            try p.verticallyScrollable := el.GetPattern("Scroll").VerticallyScrollable
            patterns.Push(p)
        }
    }
    ; Window
    try
    {
        if (el.GetPropertyValue(30090)) {
            p := {name: "WindowPattern"}
            try p.canMinimize := el.GetPattern("WindowPattern").CanMinimize
            try p.canMaximize := el.GetPattern("WindowPattern").CanMaximize
            patterns.Push(p)
        }
    }
    ; Transform
    try
    {
        if (el.GetPropertyValue(30040)) {
            p := {name: "Transform"}
            try p.canMove := el.GetPattern("Transform").CanMove
            try p.canResize := el.GetPattern("Transform").CanResize
            patterns.Push(p)
        }
    }
    ; LegacyIAccessible
    try
    {
        if (el.GetPropertyValue(30033)) {
            p := {name: "LegacyIAccessible"}
            try p.name := el.GetPattern("LegacyIAccessible").Name
            try p.value := el.GetPattern("LegacyIAccessible").Value
            patterns.Push(p)
        }
    }
    return(patterns)
}

/**
 * Determine a sensible default action for an element by probing pattern availability.
 */
_DetermineAction(el)
{
    try
    {
        if (el.GetPropertyValue(30031))
            return("Invoke()")
    }
    try
    {
        if (el.GetPropertyValue(30041))
            return("Toggle()")
    }
    try
    {
        if (el.GetPropertyValue(30028)) {
            state := el.GetPattern("ExpandCollapse").ExpandCollapseState
            return(state = 0 ? "Expand()" : "Collapse()")
        }
    }
    try
    {
        if (el.GetPropertyValue(30043))
            return('SetValue("")')
    }
    try
    {
        if (el.GetPropertyValue(30036))
            return("Select()")
    }
    return("Click()")
}

/**
 * Build a condition string for `el` — Type + AutomationId > Name > ClassName.
 */
_BuildConditionString(el)
{
    parts := []
    try
    {
        typeId := el.Type
        typeName := UIA_Type.HasValue(typeId)
        if (typeName)
            parts.Push('Type: "' typeName '"')
    }
    try
    {
        aid := el.AutomationId
        if (aid != "") {
            parts.Push('AutomationId: "' _EscapeStr(String(aid)) '"')
            return("{" _Join(parts) "}")
        }
    }
    try
    {
        name := el.Name
        if (name) {
            parts.Push('Name: "' _EscapeStr(name) '"')
            return("{" _Join(parts) "}")
        }
    }
    try
    {
        cn := el.ClassName
        if (cn)
            parts.Push('ClassName: "' _EscapeStr(cn) '"')
    }
    return(parts.Length ? "{" _Join(parts) "}" : "{}")
}

_EscapeStr(s)
{
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    return(s)
}

_Join(arr)
{
    s := ""
    for i, v in arr
        s .= (i > 1 ? ", " : "") v
    return(s)
}

; ══════════════════════════════════════════════════════════════════
;  Process Detection Helpers
; ══════════════════════════════════════════════════════════════════

/**
 * Check if a window is Chromium-based (Chrome, Edge, Electron, CEF, etc.).
 *
 * Uses the UIA library's built-in WindowIsChromium detection which covers
 * ALL Chromium-based apps — Electron (Signal, Discord, Slack, VS Code, Teams),
 * CEF (Spotify), and standard browsers — not just a hardcoded list.
 *
 * @param {Integer} hwnd - window handle (use "ahk_id " prefix for string calls)
 * @returns {Boolean} True if the window uses Chromium rendering
 */
_IsChromiumWindow(hwnd)
{
    try
    {
        return(UIA.WindowIsChromium("ahk_id " hwnd))
    }
    catch Error as e
    {
        return(false)
    }
}

/**
 * Check if a process is a known browser by executable name.
 *
 * For Chromium-based window detection (including Electron apps like Signal,
 * Discord, VS Code), use _IsChromiumWindow instead.
 *
 * @param {Integer} pid - process ID
 * @returns {Boolean} True if the process is a browser
 */
_IsBrowserProcess(pid)
{
    try
    {
        exe := ProcessGetName(pid)
        exe := StrLower(exe)
        return(InStr(exe, "chrome") || InStr(exe, "msedge") || InStr(exe, "opera") || InStr(exe, "brave") || InStr(exe, "firefox"))
    }
    return(false)
}

_IsElevated(pid)
{
    try
    {
        hProc := DllCall("OpenProcess", "UInt", 0x400, "Int", 0, "UInt", pid, "Ptr")
        if (!hProc)
            return(false)
        token := 0
        DllCall("OpenProcessToken", "Ptr", hProc, "UInt", 8, "Ptr*", &token)
        DllCall("CloseHandle", "Ptr", hProc)
        if (!token)
            return(false)
        elevation := 0
        DllCall("GetTokenInformation", "Ptr", token, "Int", 20, "UInt*", &elevation, "UInt", 4, "UInt*", &retLen)
        DllCall("CloseHandle", "Ptr", token)
        return(elevation != 0)
    }
    return(false)
}

_CheckExeBitness(path)
{
    try
    {
        if (!FileExist(path))
            return("?")
        bin := FileOpen(path, "r")
        bin.Pos := 0x3C
        peOffset := bin.ReadUInt()
        bin.Pos := peOffset + 4
        machine := bin.ReadUShort()
        bin.Close()
        return(machine = 0x8664 ? "x64" : "x86")
    }
    return("?")
}

; ══════════════════════════════════════════════════════════════════
;  Locator Resolution
; ══════════════════════════════════════════════════════════════════

/**
 * Resolve a locator object to a UIA element.
 * locator = {hwnd?, condition?, scope?, matchMode?, index?}
 * Falls back chain: anchor hwnd → condition → scope → matchMode → index
 * Returns the resolved element, or throws.
 */
_ResolveLocator(locator)
{
    root := 0
    ; Root by HWND
    if (locator.Has("hwnd") && locator["hwnd"]) {
        ; Try without cache request first — VB6/LegacyIAccessible
        ; bridges can E_INVALIDARG when cache is combined with FindAll.
        try
        {
            root := UIA.ElementFromHandle(locator["hwnd"])
        }
        catch Error as e
        {
            cr := _MakeCacheRequest()
            root := UIA.ElementFromHandle(locator["hwnd"], cr)
        }
    }
    ; Root by focused element
    else {
        root := UIA.GetFocusedElement()
    }
    if (!root)
        throw Error("Could not resolve root element from locator")

    ; If no condition, return root
    if (!locator.Has("condition") || !locator["condition"] || locator["condition"] = "")
        return(root)

    condMap := _BuildCondition(locator["condition"])
    if (condMap = "")
        return(root)

    scope := _ResolveScope(locator.Has("scope") ? locator["scope"] : "Descendants")
    matchMode := _ResolveMatchMode(locator.Has("matchMode") ? locator["matchMode"] : "Exact")
    index := locator.Has("index") ? locator["index"] : 1

    ; Use FindAll + index to get the Nth match.
    ; Wrapped in its own try so COM errors don't propagate
    ; and corrupt the engine's COM apartment.
    try
    {
        matches := root.FindAll(condMap, matchMode, scope)
        if (IsObject(matches) && matches.Length >= index)
            return(matches[index])
    }
    catch Error as findErr
    {
        ; Distinguish COM parameter errors from "not found"
        if (InStr(findErr.Message, "0x80070057") || InStr(findErr.Message, "parameter is incorrect"))
            throw Error("FindAll failed on this window: " findErr.Message
                . " — the condition may use properties unsupported by this window's UIA bridge.")
        ; Re-throw other errors
        throw findErr
    }
    throw Error("No element found matching the condition")
}

; ══════════════════════════════════════════════════════════════════
;  Command Handlers
; ══════════════════════════════════════════════════════════════════

/**
 * inspect_at_cursor
 * Returns full element info at the mouse cursor position.
 */
_HandleInspectAtCursor(params)
{
    global UIA
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY, &winUnderMouse)
    if (!winUnderMouse)
        throw Error("No window under cursor")
    engineLog.Debug("InspectAtCursor: mouse at (" mX "," mY ") hwnd=0x" Format("{:X}", winUnderMouse))

    ; Check elevation
    targetPid := WinGetPID("ahk_id " winUnderMouse)
    engineLog.Debug("InspectAtCursor: targetPid=" targetPid)
    elevated := _IsElevated(targetPid)
    if (elevated && !A_IsAdmin) {
        return {
            elevated: true,
            targetPid: targetPid,
            targetName: ProcessGetName(targetPid),
            message: "Target is elevated. Restart engine as Administrator."
        }
    }

    ; Activate Chromium accessibility if needed
    try
    {
        if (_IsBrowserProcess(targetPid))
            UIA.ActivateChromiumAccessibility(winUnderMouse)
    }

    engineLog.Debug("InspectAtCursor: building cache request...")
    cr := _MakeCacheRequest()
    engineLog.Debug("InspectAtCursor: getting window element from handle...")
    windowEl := UIA.ElementFromHandle(winUnderMouse, cr)

    engineLog.Debug("InspectAtCursor: calling ElementFromPoint...")
    el := 0
    try
    {
        el := UIA.ElementFromPoint(mX, mY)
    }
    catch Error as err
    {
        ; Chromium browsers, GPU-rendered surfaces, and some
        ; overlays don't expose UIA at the pixel level.
        return {
            error: true,
            message: "Element at cursor not accessible via UIA: " err.Message,
            hint: "Try hovering over a different window (not a browser). "
                . "Chromium-based browsers (Edge, Chrome) do not expose "
                . "tab-level or page-level elements to UIA via point query.",
            x: mX,
            y: mY,
            hwnd: Format("0x{:X}", winUnderMouse),
            targetName: ProcessGetName(targetPid)
        }
    }

    ; Fallback: raw COM IUIAutomation call for custom UI frameworks
    if (!el) {
        try
        {
            automation := UIA.IUIAutomation
            pt := Buffer(8, 0)
            NumPut("Int", mX, "Int", mY, pt)
            elPtr := 0
            ComCall(7, automation, "int", "ptr", pt, "ptr*", &elPtr)
            if (elPtr)
                el := UIA.IUIAutomationElement(elPtr)
        }
    }

    if (!el)
        return {
            error: true,
            message: "UIA.ElementFromPoint returned nothing at (" mX "," mY ")",
            x: mX, y: mY,
            hwnd: Format("0x{:X}", winUnderMouse),
            targetName: ProcessGetName(targetPid)
        }

    engineLog.Debug("InspectAtCursor: element found, building full result...")
    result := _BuildFullElementResult(el, windowEl, winUnderMouse, targetPid)
    engineLog.Debug("InspectAtCursor: done, Type=" (result.HasProp("Type") ? result["Type"] : "?"))
    return(result)
}

/**
 * get_focused_element
 * Returns the currently focused UI element.
 */
_HandleGetFocusedElement(params)
{
    try
    {
        el := UIA.GetFocusedElement()
        if (!el)
            throw Error("No focused element found")

        ; Get window info from the focused element
        hwnd := 0
        try hwnd := el.CurrentNativeWindowHandle

        windowEl := 0
        try windowEl := UIA.ElementFromHandle(hwnd, _MakeCacheRequest())

        targetPid := 0
        try targetPid := WinGetPID("ahk_id " hwnd)

        return _BuildFullElementResult(el, windowEl, hwnd, targetPid)
    }
    catch Error as err
    {
        throw Error("Failed to get focused element: " err.Message)
    }
}

/**
 * find_element — resolve a locator to a single element and return full info.
 */
_HandleFindElement(params)
{
    el := _ResolveLocator(params)
    hwnd := 0
    try hwnd := el.CurrentNativeWindowHandle
    if (!hwnd)
        try hwnd := el.GetPropertyValue(30020)
    targetPid := 0
    try targetPid := WinGetPID("ahk_id " hwnd)

    windowEl := 0
    try windowEl := UIA.ElementFromHandle(hwnd, _MakeCacheRequest())

    return _BuildFullElementResult(el, windowEl, hwnd, targetPid)
}

/**
 * find_all_elements — return array of element summaries matching condition.
 */
_HandleFindAllElements(params)
{
    condMap := _BuildCondition(params.Has("condition") ? params["condition"] : {})
    if (condMap = "")
        throw Error("condition is required for find_all")

    scope := _ResolveScope(params.Has("scope") ? params["scope"] : "Descendants")
    matchMode := _ResolveMatchMode(params.Has("matchMode") ? params["matchMode"] : "Exact")

    root := 0
    if (params.Has("hwnd") && params["hwnd"]) {
        ; Try without cache request first — VB6/LegacyIAccessible windows
        ; can throw E_INVALIDARG (0x80070057) when a cache request is used
        ; with FindAll.  Using a bare ElementFromHandle avoids this.
        try
        {
            root := UIA.ElementFromHandle(params["hwnd"])
        }
        catch Error as e
        {
            cr := _MakeCacheRequest()
            root := UIA.ElementFromHandle(params["hwnd"], cr)
        }
    }
    else
    {
        root := UIA.GetFocusedElement()
    }
    if (!root)
        throw Error("Could not resolve root")

    ; Protect FindAll — VB6/LegacyIAccessible bridges may throw
    ; E_INVALIDARG for conditions containing properties they don't
    ; support (e.g. AutomationId on a native menu item).  Catch it
    ; and return a clear error without crashing the engine.
    try
    {
        matches := root.FindAll(condMap, matchMode, scope)
        results := []
        if (IsObject(matches)) {
            for i, m in matches
            {
                results.Push(_ElementSummary(m))
            }
        }
        return {
            count: results.Length,
            elements: results
        }
    }
    catch Error as err
    {
        ; E_INVALIDARG / other COM errors: the condition isn't
        ; compatible with this element type.  Return a descriptive
        ; error instead of letting the engine crash.
        return {
            count: 0,
            elements: [],
            warning: "FindAll failed: " err.Message
                . " — this window may use a legacy UIA bridge (VB6, WinForms, etc.) "
                . "that doesn't support the requested condition properties. "
                . "Try a simpler condition (e.g. Type only)."
        }
    }
}

/**
 * get_element_tree — walk the UIA tree from a window or element.
 */
_HandleGetElementTree(params)
{
    hwnd := params.Has("hwnd") ? params["hwnd"] : 0
    maxDepth := params.Has("maxDepth") ? params["maxDepth"] : 4
    filter := params.Has("filter") ? params["filter"] : ""

    if (!hwnd)
        throw Error("hwnd is required for get_element_tree")

    ; Check elevation
    targetPid := WinGetPID("ahk_id " hwnd)
    if (_IsElevated(targetPid) && !A_IsAdmin) {
        return {
            elevated: true,
            targetPid: targetPid,
            message: "Target is elevated. Restart engine as Administrator."
        }
    }

    cr := _MakeCacheRequest()
    windowEl := UIA.ElementFromHandle(hwnd, cr)
    tree := _BuildTreeSnippet(windowEl, "", maxDepth)
    return {
        hwnd: hwnd,
        maxDepth: maxDepth,
        tree: tree
    }
}

/**
 * get_ancestor_chain — walk from element to root.
 */
_HandleGetAncestorChain(params)
{
    el := _ResolveLocator(params)
    chain := _GetAncestorChain(el)
    return {
        depth: chain.Length,
        ancestors: chain
    }
}

/**
 * get_element_properties — return all properties for a resolved element.
 */
_HandleGetElementProperties(params)
{
    el := _ResolveLocator(params)
    props := _ElementToMap(el)
    ; Convert Map to object for JSON serialization
    result := {}
    for k, v in props
        result.%k% := v
    return(result)
}

/**
 * get_element_patterns — return available patterns.
 */
_HandleGetElementPatterns(params)
{
    el := _ResolveLocator(params)
    return(_GetPatterns(el))
}

/**
 * EnumWindows callback — collects window info into a global temp list.
 *
 * Using EnumWindows (Win32 API) instead of WinGetList() because AHK's
 * WinGetList() internally filters out owned/tool windows — notably VB6
 * MDI forms (ThunderRT6MDIForm) and any window with GWLP_HWNDPARENT set.
 * EnumWindows sees every top-level window unconditionally.
 */
_EnumWindowsCollect(hwnd, lParam)
{
    try
    {
        title := WinGetTitle(hwnd)
        class := WinGetClass(hwnd)
        pid  := WinGetPID(hwnd)
        exe  := ProcessGetName(pid)
        WinGetPos(&x, &y, &w, &h, hwnd)

        global _enumWindowsTmp
        _enumWindowsTmp.Push({
            hwnd:    Format("0x{:X}", hwnd),
            title:   title,
            class:   class,
            pid:     pid,
            exe:     exe,
            rect:    {left: x, top: y, right: x + w, bottom: y + h},
            elevated: _IsElevated(pid),
            visible: WinGetMinMax(hwnd) != -1
        })
    }
    catch Error as err
    {
        ; Log the failure so operators can diagnose enumeration gaps.
        ; Previously a bare `try` silently dropped the window.
        engineLog.Error("list_windows: skipping HWND " Format("0x{:X}", hwnd)
                . " — " . err.Message)
    }
    return true  ; continue enumeration
}

/**
 * list_windows — enumerate all top-level windows via EnumWindows.
 */
_HandleListWindows(params)
{
    filter := params.Has("filter") ? params["filter"] : ""
    filterLower := StrLower(filter)
    
    ; ── Collect every top-level window via EnumWindows ──────────
    global _enumWindowsTmp := []
    
    cb := CallbackCreate(_EnumWindowsCollect, , 2)
    DllCall("EnumWindows", "Ptr", cb, "Ptr", 0)
    CallbackFree(cb)
    
    windows := _enumWindowsTmp
    _enumWindowsTmp := ""  ; release global reference
    
    ; ── Apply optional filter post-collection ───────────────────
    if (filterLower) {
        filtered := []
        for win in windows
        {
            if (InStr(StrLower(win.title), filterLower))
                    || InStr(StrLower(win.exe), filterLower)
                filtered.Push(win)
        }
        windows := filtered
    }
    
    return {
        count:   windows.Length,
        windows: windows
    }
}

/**
 * get_window_info — detailed info for a specific window.
 */
_HandleGetWindowInfo(params)
{
    if (!params.Has("hwnd") || !params["hwnd"])
        throw Error("hwnd is required")

    hwnd := params["hwnd"]
    if (hwnd is String)
        hwnd := Integer(hwnd)

    try
    {
        title := WinGetTitle(hwnd)
        class := WinGetClass(hwnd)
        pid := WinGetPID(hwnd)
        exe := ProcessGetName(pid)
        path := ProcessGetPath(pid)
        WinGetPos(&x, &y, &w, &h, hwnd)
        minMax := WinGetMinMax(hwnd)
        bitness := _CheckExeBitness(path)
        elevated := _IsElevated(pid)

        ; Framework detection (lightweight, inlined)
        fw := _QuickDetectFramework(hwnd, class, pid, exe)

        return {
            hwnd: Format("0x{:X}", hwnd),
            title: title,
            class: class,
            pid: pid,
            exe: exe,
            path: path,
            rect: {left: x, top: y, right: x + w, bottom: y + h},
            minMax: minMax,   ; -1=minimized, 0=normal, 1=maximized
            bitness: bitness,
            elevated: elevated,
            isBrowser: _IsBrowserProcess(pid),
            framework: fw.framework,
            frameworkConfidence: fw.confidence
        }
    }
    catch Error as err
    {
        throw Error("Failed to get window info: " err.Message)
    }
}

/**
 * check_match_count — count how many elements match a condition.
 */
_HandleCheckMatchCount(params)
{
    root := 0
    if (params.Has("hwnd") && params["hwnd"]) {
        cr := _MakeCacheRequest()
        root := UIA.ElementFromHandle(params["hwnd"], cr)
    }
    else
    {
        root := UIA.GetFocusedElement()
    }
    if (!root)
        throw Error("Could not resolve root")

    condMap := _BuildCondition(params.Has("condition") ? params["condition"] : {})
    if (condMap = "")
        throw Error("condition is required")

    scope := _ResolveScope(params.Has("scope") ? params["scope"] : "Descendants")
    matchMode := _ResolveMatchMode(params.Has("matchMode") ? params["matchMode"] : "Exact")

    try
    {
        matches := root.FindAll(condMap, matchMode, scope)
        if (IsObject(matches))
            return {count: matches.Length}
        return {count: 0}
    }
    catch Error as e
    {
        return {count: 0}
    }
}

/**
 * get_child_elements — return direct children of a resolved element.
 */
_HandleGetChildElements(params)
{
    el := _ResolveLocator(params)
    children := []
    try
    {
        child := UIA.TreeWalkerTrue.GetFirstChildElement(el)
        while (child)
        {
            children.Push(_ElementSummary(child))
            child := UIA.TreeWalkerTrue.GetNextSiblingElement(child)
        }
    }
    return {
        count: children.Length,
        children: children
    }
}

/**
 * get_bounding_rect — return the bounding rectangle of an element.
 */
_HandleGetBoundingRect(params)
{
    el := _ResolveLocator(params)
    try
    {
        raw := el.GetPropertyValue(30001)
        if (IsObject(raw))
            return {left: raw.l, top: raw.t, right: raw.r, bottom: raw.b}
        return {left: 0, top: 0, right: 0, bottom: 0}
    }
    catch Error as e
    {
        return {left: 0, top: 0, right: 0, bottom: 0}
    }
}

/**
 * wait_for_element — poll until element matching condition exists or timeout.
 */
_HandleWaitForElement(params)
{
    timeout := params.Has("timeout") ? params["timeout"] : 5000
    hwnd := params.Has("hwnd") ? params["hwnd"] : 0
    condObj := params.Has("condition") ? params["condition"] : {}

    condMap := _BuildCondition(condObj)
    if (condMap = "")
        throw Error("condition is required")

    scope := _ResolveScope(params.Has("scope") ? params["scope"] : "Descendants")
    matchMode := _ResolveMatchMode(params.Has("matchMode") ? params["matchMode"] : "Exact")

    ; Get root element
    root := 0
    if (hwnd) {
        cr := _MakeCacheRequest()
        root := UIA.ElementFromHandle(hwnd, cr)
    }
    else
    {
        root := UIA.GetFocusedElement()
    }
    if (!root)
        throw Error("Could not resolve root")

    ; Poll
    start := A_TickCount
    loop
    {
        try
        {
            matches := root.FindAll(condMap, matchMode, scope)
            if (IsObject(matches) && matches.Length > 0) {
                return {
                    found: true,
                    elapsed: A_TickCount - start,
                    element: _BuildFullElementResult(matches[1], root, hwnd, 0)
                }
            }
        }
        if (A_TickCount - start >= timeout)
            break
        Sleep(100)
    }

    return {
        found: false,
        elapsed: A_TickCount - start
    }
}

/**
 * get_element_at_point — return element at screen (x, y).
 */
_HandleGetElementAtPoint(params)
{
    if (!params.Has("x") || !params.Has("y"))
        throw Error("x and y are required")

    x := params["x"], y := params["y"]

    ; Get window under point
    hwnd := 0
    try
    {
        pt := (x & 0xFFFFFFFF) | (y << 32)
        hwnd := DllCall("WindowFromPoint", "Int64", pt, "Ptr")
    }
    if (!hwnd)
        throw Error("No window at (" x ", " y ")")

    targetPid := WinGetPID("ahk_id " hwnd)

    cr := _MakeCacheRequest()
    windowEl := UIA.ElementFromHandle(hwnd, cr)
    el := UIA.ElementFromPoint(x, y)

    return _BuildFullElementResult(el, windowEl, hwnd, targetPid)
}

; ══════════════════════════════════════════════════════════════════
;  Action & Catalog Handlers (Phase 1+2 tools)
; ══════════════════════════════════════════════════════════════════

/**
 * uia_get_type_catalog — return all valid UIA control type names and their integer IDs.
 *
 * @returns {Object} Object with type name → integer ID mappings
 */
_HandleGetTypeCatalog(params)
{
    global UIA_Type
    types := Map()
    ; Enumerate all type constants from the UIA library
    try
    {
        for name, id in UIA_Type.OwnProps()
            types[name] := id
    }
    return types
}

/**
 * uia_get_pattern_catalog — return all available UIA patterns with their methods and properties.
 *
 * @returns {Object} Object with pattern name → {methods, properties} mappings
 */
_HandleGetPatternCatalog(params)
{
    catalog := Map()

    catalog["Invoke"] := {methods: ["Invoke"]}

    catalog["Toggle"] := {
        methods: ["Toggle"],
        properties: ["ToggleState"]
    }

    catalog["ExpandCollapse"] := {
        methods: ["Expand", "Collapse"],
        properties: ["ExpandCollapseState"]
    }

    catalog["Value"] := {
        methods: ["SetValue"],
        properties: ["Value", "IsReadOnly"]
    }

    catalog["SelectionItem"] := {
        methods: ["Select", "AddToSelection", "RemoveFromSelection"],
        properties: ["IsSelected", "SelectionContainer"]
    }

    catalog["Selection"] := {
        methods: ["GetSelection"],
        properties: ["CanSelectMultiple", "IsSelectionRequired"]
    }

    catalog["Scroll"] := {
        methods: ["Scroll", "SetScrollPercent", "ScrollIntoView"],
        properties: ["HorizontalScrollPercent", "VerticalScrollPercent",
                     "HorizontalViewSize", "VerticalViewSize",
                     "HorizontallyScrollable", "VerticallyScrollable"]
    }

    catalog["Grid"] := {
        methods: ["GetItem"],
        properties: ["RowCount", "ColumnCount"]
    }

    catalog["GridItem"] := {
        properties: ["Row", "Column", "RowSpan", "ColumnSpan", "ContainingGrid"]
    }

    catalog["Table"] := {
        methods: ["GetRowHeaders", "GetColumnHeaders"],
        properties: ["RowOrColumnMajor"]
    }

    catalog["TableItem"] := {
        methods: ["GetRowHeaderItems", "GetColumnHeaderItems"]
    }

    catalog["Window"] := {
        methods: ["Close", "WaitForInputIdle", "SetWindowVisualState"],
        properties: ["CanMaximize", "CanMinimize", "IsModal", "IsTopmost",
                     "WindowVisualState", "WindowInteractionState"]
    }

    catalog["Transform"] := {
        methods: ["Move", "Resize", "Rotate"],
        properties: ["CanMove", "CanResize", "CanRotate"]
    }

    catalog["RangeValue"] := {
        methods: ["SetValue"],
        properties: ["Value", "IsReadOnly", "Maximum", "Minimum",
                     "LargeChange", "SmallChange"]
    }

    catalog["Dock"] := {
        methods: ["SetDockPosition"],
        properties: ["DockPosition"]
    }

    catalog["MultipleView"] := {
        methods: ["GetViewName", "SetView"],
        properties: ["CurrentView"]
    }

    catalog["LegacyIAccessible"] := {
        methods: ["Select", "DoDefaultAction", "SetValue"],
        properties: ["ChildId", "Name", "Value", "Description", "Role", "State"]
    }

    catalog["Text"] := {
        methods: ["RangeFromPoint", "RangeFromChild", "GetSelection", "GetVisibleRanges"],
        properties: ["DocumentRange", "SupportedTextSelection"]
    }

    catalog["Drag"] := {
        properties: ["IsGrabbed", "DropEffect", "DropEffects"]
    }

    catalog["DropTarget"] := {
        properties: ["DropTargetEffect", "DropTargetEffects"]
    }

    catalog["ScrollItem"] := {
        methods: ["ScrollIntoView"]
    }

    return catalog
}

/**
 * uia_perform_action — execute an action on a resolved UIA element.
 *
 * Supported actions: Invoke, Toggle, Click, Expand, Collapse, Select,
 * ScrollIntoView, SetFocus, Highlight, SetValue.
 *
 * @param {Object} params - locator + action + optional value
 * @returns {Object} Result with success flag and action performed
 */
_HandlePerformAction(params)
{
    el := _ResolveLocator(params)

    action := params.Has("action") ? params["action"] : ""
    if (action = "")
        throw Error("action is required")

    value := params.Has("value") ? params["value"] : ""

    switch action
    {
    case "Invoke":
        try el.Invoke()
        catch Error as invokeErr
            throw Error("Invoke failed: " invokeErr.Message)
        return {success: true, action: "Invoke"}

    case "Toggle":
        try el.Toggle()
        catch Error as toggleErr
            throw Error("Toggle failed: " toggleErr.Message)
        return {success: true, action: "Toggle"}

    case "Click":
        try el.Click()
        catch Error as clickErr
            throw Error("Click failed: " clickErr.Message)
        return {success: true, action: "Click"}

    case "Expand":
        try el.Expand()
        catch Error as expandErr
            throw Error("Expand failed: " expandErr.Message)
        return {success: true, action: "Expand"}

    case "Collapse":
        try el.Collapse()
        catch Error as collapseErr
            throw Error("Collapse failed: " collapseErr.Message)
        return {success: true, action: "Collapse"}

    case "Select":
        try el.Select()
        catch Error as selectErr
            throw Error("Select failed: " selectErr.Message)
        return {success: true, action: "Select"}

    case "ScrollIntoView":
        try el.ScrollIntoView()
        catch Error as scrollErr
            throw Error("ScrollIntoView failed: " scrollErr.Message)
        return {success: true, action: "ScrollIntoView"}

    case "SetFocus":
        try el.SetFocus()
        catch Error as focusErr
            throw Error("SetFocus failed: " focusErr.Message)
        return {success: true, action: "SetFocus"}

    case "Highlight":
        try el.Highlight()
        catch Error as hlErr
            throw Error("Highlight failed: " hlErr.Message)
        return {success: true, action: "Highlight"}

    case "SetValue":
        if (value = "")
            throw Error("value is required for SetValue action")
        try el.SetValue(value)
        catch Error as svErr
            throw Error("SetValue failed: " svErr.Message)
        return {success: true, action: "SetValue", value: value}

    default:
        throw Error("Unknown action: " action
            . ". Supported: Invoke, Toggle, Click, Expand, Collapse, Select, ScrollIntoView, SetFocus, Highlight, SetValue")
    }
}

/**
 * uia_set_value — set the value of a UIA element (Edit field, checkbox, etc.).
 *
 * @param {Object} params - locator + value
 * @returns {Object} Result with success flag
 */
_HandleSetValue(params)
{
    el := _ResolveLocator(params)

    if (!params.Has("value"))
        throw Error("value is required")

    value := params["value"]
    try el.SetValue(value)
    catch Error as err
        throw Error("SetValue failed: " err.Message)

    return {success: true, value: value}
}

/**
 * uia_highlight_element — draw a colored highlight border around an element.
 *
 * @param {Object} params - locator + optional duration (ms) and color
 * @returns {Object} Result with success flag
 */
_HandleHighlightElement(params)
{
    el := _ResolveLocator(params)

    duration := params.Has("duration") ? params["duration"] : 2000
    color := params.Has("color") ? params["color"] : ""

    try
    {
        if (color != "")
            el.Highlight(duration, color)
        else
            el.Highlight(duration)
    }
    catch Error as err
        throw Error("Highlight failed: " err.Message)

    return {success: true, duration: duration}
}

/**
 * uia_dump_tree — return a comprehensive text dump of an element and its descendants.
 *
 * @param {Object} params - locator (hwnd required, or uses focused element)
 * @returns {Object} Result with formatted dump string
 */
_HandleDumpTree(params)
{
    hwnd := params.Has("hwnd") ? params["hwnd"] : 0
    maxDepth := params.Has("maxDepth") ? params["maxDepth"] : 0

    el := 0
    if (hwnd)
    {
        cr := _MakeCacheRequest()
        el := UIA.ElementFromHandle(hwnd, cr)
    }
    else
    {
        el := UIA.GetFocusedElement()
    }
    if (!el)
        throw Error("Could not resolve element for dump")

    try
    {
        if (maxDepth > 0)
            dump := el.DumpAll("`n", maxDepth)
        else
            dump := el.DumpAll()
        return {dump: dump}
    }
    catch Error as err
        throw Error("DumpAll failed: " err.Message)
}

/**
 * uia_wait_element_not_exist — poll until an element matching condition disappears or timeout.
 *
 * @param {Object} params - must include condition; optional hwnd, timeout
 * @returns {Object} Result with gone flag and elapsed ms
 */
_HandleWaitElementNotExist(params)
{
    timeout := params.Has("timeout") ? params["timeout"] : 5000
    hwnd := params.Has("hwnd") ? params["hwnd"] : 0
    condObj := params.Has("condition") ? params["condition"] : {}

    condMap := _BuildCondition(condObj)
    if (condMap = "")
        throw Error("condition is required")

    scope := _ResolveScope(params.Has("scope") ? params["scope"] : "Descendants")
    matchMode := _ResolveMatchMode(params.Has("matchMode") ? params["matchMode"] : "Exact")

    root := 0
    if (hwnd)
    {
        cr := _MakeCacheRequest()
        root := UIA.ElementFromHandle(hwnd, cr)
    }
    else
    {
        root := UIA.GetFocusedElement()
    }
    if (!root)
        throw Error("Could not resolve root")

    start := A_TickCount
    loop
    {
        try
        {
            matches := root.FindAll(condMap, matchMode, scope)
            if (!IsObject(matches) || matches.Length = 0)
            {
                return {
                    gone: true,
                    elapsed: A_TickCount - start
                }
            }
        }
        if (A_TickCount - start >= timeout)
            break
        Sleep(100)
    }

    return {
        gone: false,
        elapsed: A_TickCount - start
    }
}

/**
 * uia_element_exists — check if an element matching condition exists without throwing.
 *
 * @param {Object} params - must include condition; optional hwnd, scope, matchMode
 * @returns {Object} Result with exists flag
 */
_HandleElementExists(params)
{
    root := 0
    if (params.Has("hwnd") && params["hwnd"])
    {
        cr := _MakeCacheRequest()
        root := UIA.ElementFromHandle(params["hwnd"], cr)
    }
    else
    {
        root := UIA.GetFocusedElement()
    }
    if (!root)
        return {exists: false}

    condMap := _BuildCondition(params.Has("condition") ? params["condition"] : {})
    if (condMap = "")
        return {exists: false}

    scope := _ResolveScope(params.Has("scope") ? params["scope"] : "Descendants")
    matchMode := _ResolveMatchMode(params.Has("matchMode") ? params["matchMode"] : "Exact")

    try
    {
        matches := root.FindAll(condMap, matchMode, scope)
        if (IsObject(matches) && matches.Length > 0)
        {
            summary := _ElementSummary(matches[1])
            return {
                exists: true,
                count: matches.Length,
                example: summary
            }
        }
        return {exists: false, count: 0}
    }
    catch Error as e
    {
        return {exists: false, count: 0}
    }
}

; ══════════════════════════════════════════════════════════════════
;  Phase 3 Handlers — path navigation, root element, Chromium
; ══════════════════════════════════════════════════════════════════

/**
 * Walk the UIA tree from a starting element using a path string.
 *
 * Supported path formats:
 *   "3,2"                       — comma-separated child indices (TreeWalkerTrue)
 *   "/Name1/Name2"              — slash-separated named segments (FindFirst by Name)
 *   "/0/1[@AutomationId='X']"  — numeric child indices with condition filter on last
 *   "//*[@AutomationId='X']"   — descendant search using FindFirst with condition
 *   "{Type:50010, Name:'foo'}" — condition object applied to starting element's descendants
 *   "/"                         — return starting element itself
 *
 * @param {UIA.Element} startEl - element to start navigation from
 * @param {String} path - path string to walk
 * @returns {UIA.Element} The element at the resolved path
 */
_ElementFromPath(startEl, path)
{
    ; Empty path or root marker — return starting element
    if (path = "" || path = "/")
        return startEl

    path := Trim(path)

    ; ── Format 1: condition object string "{Type:50010, Name:'foo'}" ──
    if (SubStr(path, 1, 1) = "{")
    {
        condObj := _ParseConditionString(path)
        el := startEl.FindFirst(condObj, , UIA_TreeScope.Descendants)
        if (!el)
            throw Error("No descendant matching condition: " path)
        return el
    }

    ; ── Format 2: descendant search "//*[@AutomationId='X']" ──
    if (SubStr(path, 1, 2) = "//")
    {
        rest := SubStr(path, 3)
        condObj := _ParseXPathCondition(rest)
        el := (condObj = "")
            ? startEl.FindFirst("", , UIA_TreeScope.Descendants)
            : startEl.FindFirst(condObj, , UIA_TreeScope.Descendants)
        if (!el)
            throw Error("No descendant found: " path)
        return el
    }

    ; ── Formats 3 & 4: slash-separated or comma-separated ──
    ; Detect delimiter: comma-separated if no leading slash and contains commas
    segments := []
    if (SubStr(path, 1, 1) = "/")
    {
        ; Slash-separated: /Name1/Name2 or /0/1[@AutoId='X']
        raw := SubStr(path, 2)  ; strip leading /
        ; Split on / but not inside brackets
        segments := _SplitPathSegments(raw)
    }
    else if (InStr(path, ","))
    {
        ; Comma-separated: 3,2,1
        for part in StrSplit(path, ",")
            segments.Push(Trim(part))
    }
    else
    {
        ; Single segment
        segments.Push(path)
    }

    el := startEl
    for seg in segments
    {
        seg := Trim(seg)
        if (seg = "")
            continue

        ; Parse optional condition suffix: 0[@AutomationId='X']
        idx := ""
        condStr := ""
        if (RegExMatch(seg, "^(\\d+)(\\[.+\\])?$", &m))
        {
            idx := Integer(m[1])
            condStr := (m.Count >= 2 && m[2] != "") ? m[2] : ""
        }
        else if (RegExMatch(seg, "^([^\\[]+)(\\[.+\\])?$", &m))
        {
            ; Named segment: Name[@Condition]
            name := m[1]
            condStr := (m.Count >= 2 && m[2] != "") ? m[2] : ""

            condObj := {Name: name}
            if (condStr != "")
            {
                subObj := _ParseXPathCondition(condStr)
                if (subObj != "")
                {
                    ; Merge sub-condition properties into condObj
                    for k, v in (subObj is Object ? subObj.OwnProps() : [])
                        condObj.%k% := v
                }
            }
            child := el.FindFirst(condObj, , UIA_TreeScope.Children)
            if (!child)
                throw Error("Child not found: '" seg "' under " _ElName(el))
            el := child
            continue
        }

        ; Numeric index + optional condition
        condObj := (condStr != "") ? _ParseXPathCondition(condStr) : ""

        ; Get children matching condition, take the idx-th one
        children := el.FindAll(condObj, , UIA_TreeScope.Children)
        if (children.Length <= idx)
            throw Error("Index " idx " out of range (found " children.Length " children) for: " seg)
        el := children[idx + 1]  ; AHK arrays are 1-indexed
    }

    return el
}

/**
 * Parse a condition string like "{Type:50010, AutomationId:'mMainMenuStrip'}".
 * Returns a plain Object suitable for FindFirst/FindAll.
 */
_ParseConditionString(s)
{
    ; Strip outer braces
    s := Trim(s)
    if (SubStr(s, 1, 1) = "{")
        s := SubStr(s, 2, -1)

    condObj := {}
    ; Split on commas not inside quotes
    pos := 1
    inQuote := false
    start := 1
    while (pos <= StrLen(s))
    {
        ch := SubStr(s, pos, 1)
        if (ch = "'" || ch = '"')
            inQuote := !inQuote
        else if (!inQuote && ch = ",")
        {
            pair := Trim(SubStr(s, start, pos - start))
            if (pair != "")
                _AddConditionPairObj(condObj, pair)
            start := pos + 1
        }
        pos++
    }
    ; Last pair
    pair := Trim(SubStr(s, start))
    if (pair != "")
        _AddConditionPairObj(condObj, pair)

    return condObj
}

_AddConditionPairObj(obj, pair)
{
    if (!RegExMatch(pair, "^\\s*(\\w+)\\s*:\\s*(.+)\\s*$", &m))
        return

    prop := m[1]
    val := Trim(m[2])

    ; Strip quotes from string values
    if (SubStr(val, 1, 1) = "'" || SubStr(val, 1, 1) = '"')
        val := SubStr(val, 2, -1)

    ; Try numeric conversion for Type/ControlType/ProcessId
    if (prop = "Type" || prop = "ControlType" || prop = "ProcessId")
    {
        try
            val := Integer(val)
    }

    obj.%prop% := val
}

/**
 * Parse an XPath-style condition like "[@AutomationId='SettingsButton']".
 * Returns a plain Object suitable for FindFirst/FindAll, or "" if no condition.
 */
_ParseXPathCondition(s)
{
    s := Trim(s)

    ; Strip leading "//*" if present
    if (SubStr(s, 1, 3) = "//*")
        s := SubStr(s, 4)

    if (s = "" || s = "*")
        return ""

    ; Strip brackets: [@AutomationId='SettingsButton']
    if (SubStr(s, 1, 1) = "[")
        s := SubStr(s, 2)
    if (SubStr(s, -1) = "]")
        s := SubStr(s, 1, -1)

    ; Remove @ prefix
    if (SubStr(s, 1, 1) = "@")
        s := SubStr(s, 2)

    ; Split on = (prop='value' or prop="value")
    if (!RegExMatch(s, "^\\s*(\\w+)\\s*=\\s*(.+)\\s*$", &m))
        return ""

    prop := m[1]
    val := Trim(m[2])

    ; Strip quotes
    if (SubStr(val, 1, 1) = "'" || SubStr(val, 1, 1) = '"')
        val := SubStr(val, 2, -1)

    ; Try numeric conversion
    if (prop = "Type" || prop = "ControlType" || prop = "ProcessId")
    {
        try
            val := Integer(val)
    }

    condObj := {}
    condObj.%prop% := val
    return condObj
}

/**
 * Split a path like "0/1[@AutoId='X']/2" into segments, respecting brackets.
 */
_SplitPathSegments(path)
{
    segments := []
    current := ""
    depth := 0
    for i, ch in StrSplit(path)
    {
        if (ch = "[" || ch = "{")
            depth++
        else if (ch = "]" || ch = "}")
            depth--

        if (ch = "/" && depth = 0)
        {
            if (current != "")
                segments.Push(current)
            current := ""
        }
        else
        {
            current .= ch
        }
    }
    if (current != "")
        segments.Push(current)
    return segments
}

/**
 * Get a human-readable name for an element for error messages.
 */
_ElName(el)
{
    try return el.Name
    catch Error as e
        return "(unnamed)"
}

/**
 * uia_get_element_from_path — navigate the UIA tree using path syntax.
 *
 * Supports comma-separated numeric paths ("3,2" = third child's second child),
 * slash-separated named paths ("/MenuBar/SettingsButton"),
 * XPath-like conditions ("//*[@AutomationId='X']"),
 * and condition object strings ("{Type:50010, Name:'foo'}").
 *
 * @param {Object} params - must include hwnd and path
 * @returns {Map} Full element result for the element at the path
 */
_HandleGetElementFromPath(params)
{
    if (!params.Has("hwnd") || !params["hwnd"])
        throw Error("hwnd is required for get_element_from_path")

    if (!params.Has("path") || params["path"] = "")
        throw Error("path is required for get_element_from_path")

    hwnd := params["hwnd"]
    if (hwnd is String)
        hwnd := Integer(hwnd)

    path := params["path"]

    cr := _MakeCacheRequest()
    windowEl := UIA.ElementFromHandle(hwnd, cr)

    el := 0
    try
    {
        ; Walk the UIA tree using the path syntax.
        ; Supports:
        ;   "3,2"            — comma-separated child indices
        ;   "/Name1/Name2"    — slash-separated named segments (FindFirst by Name)
        ;   "/0/1[@AutoId='X']" — numeric index then condition-filtered child
        ;   "//*[@AutoId='X']" — descendant search with condition
        ;   "{Type:50010,...}" — condition object (applied to windowEl's descendants)
        el := _ElementFromPath(windowEl, path)
    }
    catch Error as err
        throw Error("ElementFromPath failed: " err.Message . " — path: " path)

    if (!el)
        throw Error("No element found at path: " path)

    targetPid := WinGetPID("ahk_id " hwnd)
    return _BuildFullElementResult(el, windowEl, hwnd, targetPid)
}

/**
 * uia_get_root_element — get the desktop root element for cross-application searches.
 *
 * @returns {Map} Element summary for the desktop root
 */
_HandleGetRootElement(params)
{
    global UIA
    try
    {
        root := UIA.GetRootElement()
        if (!root)
            throw Error("GetRootElement returned nothing")

        return {
            Type:         _PropStr(root, 30003),
            Name:         _PropStr(root, 30005),
            AutomationId: _PropStr(root, 30011),
            ClassName:    _PropStr(root, 30012),
            FrameworkId:  _PropStr(root, 30024),
            IsEnabled:    _PropBool(root, 30010),
            ProcessId:    _PropInt(root, 30002),
            NativeWindowHandle: _PropHwnd(root, 30020)
        }
    }
    catch Error as err
        throw Error("GetRootElement failed: " err.Message)
}

/**
 * uia_element_from_chromium — get the Chromium content element for browser automation.
 *
 * Activates Chromium accessibility and returns the render widget element
 * (Chrome_RenderWidgetHostHWND1) for Chrome/Edge/Brave.
 *
 * @param {Object} params - must include hwnd of the browser window
 * @returns {Map} Full element result for the Chromium content element
 */
_HandleElementFromChromium(params)
{
    if (!params.Has("hwnd") || !params["hwnd"])
        throw Error("hwnd is required for element_from_chromium")

    hwnd := params["hwnd"]
    if (hwnd is String)
        hwnd := Integer(hwnd)

    targetPid := WinGetPID("ahk_id " hwnd)

    if (!_IsChromiumWindow(hwnd))
        throw Error("The specified window is not a Chromium-based application. "
            . "This tool works with Chrome, Edge, Brave, and Electron apps "
            . "(Signal, Discord, VS Code, Teams, Slack, etc.)")

    try
    {
        UIA.ActivateChromiumAccessibility(hwnd)
    }
    catch Error as err
        throw Error("ActivateChromiumAccessibility failed: " err.Message)

    cr := _MakeCacheRequest()
    el := 0
    try
    {
        el := UIA.ElementFromChromium(hwnd, false, cr)
    }
    catch Error as err
        throw Error("ElementFromChromium failed: " err.Message)

    if (!el)
        throw Error("Could not get Chromium content element — browser may not have accessibility enabled")

    windowEl := UIA.ElementFromHandle(hwnd, cr)
    return _BuildFullElementResult(el, windowEl, hwnd, targetPid)
}

; ══════════════════════════════════════════════════════════════════
;  Utility Handlers — state enums, window management, screenshot, recipes
; ══════════════════════════════════════════════════════════════════

/**
 * uia_get_state_enums — return well-known UIA state value → name mappings.
 *
 * Critical for LLM code generation: without this, the LLM guesses whether
 * ToggleState 1 means "On" or "Off", and generates broken conditional logic.
 *
 * @returns {Object} State name → {value: name} mappings
 */
_HandleGetStateEnums(params)
{
    enums := Map()

    enums["ToggleState"] := Map(
        0, "Off",
        1, "On",
        2, "Indeterminate"
    )

    enums["ExpandCollapseState"] := Map(
        0, "Collapsed",
        1, "Expanded",
        2, "PartiallyExpanded",
        3, "LeafNode"
    )

    enums["WindowVisualState"] := Map(
        0, "Normal",
        1, "Maximized",
        2, "Minimized"
    )

    enums["WindowInteractionState"] := Map(
        0, "Running",
        1, "Closing",
        2, "ReadyForUserInteraction",
        3, "BlockedByModalWindow",
        4, "NotResponding"
    )

    enums["Orientation"] := Map(
        0, "None",
        1, "Horizontal",
        2, "Vertical"
    )

    enums["RowOrColumnMajor"] := Map(
        0, "RowMajor",
        1, "ColumnMajor"
    )

    enums["DockPosition"] := Map(
        0, "Top",
        1, "Left",
        2, "Bottom",
        3, "Right",
        4, "Fill",
        5, "None"
    )

    enums["SupportedTextSelection"] := Map(
        0, "None",
        1, "Single",
        2, "Multiple"
    )

    enums["LiveSetting"] := Map(
        0, "Off",
        1, "Polite",
        2, "Assertive"
    )

    enums["ZoomUnit"] := Map(
        0, "NoAmount",
        1, "LargeDecrement",
        2, "SmallDecrement",
        3, "LargeIncrement",
        4, "SmallIncrement"
    )

    return enums
}

/**
 * uia_manage_window — perform window lifecycle operations.
 *
 * Supported actions: Activate, Minimize, Maximize, Restore, Close, Move, Resize.
 * For Move: provide x and y. For Resize: provide width and height.
 *
 * @param {Object} params - must include hwnd and action
 * @returns {Object} Result with success flag
 */
_HandleManageWindow(params)
{
    if (!params.Has("hwnd") || !params["hwnd"])
        throw Error("hwnd is required")

    action := params.Has("action") ? params["action"] : ""
    if (action = "")
        throw Error("action is required")

    hwnd := params["hwnd"]
    if (hwnd is String)
        hwnd := Integer(hwnd)

    switch action
    {
    case "Activate":
        WinActivate("ahk_id " hwnd)
        WinWaitActive("ahk_id " hwnd,, 2)
        return {success: true, action: "Activate"}

    case "Minimize":
        WinMinimize("ahk_id " hwnd)
        return {success: true, action: "Minimize"}

    case "Maximize":
        WinMaximize("ahk_id " hwnd)
        return {success: true, action: "Maximize"}

    case "Restore":
        WinRestore("ahk_id " hwnd)
        return {success: true, action: "Restore"}

    case "Close":
        WinClose("ahk_id " hwnd)
        return {success: true, action: "Close"}

    case "Move":
        if (!params.Has("x") || !params.Has("y"))
            throw Error("x and y are required for Move action")
        WinMove(params["x"], params["y"],,, "ahk_id " hwnd)
        return {success: true, action: "Move", x: params["x"], y: params["y"]}

    case "Resize":
        if (!params.Has("width") || !params.Has("height"))
            throw Error("width and height are required for Resize action")
        WinMove(,, params["width"], params["height"], "ahk_id " hwnd)
        return {success: true, action: "Resize", width: params["width"], height: params["height"]}

    default:
        throw Error("Unknown window action: " action
            . ". Supported: Activate, Minimize, Maximize, Restore, Close, Move, Resize")
    }
}

/**
 * uia_capture_screenshot — capture a screenshot of a window.
 *
 * Captures the client area to a BMP file and returns the path.
 * Uses native GDI DllCalls — no external library required.
 *
 * @param {Object} params - must include hwnd, optional filePath
 * @returns {Object} Result with filePath of the captured screenshot
 */
_HandleCaptureScreenshot(params)
{
    if (!params.Has("hwnd") || !params["hwnd"])
        throw Error("hwnd is required")

    hwnd := params["hwnd"]
    if (hwnd is String)
        hwnd := Integer(hwnd)

    ; Determine output path — always use .bmp (GDI limitation)
    filePath := params.Has("filePath") ? params["filePath"]
        : A_Temp "\UIA_Screenshot_" FormatTime(A_Now, "yyyyMMdd-HHmmss") ".bmp"
    ; Force .bmp extension regardless of input
    if (!InStr(filePath, ".bmp"))
        filePath .= ".bmp"

    ; Get window dimensions
    try WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    catch Error as err
        throw Error("Could not get window position: " err.Message)

    if (w <= 0 || h <= 0)
        throw Error("Window has zero size — cannot capture")

    ; Try window DC first (GDI windows).  Falls back to screen DC for
    ; D3D/DirectComposition surfaces (Electron, Chromium, UWP, WPF).
    ; PrintWindow returns error 2 on D3D swap chains — screen BitBlt
    ; captures whatever is visible regardless of rendering backend.
    hdcWindow := DllCall("GetWindowDC", "Ptr", hwnd, "Ptr")
    useScreenDC := false
    if (!hdcWindow)
    {
        ; Window DC unavailable — use screen DC
        hdcWindow := DllCall("GetDC", "Ptr", 0, "Ptr")
        useScreenDC := true
    }

    hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcWindow, "Ptr")
    hBitmap := DllCall("CreateCompatibleBitmap", "Ptr", hdcWindow, "Int", w, "Int", h, "Ptr")
    oldBitmap := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hBitmap, "Ptr")

    result := DllCall("PrintWindow", "Ptr", hwnd, "Ptr", hdcMem, "UInt", 0, "Int")
    if (!result)
    {
        ; PrintWindow failed — use BitBlt.
        ; If using screen DC, translate to screen coordinates.
        if (useScreenDC)
        {
            DllCall("BitBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", w, "Int", h,
                    "Ptr", hdcWindow, "Int", x, "Int", y, "UInt", 0x00CC0020)
        }
        else
        {
            DllCall("BitBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", w, "Int", h,
                    "Ptr", hdcWindow, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
        }
    }

    ; Save to BMP file
    _SaveBitmapToFile(hBitmap, filePath, w, h)

    ; Cleanup
    DllCall("SelectObject", "Ptr", hdcMem, "Ptr", oldBitmap)
    DllCall("DeleteObject", "Ptr", hBitmap)
    DllCall("DeleteDC", "Ptr", hdcMem)
    if (useScreenDC)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcWindow)
    else
        DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdcWindow)

    return {success: true, filePath: filePath, width: w, height: h}
}

/**
 * Save a GDI bitmap handle to a BMP file on disk.
 *
 * @param {Integer} hBitmap - GDI bitmap handle
 * @param {String} filePath - output file path
 * @param {Integer} width - image width
 * @param {Integer} height - image height
 */
_SaveBitmapToFile(hBitmap, filePath, width, height)
{
    ; Get bitmap bits
    biSize := 40
    bitsSize := width * height * 4
    fileHeaderSize := 14

    bmi := Buffer(biSize, 0)
    NumPut("Int", biSize, bmi, 0)
    NumPut("Int", width, bmi, 4)
    NumPut("Int", -height, bmi, 8)  ; negative = top-down
    NumPut("UShort", 1, bmi, 12)
    NumPut("UShort", 32, bmi, 14)   ; 32-bit

    bits := Buffer(bitsSize, 0)
    hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    DllCall("GetDIBits", "Ptr", hdc, "Ptr", hBitmap, "UInt", 0, "UInt", height,
            "Ptr", bits, "Ptr", bmi, "UInt", 0)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)

    ; Write BMP file
    fileHeader := Buffer(fileHeaderSize, 0)
    NumPut("UShort", 0x4D42, fileHeader, 0)  ; "BM"
    NumPut("UInt", fileHeaderSize + biSize + bitsSize, fileHeader, 2)
    NumPut("UInt", fileHeaderSize + biSize, fileHeader, 10)

    if (FileExist(filePath))
        FileDelete(filePath)
    f := FileOpen(filePath, "w")
    f.RawWrite(fileHeader, fileHeaderSize)
    f.RawWrite(bmi, biSize)
    f.RawWrite(bits, bitsSize)
    f.Close()
}

/**
 * uia_get_code_recipe — return proven AHK v2 code templates for common automation scenarios.
 *
 * @param {Object} params - must include recipe name
 * @returns {Object} Recipe with name, description, and ahkCode
 */
_HandleGetCodeRecipe(params)
{
    recipe := params.Has("recipe") ? params["recipe"] : ""
    if (recipe = "")
        throw Error("recipe is required. Available recipes: " _ListRecipes())

    switch recipe
    {
    case "activate_window":
        return {
            name: "activate_window",
            description: "Activate a window and get its UIA element",
            ahkCode: 'WinActivate("Window Title ahk_exe target.exe")`n'
                . 'WinWaitActive("Window Title ahk_exe target.exe")`n'
                . 'winEl := UIA.ElementFromHandle("Window Title ahk_exe target.exe")'
        }

    case "find_and_click":
        return {
            name: "find_and_click",
            description: "Find a button and click it with error handling",
            ahkCode: 'try {`n'
                . '    btn := winEl.WaitElement({Type: "Button", Name: "OK"},, 5000)`n'
                . '    btn.Click()`n'
                . '    Sleep(200)`n'
                . '} catch Error as err {`n'
                . '    MsgBox("Failed: " err.Message)`n'
                . '}'
        }

    case "menu_navigate":
        return {
            name: "menu_navigate",
            description: "Navigate a native menu: File → Open with submenu handling",
            ahkCode: '; Expand top-level menu`n'
                . 'winEl.FindFirst({Type: "MenuItem", Name: "File"}).Expand()`n'
                . 'Sleep(200)`n'
                . '; The submenu is a separate #32768 popup window`n'
                . 'popup := UIA.ElementFromHandle("ahk_class #32768")`n'
                . 'popup.FindFirst({Type: "MenuItem", Name: "Open..."}).Invoke()`n'
                . 'Sleep(300)'
        }

    case "dialog_fill":
        return {
            name: "dialog_fill",
            description: "Fill fields in a dialog and submit",
            ahkCode: '; Wait for dialog to appear`n'
                . 'dlgEl := UIA.ElementFromHandle("Dialog Title ahk_class #32770")`n'
                . '; Fill fields`n'
                . 'dlgEl.FindFirst({Type: "Edit", AutomationId: "nameField"}).SetValue("John Doe")`n'
                . 'dlgEl.FindFirst({Type: "ComboBox", Name: "Country"}).SetValue("Canada")`n'
                . '; Click OK`n'
                . 'dlgEl.FindFirst({Type: "Button", Name: "OK"}).Invoke()`n'
                . 'Sleep(200)'
        }

    case "tree_explore":
        return {
            name: "tree_explore",
            description: "Expand tree nodes and select a leaf item",
            ahkCode: '; Find and expand tree nodes`n'
                . 'tree := winEl.FindFirst({Type: "Tree"})`n'
                . 'node := tree.FindFirst({Type: "TreeItem", Name: "Parent Node"})`n'
                . 'node.Expand()`n'
                . 'Sleep(100)`n'
                . '; Select child item`n'
                . 'child := node.FindFirst({Type: "TreeItem", Name: "Child Item"},, UIA.TreeScope.Children)`n'
                . 'child.Select()'
        }

    case "grid_read":
        return {
            name: "grid_read",
            description: "Iterate a DataGrid and read cell values",
            ahkCode: 'grid := winEl.FindFirst({Type: "DataGrid"})`n'
                . 'rows := grid.FindAll({Type: "DataItem"})`n'
                . 'for row in rows {`n'
                . '    cells := row.FindAll({Type: "Text"},, UIA.TreeScope.Children)`n'
                . '    for cell in cells`n'
                . '        OutputDebug cell.Name`n'
                . '}'
        }

    case "wait_and_click":
        return {
            name: "wait_and_click",
            description: "Wait for an element, click it, and wait for a result element",
            ahkCode: '; Wait for button to appear`n'
                . 'btn := winEl.WaitElement({Type: "Button", Name: "Submit"},, 10000)`n'
                . 'if !btn`n'
                . '    throw Error("Submit button never appeared")`n'
                . 'btn.Click()`n'
                . 'Sleep(300)`n'
                . '; Wait for result to appear`n'
                . 'result := winEl.WaitElement({Type: "Text", Name: "Success"},, 5000)`n'
                . 'if result`n'
                . '    MsgBox("Operation completed")'
        }

    case "combo_select":
        return {
            name: "combo_select",
            description: "Expand a ComboBox and select an item by name",
            ahkCode: 'combo := winEl.FindFirst({Type: "ComboBox", AutomationId: "countrySelect"})`n'
                . 'combo.Expand()`n'
                . 'Sleep(100)`n'
                . '; Find the popup list and select an item`n'
                . 'combo.FindFirst({Type: "ListItem", Name: "Canada"}).Select()'
        }

    case "list_recipes":
        return {
            name: "list_recipes",
            description: "Available recipe names",
            recipes: _ListRecipes()
        }

    default:
        throw Error("Unknown recipe: " recipe . ". Available: " _ListRecipes())
    }
}

_ListRecipes()
{
    return "activate_window, find_and_click, menu_navigate, dialog_fill, "
        . "tree_explore, grid_read, wait_and_click, combo_select, list_recipes"
}

/**
 * uia_get_element_code — return a runnable AHK v2 code snippet that targets a
 * specific element using the standard locator. Resolves the element, builds its
 * condition string, infers the best action, and returns a complete script that the
 * user can save and run directly.
 *
 * The generated code follows the same style as UIA_Inspector's "Add Element" button:
 * a self-contained script with Main()/ExitApp, local variable assignments, and the
 * action called on the resolved element.
 *
 * @param {Object} params - standard locator: hwnd, condition, scope, matchMode, index
 * @returns {Object} {ahkCode: "..."} with the full AHK v2 script
 */
_HandleGetElementCode(params)
{
    el := _ResolveLocator(params)

    ; Get the window HWND for title resolution
    hwnd := 0
    try hwnd := el.CurrentNativeWindowHandle
    if (!hwnd)
        try hwnd := el.GetPropertyValue(30020)

    ; Build the winTitle string (title ahk_exe exeName)
    winTitle := ""
    try
    {
        title := WinGetTitle(hwnd)
        exe := ProcessGetName(WinGetPID("ahk_id " hwnd))
        winTitle := title " ahk_exe " exe
    }
    if (!winTitle)
        winTitle := "ahk_id " hwnd

    ; Build condition and action
    condStr := _BuildConditionString(el)
    action := _DetermineAction(el)

    ; Assemble FindFirst arguments: condition + matchMode + optional scope
    mm := params.Has("matchMode") ? params["matchMode"] : "Exact"
    sc := params.Has("scope") ? params["scope"] : ""
    findArgs := condStr ', "' mm '"'
    if (sc && sc != "Descendants")
        findArgs .= ', UIA.TreeScope.' sc

    ; Assemble the complete AHK v2 script
    code := '#Requires AutoHotkey v2.0.2+`n'
    code .= '#Include <UIA>`n'
    code .= 'Main()`n'
    code .= 'ExitApp`n'
    code .= '`n'
    code .= 'Main()`n'
    code .= '{`n'
    code .= '    local winEl := UIA.ElementFromHandle("' winTitle '")`n'
    code .= '    local el := winEl.FindFirst(' findArgs ')`n'
    code .= '    el.' action '`n'
    code .= '}'

    return Map("ahkCode", code)
}

; ══════════════════════════════════════════════════════════════════
;  Full Element Result Builder (used by multiple handlers)
; ══════════════════════════════════════════════════════════════════

_BuildFullElementResult(el, windowEl, hwnd, targetPid)
{
    global UIA
    props := _ElementToMap(el)
    patterns := _GetPatterns(el)
    ancestors := _GetAncestorChain(el)
    action := _DetermineAction(el)
    condition := _BuildConditionString(el)

    result := Map()
    for k, v in props
        result[k] := v
    result["Patterns"] := patterns
    result["AncestorChain"] := ancestors
    result["InferredAction"] := action
    result["ConditionString"] := condition

    ; Window info
    if (hwnd) {
        try
        {
            result["WindowTitle"] := WinGetTitle(hwnd)
            result["WindowClass"] := WinGetClass(hwnd)
            result["WindowExe"] := ProcessGetName(targetPid ? targetPid : WinGetPID("ahk_id " hwnd))
        }
    }

    return(result)
}

; ══════════════════════════════════════════════════════════════════
;  TCP Server
; ══════════════════════════════════════════════════════════════════

_HandleRequest(jsonStr)
{
    ; Parse JSON
    request := ""
    try request := JSON.Parse(jsonStr)
    catch Error as e {
        engineLog.Error("JSON parse error: " SubStr(jsonStr, 1, 200))
        return(_RpcError("", -32700, "Parse error"))
    }

    id := request.Has("id") ? request["id"] : ""
    method := request.Has("method") ? request["method"] : ""
    params := request.Has("params") ? request["params"] : {}

    ; Method dispatch table
    static handlers := Map(
        "ping",                  (*) => "pong",
        "inspect_at_cursor",    _HandleInspectAtCursor,
        "inspect_element_at_cursor", _HandleInspectAtCursor,  ; MCP bridge name
        "get_focused_element",  _HandleGetFocusedElement,
        "find_element",         _HandleFindElement,
        "find_all_elements",    _HandleFindAllElements,
        "get_element_tree",     _HandleGetElementTree,
        "get_ancestor_chain",   _HandleGetAncestorChain,
        "get_element_properties", _HandleGetElementProperties,
        "get_element_patterns", _HandleGetElementPatterns,
        "list_windows",         _HandleListWindows,
        "get_window_info",      _HandleGetWindowInfo,
        "check_match_count",    _HandleCheckMatchCount,
        "get_child_elements",   _HandleGetChildElements,
        "inspect_bounding_rect",    _HandleGetBoundingRect,
        "inspect_element_wait",     _HandleWaitForElement,
        "inspect_element_at_point", _HandleGetElementAtPoint,
        "get_bounding_rect",    _HandleGetBoundingRect,    ; legacy alias
        "wait_for_element",     _HandleWaitForElement,     ; legacy alias
        "get_element_at_point", _HandleGetElementAtPoint,  ; legacy alias
        "get_full_element",     _HandleGetElementProperties,  ; alias
        "uia_get_type_catalog",     _HandleGetTypeCatalog,
        "uia_get_pattern_catalog",  _HandleGetPatternCatalog,
        "uia_perform_action",       _HandlePerformAction,
        "uia_set_value",            _HandleSetValue,
        "uia_highlight_element",    _HandleHighlightElement,
        "uia_dump_tree",            _HandleDumpTree,
        "uia_wait_element_not_exist",   _HandleWaitElementNotExist,
        "uia_element_exists",       _HandleElementExists,
        "uia_get_element_from_path", _HandleGetElementFromPath,
        "uia_get_root_element",      _HandleGetRootElement,
        "uia_element_from_chromium", _HandleElementFromChromium,
        "uia_get_state_enums",      _HandleGetStateEnums,
        "uia_manage_window",        _HandleManageWindow,
        "uia_capture_screenshot",   _HandleCaptureScreenshot,
        "uia_get_code_recipe",      _HandleGetCodeRecipe,
        "uia_get_element_code",     _HandleGetElementCode,
        "uia_detect_framework",     _HandleDetectFramework,
        "uia_get_pixel_color",      _HandleGetPixelColor,
        "uia_get_accessibility_warnings", _HandleGetAccessibilityWarnings,
        "shutdown",             (*) => (SetTimer(_DoShutdown, -1), "shutting down")
    )

    if (!handlers.Has(method)) {
        engineLog.Error("Method not found: " method)
        return(_RpcError(id, -32601, "Method not found: " method))
    }

    ; ── Truncated params for debug log ──────────
    ; Prevent log bloat from large payloads while still capturing
    ; enough to replay failing requests.
    paramsStr := ""
    try
    {
        s := JSON.Stringify(params, 0)
        paramsStr := StrLen(s) <= 1024 ? s : SubStr(s, 1, 1024) "… (len=" StrLen(s) ")"
    } catch Error as e
        paramsStr := "[serialization error]"

    tick := A_TickCount
    try
    {
        engineLog.Debug("Dispatching: " method " params=" paramsStr)
        result := handlers[method](params)
        elapsed := A_TickCount - tick
        engineLog.Debug("Completed: " method " (" elapsed "ms)")
        ; ── Slow operation warning ──────────────────
        ; Log a warning for operations exceeding 3s.
        ; Long FindAll calls (especially Descendants scope on
        ; large WinForms trees like BaseCamp) can indicate an
        ; impending COM hang or a condition that needs narrowing.
        if (elapsed > 3000)
            engineLog.Info("SLOW: " method " took " elapsed "ms params=" paramsStr)
        return(_RpcResult(id, result))
    }
    catch Error as err
    {
        elapsed := A_TickCount - tick
        errDetail := err.HasProp("What") ? " (" err.What ")" : ""
        engineLog.Error("Handler error [" method "] (" elapsed "ms): " err.Message . errDetail . " | params=" paramsStr)
        ; ── COM stabilisation ──────────────────────
        ; After a COM error (especially E_INVALIDARG from legacy
        ; UIA bridges like VB6), the COM apartment may be unstable.
        ; A short sleep lets pending COM RPC calls drain before the
        ; next request, preventing a silent native crash.
        if (InStr(err.Message, "0x8") || InStr(err.Message, "ComCall"))
            Sleep(50)
        return(_RpcError(id, -32000, err.Message, err.HasProp("What") ? err.What : ""))
    }
}

_DoShutdown(*)
{
    engineLog.Info("Shutting down")
    FileDelete(PORT_FILE)
    ; Use ExitProcess for a guaranteed immediate exit.
    ; ExitApp can be silently suppressed if OnError returns non-zero
    ; (e.g. after WSACleanup tears down socket state that ExitApp
    ;  then tries to reference during its cleanup).
    DllCall("kernel32\ExitProcess", "uint", 0)
}

; ══════════════════════════════════════════════════════════════════
;  Framework Detection
; ══════════════════════════════════════════════════════════════════

/**
 * Quick inlined framework detection (used by get_window_info).
 * Returns {framework, confidence} without the full clue list.
 */
_QuickDetectFramework(hwnd, class, pid, exe)
{
    exeLower := StrLower(exe)

    if (InStr(class, "HwndWrapper"))
        return {framework: "WPF", confidence: "high"}
    if (InStr(class, "ThunderRT6"))
        return {framework: "VB6", confidence: "high"}
    if (InStr(class, "SunAwt"))
        return {framework: "Java Swing", confidence: "high"}
    if (InStr(class, "Afx:"))
        return {framework: "MFC", confidence: "high"}
    if (InStr(class, "Qt5") || InStr(class, "Qt6"))
        return {framework: "Qt", confidence: "high"}
    if (InStr(class, "ApplicationFrame"))
        return {framework: "UWP", confidence: "medium"}
    if (InStr(class, "TForm") || InStr(class, "TButton") || InStr(class, "TEdit"))
        return {framework: "Delphi", confidence: "medium"}

    ; Chromium detection
    try {
        controls := WinGetControls(hwnd)
        for _, ctrl in controls {
            if (InStr(ctrl, "Chrome_RenderWidgetHostHWND")) {
                if (InStr(exeLower, "chrome") && !InStr(exeLower, "electron") && !InStr(exeLower, "code"))
                    return {framework: "Chrome", confidence: "high"}
                if (InStr(exeLower, "msedge"))
                    return {framework: "Edge", confidence: "high"}
                return {framework: "Electron", confidence: "medium"}
            }
            if (InStr(ctrl, "WindowsForms10"))
                return {framework: "WinForms", confidence: "high"}
        }
    }

    ; Fallback: UIA FrameworkId
    try {
        el := UIA.ElementFromHandle(hwnd)
        fwId := el.GetPropertyValue(30024)
        if (fwId && fwId != "")
            return {framework: String(fwId), confidence: "medium"}
    }

    return {framework: "Win32", confidence: "low"}
}

/**
 * uia_detect_framework — identify the UI framework of a window.
 *
 * Detects: WPF, WinForms, Chrome/Electron, Java Swing, Qt, UWP,
 * Delphi, VB6, MFC, and legacy Win32.
 */
_HandleDetectFramework(params)
{
    if (!params.Has("hwnd") || !params["hwnd"])
        throw Error("hwnd is required")

    hwnd := params["hwnd"]
    if (hwnd is String)
        hwnd := Integer(hwnd)

    class := ""
    title := ""
    exe := ""
    pid := 0
    try class := WinGetClass(hwnd)
    try title := WinGetTitle(hwnd)
    try pid := WinGetPID(hwnd)
    try exe := ProcessGetName(pid)
    exeLower := StrLower(exe)

    ; Gather clues
    clues := []
    framework := "unknown"
    confidence := "low"

    ; ── WPF ──
    if (InStr(class, "HwndWrapper")) {
        framework := "WPF"
        confidence := "high"
        clues.Push("Window class contains HwndWrapper (WPF hosting window)")
    }

    ; ── Windows Forms ──
    if (framework = "unknown") {
        try {
            controls := WinGetControls(hwnd)
            for _, ctrl in controls {
                if (InStr(ctrl, "WindowsForms10")) {
                    framework := "WinForms"
                    confidence := "high"
                    clues.Push("Found WindowsForms10 control class")
                    break
                }
            }
        }
    }

    ; ── Chrome / Electron (Chromium) ──
    if (framework = "unknown") {
        isChromium := false
        try {
            controls := WinGetControls(hwnd)
            for _, ctrl in controls {
                if (InStr(ctrl, "Chrome_RenderWidgetHostHWND")) {
                    isChromium := true
                    break
                }
            }
        }
        if (isChromium) {
            ; Distinguish Electron apps from plain Chrome
            if (InStr(exeLower, "chrome") && !InStr(exeLower, "electron") && !InStr(exeLower, "code")) {
                framework := "Chrome"
                confidence := "high"
                clues.Push("Chrome_RenderWidgetHostHWND control found, chrome.exe process")
            }
            else if (InStr(exeLower, "msedge")) {
                framework := "Edge"
                confidence := "high"
                clues.Push("Chrome_RenderWidgetHostHWND control found, msedge.exe process")
            }
            else {
                framework := "Electron"
                confidence := "medium"
                clues.Push("Chrome_RenderWidgetHostHWND control found in non-browser process: " exe)
            }
        }
    }

    ; ── Java Swing ──
    if (framework = "unknown" && InStr(class, "SunAwt")) {
        framework := "Java Swing"
        confidence := "high"
        clues.Push("Window class contains SunAwt (Java AWT/Swing)")
    }

    ; ── Qt ──
    if (framework = "unknown" && (InStr(class, "Qt5") || InStr(class, "Qt6"))) {
        framework := "Qt"
        confidence := "high"
        clues.Push("Window class contains Qt5/Qt6")
    }

    ; ── UWP / Modern Windows ──
    if (framework = "unknown" && InStr(class, "ApplicationFrame")) {
        framework := "UWP"
        confidence := "medium"
        clues.Push("Window class is ApplicationFrameWindow (UWP host)")
    }

    ; ── Delphi ──
    if (framework = "unknown" && (InStr(class, "TForm") || InStr(class, "TButton") || InStr(class, "TEdit"))) {
        framework := "Delphi"
        confidence := "medium"
        clues.Push("Window class prefix 'T' suggests Delphi/VCL")
    }

    ; ── VB6 ──
    if (framework = "unknown" && InStr(class, "ThunderRT6")) {
        framework := "VB6"
        confidence := "high"
        clues.Push("Window class ThunderRT6 (VB6 runtime)")
    }

    ; ── MFC ──
    if (framework = "unknown" && InStr(class, "Afx:")) {
        framework := "MFC"
        confidence := "high"
        clues.Push("Window class Afx: prefix (MFC framework)")
    }

    ; ── Fallback: use UIA FrameworkId ──
    if (framework = "unknown") {
        try {
            el := UIA.ElementFromHandle(hwnd)
            fwId := el.GetPropertyValue(30024)
            if (fwId && fwId != "") {
                fwIdStr := String(fwId)
                if (InStr(fwIdStr, "WPF")) {
                    framework := "WPF"
                    confidence := "medium"
                    clues.Push("UIA FrameworkId: " fwIdStr)
                } else {
                    framework := fwIdStr
                    confidence := "medium"
                    clues.Push("UIA FrameworkId: " fwIdStr)
                }
            }
        } catch Error as e {
            clues.Push("UIA element resolution failed — cannot determine FrameworkId")
        }
    }

    ; ── Additional clues ──
    if (exeLower) {
        if (InStr(exeLower, "code") || InStr(exeLower, "code-insiders"))
            clues.Push("Process is VS Code (Electron-based)")
        if (InStr(exeLower, "signal"))
            clues.Push("Process is Signal (Electron-based)")
        if (InStr(exeLower, "discord"))
            clues.Push("Process is Discord (Electron-based)")
        if (InStr(exeLower, "notepad"))
            clues.Push("Process is Notepad (Win32)")
        if (InStr(exeLower, "javaw") || InStr(exeLower, "java"))
            clues.Push("Process is java/javaw (likely Java Swing or JavaFX)")
    }

    ; Count controls for heuristics
    try {
        controls := WinGetControls(hwnd)
        if (controls.Length < 5)
            clues.Push("Window has very few Win32 controls — may be custom-rendered or UIA-only")
    }

    return {
        framework: framework,
        confidence: confidence,
        clues: clues,
        class: class,
        exe: exe
    }
}

; ══════════════════════════════════════════════════════════════════
;  Pixel Color
; ══════════════════════════════════════════════════════════════════

/**
 * uia_get_pixel_color — get the pixel color at screen coordinates.
 */
_HandleGetPixelColor(params)
{
    if (!params.Has("x") || !params.Has("y"))
        throw Error("x and y are required")

    x := params["x"]
    y := params["y"]
    if (x is String)
        x := Integer(x)
    if (y is String)
        y := Integer(y)

    CoordMode("Pixel", "Screen")
    try {
        color := PixelGetColor(x, y)
        r := (color >> 16) & 0xFF
        g := (color >> 8) & 0xFF
        b := color & 0xFF
        hex := Format("#{:06X}", color)
        return {
            x: x,
            y: y,
            color: color,
            hex: hex,
            rgb: [r, g, b]
        }
    } catch Error as err {
        throw Error("Failed to get pixel color: " err.Message)
    }
}

; ══════════════════════════════════════════════════════════════════
;  Accessibility Warnings
; ══════════════════════════════════════════════════════════════════

/**
 * uia_get_accessibility_warnings — report potential automation pitfalls.
 */
_HandleGetAccessibilityWarnings(params)
{
    if (!params.Has("hwnd") || !params["hwnd"])
        throw Error("hwnd is required")

    hwnd := params["hwnd"]
    if (hwnd is String)
        hwnd := Integer(hwnd)

    warnings := []
    class := ""
    title := ""
    pid := 0
    exe := ""
    try class := WinGetClass(hwnd)
    try title := WinGetTitle(hwnd)
    try pid := WinGetPID(hwnd)
    try exe := ProcessGetName(pid)

    ; ── Chromium content detection ──
    isChromium := false
    try {
        controls := WinGetControls(hwnd)
        for _, ctrl in controls {
            if (InStr(ctrl, "Chrome_RenderWidgetHostHWND")) {
                isChromium := true
                break
            }
        }
    }
    if (isChromium) {
        warnings.Push(Map(
            "severity", "info",
            "message", "Chromium-based rendering detected. Standard UIA may only see the top-level document. Use `uia_element_from_chromium` to access page content."
        ))
    }

    ; ── WPF ──
    if (InStr(class, "HwndWrapper")) {
        warnings.Push(Map(
            "severity", "info",
            "message", "WPF application detected. UIA is well-supported. Prefer AutomationId over Name for stable element identification."
        ))
    }

    ; ── WinForms ──
    try {
        controls := WinGetControls(hwnd)
        hasWinForms := false
        for _, ctrl in controls {
            if (InStr(ctrl, "WindowsForms10")) {
                hasWinForms := true
                break
            }
        }
        if (hasWinForms) {
            warnings.Push(Map(
                "severity", "warning",
                "message", "Windows Forms detected. UIA can be slow on large WinForms trees. Use narrow scopes and specific conditions. FindAll on Descendants scope may time out."
            ))
        }
    }

    ; ── VB6 / Legacy IAccessible ──
    if (InStr(class, "ThunderRT6")) {
        warnings.Push(Map(
            "severity", "warning",
            "message", "VB6 application detected. UIA bridge is LegacyIAccessible — properties may be limited. CacheRequest combined with FindAll may fail. Use Element scope and single-element lookups."
        ))
    }

    ; ── Java ──
    if (InStr(class, "SunAwt")) {
        warnings.Push(Map(
            "severity", "info",
            "message", "Java Swing application detected. UIA support varies by Java version. JavaFX apps have better UIA support than Swing."
        ))
    }

    ; ── Custom rendering hint ──
    try {
        controls := WinGetControls(hwnd)
        try {
            winText := WinGetText(hwnd)
            if (controls.Length < 5 && winText != "") {
                warnings.Push(Map(
                    "severity", "warning",
                    "message", "Window has very few Win32 controls (" controls.Length ") but has window text — suggests custom rendering. UIA may see limited elements. Consider screenshot-based approaches as fallback."
                ))
            }
        }
    }

    ; ── Elevated process ──
    try {
        targetPid := WinGetPID(hwnd)
        if (_IsElevated(targetPid) && !A_IsAdmin) {
            warnings.Push(Map(
                "severity", "error",
                "message", "Target process is elevated but engine is not running as Administrator. UIA access will be denied. Restart VS Code as Administrator."
            ))
        }
    }

    ; ── Browser ──
    if (_IsBrowserProcess(pid)) {
        warnings.Push(Map(
            "severity", "info",
            "message", "Browser process detected. Use `uia_element_from_chromium` for page content. Standard FindFirst on browser window only sees the toolbar/UI chrome."
        ))
    }

    ; ── UWP ──
    if (InStr(class, "ApplicationFrame")) {
        warnings.Push(Map(
            "severity", "info",
            "message", "UWP application detected. The visible window (ApplicationFrameWindow) is a host — use `get_element_tree` to find the actual content window underneath."
        ))
    }

    if (warnings.Length = 0) {
        warnings.Push(Map(
            "severity", "info",
            "message", "No specific accessibility concerns detected for this window."
        ))
    }

    return {
        hwnd: Format("0x{:X}", hwnd),
        class: class,
        exe: exe,
        warningCount: warnings.Length,
        warnings: warnings
    }
}

; ══════════════════════════════════════════════════════════════════
;  Main — TCP listen loop
; ══════════════════════════════════════════════════════════════════

global _lastActivity := A_TickCount
global srv := 0
global serverBound := false

; Write port file so the extension can find us
try FileDelete(PORT_FILE)
FileAppend("127.0.0.1:" ENGINE_PORT "`n" ProcessExist(), PORT_FILE)
engineLog.Info("Engine PID=" ProcessExist() " starting on port " ENGINE_PORT)

; Create listening socket
_OnAccept := _SocketOnAccept
_OnRecv   := _SocketOnRecv
_OnClose  := _SocketOnClose
try
{
    ; Initialize Winsock (required before any socket calls)
    wsadata := Buffer(400, 0)
    r := DllCall("Ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsadata)
    if (r != 0)
        throw Error("WSAStartup() failed: " r)

    srv := DllCall("Ws2_32\socket", "Int", 2, "Int", 1, "Int", 0, "Ptr") ; AF_INET, SOCK_STREAM, 0
    if (srv = -1)
        throw Error("socket() failed: " WSAGetLastError())

    ; Allow address reuse
    optVal := 1
    DllCall("Ws2_32\setsockopt", "Ptr", srv, "Int", 0xFFFF, "Int", 4, "Ptr*", optVal, "Int", 4)

    ; Bind
    addr := Buffer(16, 0)
    NumPut("UShort", 2, "UShort", _Htons(ENGINE_PORT), "UInt", 0x0100007F, addr) ; AF_INET, port, 127.0.0.1
    r := DllCall("Ws2_32\bind", "Ptr", srv, "Ptr", addr, "Int", 16)
    if (r != 0)
        throw Error("bind() failed: " WSAGetLastError() " — port " ENGINE_PORT " may be in use")

    ; Listen
    DllCall("Ws2_32\listen", "Ptr", srv, "Int", 1)
    serverBound := true
    engineLog.Info("TCP server bound to 127.0.0.1:" ENGINE_PORT)
}
catch Error as err
{
    OutputDebug "UIA_MCP_Engine: FATAL — " err.Message "`n"
    ; Write error to port file so the extension can detect the failure
    try FileDelete(PORT_FILE)
    FileAppend("ERROR: " err.Message, PORT_FILE)
    ExitApp()
}

; Register socket events
_AcceptProc := CallbackCreate(_OnAccept, "", 4)
DllCall("Ws2_32\WSAAsyncSelect", "Ptr", srv, "Ptr", A_ScriptHwnd, "UInt", 0x8000, "Int", 0x08) ; WM_SOCKET, FD_ACCEPT

; Idle timeout checker
SetTimer(_CheckIdle, 10000)

; ── Global inspect-at-cursor hotkey ───────────
; Register with :: syntax for full global access (Hotkey() callbacks
; have restricted scoping in AHK v2). Default: Ctrl+Shift+Alt+I.
; Override with --inspect-hotkey on the command line.

; We use Hotkey() to register a dynamically-configured key, but the
; handler must be a :: label-style function registered separately
; to avoid AHK v2 scoping restrictions.  The _InspectHotkeyHandler
; function delegates to _HandleInspectAtCursor — the same rich
; pipeline used by JSON-RPC.
_InspectHotkeyHandler(*)
{
    global _lastActivity
    _lastActivity := A_TickCount
    try
    {
        result := _HandleInspectAtCursor({})
    }
    catch Error as err
    {
        engineLog.Error("Hotkey error: " err.Message)
        ToolTip("UIA inspect failed: " err.Message)
        SetTimer(() => ToolTip(), -3000)
        return
    }
    ; Handle graceful error objects
    isMap := (result is Map)
    if (IsObject(result) && ((isMap && result.Has("error")) || (!isMap && result.HasProp("error"))) && result["error"]) {
        msg := isMap ? result["message"] : result.HasProp("message") ? result.message : ""
        ToolTip(msg || "Not accessible")
        SetTimer(() => ToolTip(), -3000)
        return
    }
    ; Show result tooltip with full element info
    try
    {
        elType   := isMap ? (result.Has("LocalizedType") ? result["LocalizedType"] : result.Has("Type") ? result["Type"] : "") : ""
        elName   := isMap ? (result.Has("Name") ? result["Name"] : "") : ""
        elClass  := isMap ? (result.Has("ClassName") ? result["ClassName"] : "") : ""
        elAction := isMap ? (result.Has("InferredAction") ? result["InferredAction"] : "") : ""
        winTitle := isMap ? (result.Has("WindowTitle") ? result["WindowTitle"] : "") : ""

        if (elType = "")
            elType := "?"
        if (elName = "")
            elName := "(no name)"
        if (elClass = "")
            elClass := "?"

        summary := ""
        if (winTitle)
            summary .= "Window: " winTitle "`n"
        summary .= Format("{} `"{}`"`nClass: {}", elType, elName, elClass)
        if (elAction)
            summary .= "`nAction: " elAction
        ToolTip(summary, , , 3)
        ToolTip(summary, , , 3)
        SetTimer(() => ToolTip(), -5000)

        try A_Clipboard := JSON.Stringify(result, 4)
        engineLog.Debug("Hotkey inspect: " elType " " elName)
    }
    catch Error as err2
    {
        engineLog.Error("Hotkey display error: " err2.Message)
    }
}

Hotkey(INSPECT_HOTKEY, _InspectHotkeyHandler, "On")
engineLog.Info("Inspect hotkey registered: " INSPECT_HOTKEY)

; Keep tray icon visible so the user knows the engine is running.

_JoinPatterns(patterns)
{
    if (!IsObject(patterns) || !patterns.Length)
        return("none")
    list := ""
    for i, p in patterns
    {
        if (i > 1)
            list .= ", "
        list .= p.name
        if (p.HasProp("isReadOnly"))
            list .= p.isReadOnly ? "(RO)" : "(RW)"
    }
    return(list)
}

; Announce ready
OutputDebug "UIA_MCP_Engine: listening on 127.0.0.1:" ENGINE_PORT "`n"

; ══════════════════════════════════════════════════════════════════
;  Socket Callbacks
; ══════════════════════════════════════════════════════════════════

global _clientSock := 0
global _recvBuf := ""

_SocketOnAccept(wp, lp, msg, hwnd)
{
    global srv, _clientSock, _recvBuf, _OnRecv, _OnClose, _lastActivity

    ; Only accept if not already serving a client (single-connection model)
    if (_clientSock) {
        ; Reject extra connections
        tmpSock := DllCall("Ws2_32\accept", "Ptr", srv, "Ptr", 0, "Ptr", 0, "Ptr")
        if (tmpSock != -1)
            DllCall("Ws2_32\closesocket", "Ptr", tmpSock)
        return
    }

    _clientSock := DllCall("Ws2_32\accept", "Ptr", srv, "Ptr", 0, "Ptr", 0, "Ptr")
    if (_clientSock = -1)
        return
    engineLog.Debug("Client connected")

    _recvBuf := ""
    _lastActivity := A_TickCount

    RecvProc := CallbackCreate(_OnRecv, "", 4)
    CloseProc := CallbackCreate(_OnClose, "", 4)
    DllCall("Ws2_32\WSAAsyncSelect", "Ptr", _clientSock, "Ptr", A_ScriptHwnd, "UInt", 0x8000, "Int", 0x01 | 0x20) ; FD_READ | FD_CLOSE
}

_SocketOnRecv(wp, lp, msg, hwnd)
{
    global _clientSock, _recvBuf, _lastActivity

    buf := Buffer(65536, 0)
    n := DllCall("Ws2_32\recv", "Ptr", _clientSock, "Ptr", buf, "Int", 65536, "Int", 0)
    if (n <= 0) {
        _CloseClient()
        return
    }

    _recvBuf .= StrGet(buf, n, "UTF-8")
    _lastActivity := A_TickCount

    ; Process all complete JSON messages (newline-delimited)
while (pos := InStr(_recvBuf, "`n"))
{
        line := SubStr(_recvBuf, 1, pos - 1)
        _recvBuf := SubStr(_recvBuf, pos + 1)
        line := Trim(line, " `t`r")
        if (line = "")
            continue
        response := _HandleRequest(line)
        _SendResponse(response)
    }
}

_SendResponse(str)
{
    global _clientSock
    buf := Buffer(StrPut(str, "UTF-8"), 0)
    StrPut(str, buf, "UTF-8")
    DllCall("Ws2_32\send", "Ptr", _clientSock, "Ptr", buf, "Int", buf.Size - 1, "Int", 0)
}

_SocketOnClose(wp, lp, msg, hwnd)
{
    _CloseClient()
}

_CloseClient()
{
    global _clientSock, _recvBuf
    if (_clientSock) {
        DllCall("Ws2_32\closesocket", "Ptr", _clientSock)
        _clientSock := 0
    }
    _recvBuf := ""
}

_CheckIdle()
{
    global _lastActivity, _clientSock
    if (!_clientSock && (A_TickCount - _lastActivity > IDLE_TIMEOUT_MS)) {
        OutputDebug "UIA_MCP_Engine: idle timeout, shutting down`n"
        _DoShutdown()
    }
}

; ══════════════════════════════════════════════════════════════════
;  Network Helpers
; ══════════════════════════════════════════════════════════════════

_Htons(val)
{
    return DllCall("ws2_32\htons", "ushort", val, "ushort")
}

WSAGetLastError()
{
    return DllCall("Ws2_32\WSAGetLastError")
}

; WM_SOCKET handler — AHK needs to receive the message via OnMessage
; We use a static variable to avoid registering multiple times
OnMessage(0x8000, _WmSocketHandler)

_WmSocketHandler(wp, lp, msg, hwnd)
{
    global _clientSock
    sock := wp
    event := lp & 0xFFFF
    err := (lp >> 16) & 0xFFFF

    if event = 0x08 ; FD_ACCEPT
        _SocketOnAccept(wp, lp, msg, hwnd)
    else if event = 0x01 ; FD_READ
        _SocketOnRecv(wp, lp, msg, hwnd)
    else if event = 0x20 ; FD_CLOSE
        _SocketOnClose(wp, lp, msg, hwnd)
}
