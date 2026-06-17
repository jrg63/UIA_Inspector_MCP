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
#Include <UIA_Inspector\cjson>

; ── cJSON configuration ───────────────────────
; Ensure booleans serialize as true/false, not 0/1
JSON.BoolsAsInts := 0

; ── Configuration ─────────────────────────────
global ENGINE_PORT      := 9876
global IDLE_TIMEOUT_MS  := 300000   ; 5 minutes
global LOG_LEVEL        := 1        ; 0=none 1=error 2=info 3=debug
global INSPECT_HOTKEY   := "^+I"    ; Ctrl+Shift+I
global LOG_FILE         := A_Temp "\UIA_MCP_Engine.log"
global PORT_FILE         := A_Temp "\UIA_MCP_Engine.port"

; Parse command-line args
for i, arg in A_Args {
    if arg = "--port" && A_Args.Has(i + 1)
        ENGINE_PORT := Integer(A_Args[i + 1])
    if arg = "--idle-timeout" && A_Args.Has(i + 1)
        IDLE_TIMEOUT_MS := Integer(A_Args[i + 1]) * 1000
    if arg = "--inspect-hotkey" && A_Args.Has(i + 1)
        INSPECT_HOTKEY := A_Args[i + 1]
    if arg = "--log-file" && A_Args.Has(i + 1)
        LOG_FILE := A_Args[i + 1]
    if arg = "--log-level" && A_Args.Has(i + 1) {
        switch A_Args[i + 1], 0 {
            case "none":  LOG_LEVEL := 0
            case "error": LOG_LEVEL := 1
            case "info":  LOG_LEVEL := 2
            case "debug": LOG_LEVEL := 3
        }
    }
}

; ══════════════════════════════════════════════════════════════════
;  Logging — writes to disk file AND stderr
; ══════════════════════════════════════════════════════════════════

_Log(level, msg) {
    if level > LOG_LEVEL
        return
    static labels := ["NONE", "ERROR", "INFO ", "DEBUG"]
    label := labels[level + 1]
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    line := Format("[{}] {} {}`n", ts, label, msg)
    try FileAppend(line, LOG_FILE)   ; persistent log on disk
    try FileAppend(line, "*")        ; also stderr for daemon capture
}

; ══════════════════════════════════════════════════════════════════
;  JSON-RPC Helpers
; ══════════════════════════════════════════════════════════════════

/**
 * Build a JSON-RPC 2.0 success response.
 * @param id - the request id (mirrored)
 * @param result - the result value (any AHK value / object)
 */
_RpcResult(id, result) {
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
_RpcError(id, code, message, data := "") {
    err := {code: code, message: message}
    if data
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
_MakeCacheRequest() {
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
    return cr
}

/**
 * Convert a UIA element to a Map of all its known properties.
 * Mirrors the property list used in UIA_Inspector's PopulateProperties.
 */
_ElementToMap(el) {
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
    try {
        raw := el.GetPropertyValue(30001)
        if IsObject(raw)
            m["BoundingRect"] := {left: raw.l, top: raw.t, right: raw.r, bottom: raw.b}
        else
            m["BoundingRect"] := ""
    } catch
        m["BoundingRect"] := ""

    ; Resolve element HWND via fallback chain
    try m["HWND"] := _ResolveElementHwnd(el)
    catch
        m["HWND"] := "0"

    return m
}

_PropStr(el, propId) {
    try {
        return String(el.GetPropertyValue(propId))
    } catch {
        return ""
    }
}

_PropBool(el, propId) {
    try {
        return el.GetPropertyValue(propId) ? true : false
    } catch {
        return false
    }
}

_PropInt(el, propId) {
    try {
        return Integer(el.GetPropertyValue(propId))
    } catch {
        return 0
    }
}

_PropHwnd(el, propId) {
    try {
        raw := el.GetPropertyValue(propId)
        return raw ? Format("0x{:X}", raw) : "0"
    } catch {
        return "0"
    }
}

/**
 * Resolve a concrete HWND for `el` — NativeWindowHandle → WinId + DeepChild search.
 */
_ResolveElementHwnd(el) {
    try {
        nwh := el.GetPropertyValue(30020)
        if nwh
            return Format("0x{:X}", nwh)
    }
    try {
        winId := WinExist("ahk_id " el.ProcessId)
        if winId {
            deep := _FindDeepestHWND(winId, el)
            if deep
                return Format("0x{:X}", deep)
            return Format("0x{:X}", winId)
        }
    }
    return "0"
}

_FindDeepestHWND(hwnd, el) {
    try {
        rect := el.GetPropertyValue(30001)
        if !IsObject(rect)
            return 0
        targetLeft := rect.l, targetTop := rect.t, targetRight := rect.r, targetBottom := rect.b
    } catch {
        return 0
    }
    bestMatch := 0
    bestArea := 0
    EnumChildWindows(hwnd, _EnumChildFunc.Bind(&bestMatch, &bestArea, targetLeft, targetTop, targetRight, targetBottom))
    return bestMatch
}

_EnumChildFunc(&bestMatch, &bestArea, tL, tT, tR, tB, hwnd) {
    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
        left := Max(x, tL), top := Max(y, tT)
        right := Min(x + w, tR), bottom := Min(y + h, tB)
        if left < right && top < bottom {
            area := (right - left) * (bottom - top)
            if area > bestArea {
                bestArea := area
                bestMatch := hwnd
            }
        }
    }
    return true
}

EnumChildWindows(hwnd, fn) {
    DllCall("EnumChildWindows", "Ptr", hwnd, "Ptr", CallbackCreate(fn, "Fast"), "Ptr", 0)
}

/**
 * Build a condition Map from a JSON-like condition object.
 * Accepts: {Type:"Button", Name:"OK", AutomationId:"foo", ClassName:"bar"}
 *          or numeric property IDs: {30003:"Button"}
 * Returns a Map suitable for FindFirst/FindAll.
 */
_BuildCondition(condObj) {
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
    for key, val in condObj {
        if val = ""
            continue
        propId := 0
        if nameToId.Has(key)
            propId := nameToId[key]
        else {
            try propId := Integer(key)
            catch
                propId := 0
        }
        if propId {
            ; For Type property, convert name to integer ID (e.g. "Pane" → 50033)
            if propId = 30003 && val is String {
                try {
                    typeId := UIA_Type.%val%
                    condMap[propId] := typeId
                } catch {
                    condMap[propId] := String(val)
                }
            } else {
                condMap[propId] := String(val)
            }
        }
    }
    ; Convert Map to Object — UIA.CreateCondition requires Object, not Map
    if !condMap.Count
        return ""
    condObj2 := {}
    for k, v in condMap
        condObj2.%k% := v
    return condObj2
}

/**
 * Convert an element to a summary map (Type + Name + AutomationId + ClassName + BoundingRect).
 * Used for find_all_elements and children lists to keep responses compact.
 */
_ElementSummary(el) {
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
_ResolveScope(scopeName) {
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
_ResolveMatchMode(mode) {
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
_GetAncestorChain(el) {
    global UIA
    chain := []
    try {
        walker := UIA.TreeWalkerTrue
        cur := el
        while cur {
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
    return chain
}

/**
 * Build a compact text tree from a window element.
 * Marks the selected element with `<<< SELECTED` if matched.
 */
_BuildTreeSnippet(windowEl, selectedEl := "", maxDepth := 4) {
    out := ""
    _WalkTree(windowEl, selectedEl, 0, maxDepth, &out)
    return out
}

_WalkTree(el, selectedEl, depth, maxDepth, &out) {
    if depth > maxDepth
        return
    prefix := ""
    loop depth
        prefix .= "  "
    typ := _PropStr(el, 30003)
    name := _PropStr(el, 30005)
    aid := _PropStr(el, 30011)
    cls := _PropStr(el, 30012)
    marker := ""
    try {
        if selectedEl && el.Compare(selectedEl)
            marker := " <<< SELECTED"
    }
    line := prefix "[" typ "]"
    if name
        line .= " Name='" name "'"
    if aid
        line .= " AutomationId='" aid "'"
    if cls
        line .= " ClassName='" cls "'"
    line .= marker "`n"
    out .= line

    ; Walk children
    try {
        child := UIA.TreeWalkerTrue.GetFirstChildElement(el)
        while child {
            _WalkTree(child, selectedEl, depth + 1, maxDepth, &out)
            child := UIA.TreeWalkerTrue.GetNextSiblingElement(child)
        }
    }
}

/**
 * Return the available patterns for an element as an array of objects,
 * each with optional sub-properties (e.g. ToggleState, Value).
 */
_GetPatterns(el) {
    global UIA
    patterns := []
    ; Invoke
    try {
        if el.GetPropertyValue(30031)
            patterns.Push({name: "Invoke"})
    }
    ; Toggle
    try {
        if el.GetPropertyValue(30041) {
            p := {name: "Toggle"}
            try p.state := el.GetPattern("Toggle").ToggleState
            patterns.Push(p)
        }
    }
    ; ExpandCollapse
    try {
        if el.GetPropertyValue(30028) {
            p := {name: "ExpandCollapse"}
            try p.state := Map(0, "Collapsed", 1, "Expanded", 2, "PartiallyExpanded")[el.GetPattern("ExpandCollapse").ExpandCollapseState]
            patterns.Push(p)
        }
    }
    ; Value
    try {
        if el.GetPropertyValue(30043) {
            p := {name: "Value"}
            try p.value := el.GetPattern("Value").Value
            try p.isReadOnly := el.GetPattern("Value").IsReadOnly
            patterns.Push(p)
        }
    }
    ; SelectionItem
    try {
        if el.GetPropertyValue(30036) {
            p := {name: "SelectionItem"}
            try p.isSelected := el.GetPattern("SelectionItem").IsSelected
            patterns.Push(p)
        }
    }
    ; Selection
    try {
        if el.GetPropertyValue(30037) {
            p := {name: "Selection"}
            try p.canSelectMultiple := el.GetPattern("Selection").CanSelectMultiple
            patterns.Push(p)
        }
    }
    ; Scroll
    try {
        if el.GetPropertyValue(30034) {
            p := {name: "Scroll"}
            try p.horizontallyScrollable := el.GetPattern("Scroll").HorizontallyScrollable
            try p.verticallyScrollable := el.GetPattern("Scroll").VerticallyScrollable
            patterns.Push(p)
        }
    }
    ; Window
    try {
        if el.GetPropertyValue(30090) {
            p := {name: "WindowPattern"}
            try p.canMinimize := el.GetPattern("WindowPattern").CanMinimize
            try p.canMaximize := el.GetPattern("WindowPattern").CanMaximize
            patterns.Push(p)
        }
    }
    ; Transform
    try {
        if el.GetPropertyValue(30040) {
            p := {name: "Transform"}
            try p.canMove := el.GetPattern("Transform").CanMove
            try p.canResize := el.GetPattern("Transform").CanResize
            patterns.Push(p)
        }
    }
    ; LegacyIAccessible
    try {
        if el.GetPropertyValue(30033) {
            p := {name: "LegacyIAccessible"}
            try p.name := el.GetPattern("LegacyIAccessible").Name
            try p.value := el.GetPattern("LegacyIAccessible").Value
            patterns.Push(p)
        }
    }
    return patterns
}

/**
 * Determine a sensible default action for an element by probing pattern availability.
 */
_DetermineAction(el) {
    try {
        if el.GetPropertyValue(30031)
            return "Invoke()"
    }
    try {
        if el.GetPropertyValue(30041)
            return "Toggle()"
    }
    try {
        if el.GetPropertyValue(30028) {
            state := el.GetPattern("ExpandCollapse").ExpandCollapseState
            return state = 0 ? "Expand()" : "Collapse()"
        }
    }
    try {
        if el.GetPropertyValue(30043)
            return 'SetValue("")'
    }
    try {
        if el.GetPropertyValue(30036)
            return "Select()"
    }
    return "Click()"
}

/**
 * Build a condition string for `el` — Type + AutomationId > Name > ClassName.
 */
_BuildConditionString(el) {
    parts := []
    try {
        typeId := el.Type
        typeName := UIA_Type.HasValue(typeId)
        if typeName
            parts.Push('Type: "' typeName '"')
    }
    try {
        aid := el.AutomationId
        if aid != "" {
            parts.Push('AutomationId: "' _EscapeStr(String(aid)) '"')
            return "{" _Join(parts) "}"
        }
    }
    try {
        name := el.Name
        if name {
            parts.Push('Name: "' _EscapeStr(name) '"')
            return "{" _Join(parts) "}"
        }
    }
    try {
        cn := el.ClassName
        if cn
            parts.Push('ClassName: "' _EscapeStr(cn) '"')
    }
    return parts.Length ? "{" _Join(parts) "}" : "{}"
}

_EscapeStr(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    return s
}

_Join(arr) {
    s := ""
    for i, v in arr
        s .= (i > 1 ? ", " : "") v
    return s
}

; ══════════════════════════════════════════════════════════════════
;  Process Detection Helpers
; ══════════════════════════════════════════════════════════════════

_IsBrowserProcess(pid) {
    try {
        exe := ProcessGetName(pid)
        exe := StrLower(exe)
        return InStr(exe, "chrome") || InStr(exe, "msedge") || InStr(exe, "opera") || InStr(exe, "brave") || InStr(exe, "firefox")
    }
    return false
}

_IsElevated(pid) {
    try {
        hProc := DllCall("OpenProcess", "UInt", 0x400, "Int", 0, "UInt", pid, "Ptr")
        if !hProc
            return false
        token := 0
        DllCall("OpenProcessToken", "Ptr", hProc, "UInt", 8, "Ptr*", &token)
        DllCall("CloseHandle", "Ptr", hProc)
        if !token
            return false
        elevation := 0
        DllCall("GetTokenInformation", "Ptr", token, "Int", 20, "UInt*", &elevation, "UInt", 4, "UInt*", &retLen)
        DllCall("CloseHandle", "Ptr", token)
        return elevation != 0
    }
    return false
}

_CheckExeBitness(path) {
    try {
        if !FileExist(path)
            return "?"
        bin := FileOpen(path, "r")
        bin.Pos := 0x3C
        peOffset := bin.ReadUInt()
        bin.Pos := peOffset + 4
        machine := bin.ReadUShort()
        bin.Close()
        return machine = 0x8664 ? "x64" : "x86"
    }
    return "?"
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
_ResolveLocator(locator) {
    root := 0
    ; Root by HWND
    if locator.Has("hwnd") && locator["hwnd"] {
        cr := _MakeCacheRequest()
        root := UIA.ElementFromHandle(locator["hwnd"], cr)
    }
    ; Root by focused element
    else {
        root := UIA.GetFocusedElement()
    }
    if !root
        throw Error("Could not resolve root element from locator")

    ; If no condition, return root
    if !locator.Has("condition") || !locator["condition"] || locator["condition"] = ""
        return root

    condMap := _BuildCondition(locator["condition"])
    if condMap = ""
        return root

    scope := _ResolveScope(locator.Has("scope") ? locator["scope"] : "Descendants")
    matchMode := _ResolveMatchMode(locator.Has("matchMode") ? locator["matchMode"] : "Exact")
    index := locator.Has("index") ? locator["index"] : 1

    ; Use FindAll + index to get the Nth match
    try {
        matches := root.FindAll(condMap, matchMode, scope)
        if IsObject(matches) && matches.Length >= index
            return matches[index]
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
_HandleInspectAtCursor(params) {
    global UIA
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY, &winUnderMouse)
    if !winUnderMouse
        throw Error("No window under cursor")
    _Log(3, "InspectAtCursor: mouse at (" mX "," mY ") hwnd=0x" Format("{:X}", winUnderMouse))

    ; Check elevation
    targetPid := WinGetPID("ahk_id " winUnderMouse)
    _Log(3, "InspectAtCursor: targetPid=" targetPid)
    elevated := _IsElevated(targetPid)
    if elevated && !A_IsAdmin {
        return {
            elevated: true,
            targetPid: targetPid,
            targetName: ProcessGetName(targetPid),
            message: "Target is elevated. Restart engine as Administrator."
        }
    }

    ; Activate Chromium accessibility if needed
    try {
        if _IsBrowserProcess(targetPid)
            UIA.ActivateChromiumAccessibility(winUnderMouse)
    }

    _Log(3, "InspectAtCursor: building cache request...")
    cr := _MakeCacheRequest()
    _Log(3, "InspectAtCursor: getting window element from handle...")
    windowEl := UIA.ElementFromHandle(winUnderMouse, cr)

    _Log(3, "InspectAtCursor: calling ElementFromPoint...")
    el := 0
    try {
        el := UIA.ElementFromPoint(mX, mY)
    } catch as err {
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
    if !el {
        try {
            automation := UIA.IUIAutomation
            pt := Buffer(8, 0)
            NumPut("Int", mX, "Int", mY, pt)
            elPtr := 0
            ComCall(7, automation, "int", "ptr", pt, "ptr*", &elPtr)
            if elPtr
                el := UIA.IUIAutomationElement(elPtr)
        }
    }

    if !el
        return {
            error: true,
            message: "UIA.ElementFromPoint returned nothing at (" mX "," mY ")",
            x: mX, y: mY,
            hwnd: Format("0x{:X}", winUnderMouse),
            targetName: ProcessGetName(targetPid)
        }

    _Log(3, "InspectAtCursor: element found, building full result...")
    result := _BuildFullElementResult(el, windowEl, winUnderMouse, targetPid)
    _Log(3, "InspectAtCursor: done, Type=" (result.HasProp("Type") ? result["Type"] : "?"))
    return result
}

/**
 * get_focused_element
 * Returns the currently focused UI element.
 */
_HandleGetFocusedElement(params) {
    try {
        el := UIA.GetFocusedElement()
        if !el
            throw Error("No focused element found")

        ; Get window info from the focused element
        hwnd := 0
        try hwnd := el.CurrentNativeWindowHandle

        windowEl := 0
        try windowEl := UIA.ElementFromHandle(hwnd, _MakeCacheRequest())

        targetPid := 0
        try targetPid := WinGetPID("ahk_id " hwnd)

        return _BuildFullElementResult(el, windowEl, hwnd, targetPid)
    } catch as err {
        throw Error("Failed to get focused element: " err.Message)
    }
}

/**
 * find_element — resolve a locator to a single element and return full info.
 */
_HandleFindElement(params) {
    el := _ResolveLocator(params)
    hwnd := 0
    try hwnd := el.CurrentNativeWindowHandle
    if !hwnd
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
_HandleFindAllElements(params) {
    root := 0
    if params.Has("hwnd") && params["hwnd"] {
        cr := _MakeCacheRequest()
        root := UIA.ElementFromHandle(params["hwnd"], cr)
    } else {
        root := UIA.GetFocusedElement()
    }
    if !root
        throw Error("Could not resolve root")

    condMap := _BuildCondition(params.Has("condition") ? params["condition"] : {})
    if condMap = ""
        throw Error("condition is required for find_all")

    scope := _ResolveScope(params.Has("scope") ? params["scope"] : "Descendants")
    matchMode := _ResolveMatchMode(params.Has("matchMode") ? params["matchMode"] : "Exact")

    matches := root.FindAll(condMap, matchMode, scope)
    results := []
    if IsObject(matches) {
        for i, m in matches {
            results.Push(_ElementSummary(m))
        }
    }
    return {
        count: results.Length,
        elements: results
    }
}

/**
 * get_element_tree — walk the UIA tree from a window or element.
 */
_HandleGetElementTree(params) {
    hwnd := params.Has("hwnd") ? params["hwnd"] : 0
    maxDepth := params.Has("maxDepth") ? params["maxDepth"] : 4
    filter := params.Has("filter") ? params["filter"] : ""

    if !hwnd
        throw Error("hwnd is required for get_element_tree")

    ; Check elevation
    targetPid := WinGetPID("ahk_id " hwnd)
    if _IsElevated(targetPid) && !A_IsAdmin {
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
_HandleGetAncestorChain(params) {
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
_HandleGetElementProperties(params) {
    el := _ResolveLocator(params)
    props := _ElementToMap(el)
    ; Convert Map to object for JSON serialization
    result := {}
    for k, v in props
        result.%k% := v
    return result
}

/**
 * get_element_patterns — return available patterns.
 */
_HandleGetElementPatterns(params) {
    el := _ResolveLocator(params)
    return _GetPatterns(el)
}

/**
 * list_windows — enumerate all top-level windows.
 */
_HandleListWindows(params) {
    filter := params.Has("filter") ? params["filter"] : ""
    windows := []
    filterLower := StrLower(filter)
    
    DetectHiddenWindows(true)
    hwnds := WinGetList()
    for i, hwnd in hwnds {
        try {
            title := WinGetTitle(hwnd)
            class := WinGetClass(hwnd)
            pid := WinGetPID(hwnd)
            exe := ProcessGetName(pid)
            WinGetPos(&x, &y, &w, &h, hwnd)

            if filterLower && !InStr(StrLower(title), filterLower) && !InStr(StrLower(exe), filterLower)
                continue

            elevated := _IsElevated(pid)

            windows.Push({
                hwnd: Format("0x{:X}", hwnd),
                title: title,
                class: class,
                pid: pid,
                exe: exe,
                rect: {left: x, top: y, right: x + w, bottom: y + h},
                elevated: elevated,
                visible: WinGetMinMax(hwnd) != -1
            })
        }
    }
    return {
        count: windows.Length,
        windows: windows
    }
}

/**
 * get_window_info — detailed info for a specific window.
 */
_HandleGetWindowInfo(params) {
    if !params.Has("hwnd") || !params["hwnd"]
        throw Error("hwnd is required")

    hwnd := params["hwnd"]
    if hwnd is String
        hwnd := Integer(hwnd)

    try {
        title := WinGetTitle(hwnd)
        class := WinGetClass(hwnd)
        pid := WinGetPID(hwnd)
        exe := ProcessGetName(pid)
        path := ProcessGetPath(pid)
        WinGetPos(&x, &y, &w, &h, hwnd)
        minMax := WinGetMinMax(hwnd)
        bitness := _CheckExeBitness(path)
        elevated := _IsElevated(pid)

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
            isBrowser: _IsBrowserProcess(pid)
        }
    } catch as err {
        throw Error("Failed to get window info: " err.Message)
    }
}

/**
 * check_match_count — count how many elements match a condition.
 */
_HandleCheckMatchCount(params) {
    root := 0
    if params.Has("hwnd") && params["hwnd"] {
        cr := _MakeCacheRequest()
        root := UIA.ElementFromHandle(params["hwnd"], cr)
    } else {
        root := UIA.GetFocusedElement()
    }
    if !root
        throw Error("Could not resolve root")

    condMap := _BuildCondition(params.Has("condition") ? params["condition"] : {})
    if condMap = ""
        throw Error("condition is required")

    scope := _ResolveScope(params.Has("scope") ? params["scope"] : "Descendants")
    matchMode := _ResolveMatchMode(params.Has("matchMode") ? params["matchMode"] : "Exact")

    try {
        matches := root.FindAll(condMap, matchMode, scope)
        if IsObject(matches)
            return {count: matches.Length}
        return {count: 0}
    } catch {
        return {count: 0}
    }
}

/**
 * get_child_elements — return direct children of a resolved element.
 */
_HandleGetChildElements(params) {
    el := _ResolveLocator(params)
    children := []
    try {
        child := UIA.TreeWalkerTrue.GetFirstChildElement(el)
        while child {
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
_HandleGetBoundingRect(params) {
    el := _ResolveLocator(params)
    try {
        raw := el.GetPropertyValue(30001)
        if IsObject(raw)
            return {left: raw.l, top: raw.t, right: raw.r, bottom: raw.b}
        return {left: 0, top: 0, right: 0, bottom: 0}
    } catch {
        return {left: 0, top: 0, right: 0, bottom: 0}
    }
}

/**
 * wait_for_element — poll until element matching condition exists or timeout.
 */
_HandleWaitForElement(params) {
    timeout := params.Has("timeout") ? params["timeout"] : 5000
    hwnd := params.Has("hwnd") ? params["hwnd"] : 0
    condObj := params.Has("condition") ? params["condition"] : {}

    condMap := _BuildCondition(condObj)
    if condMap = ""
        throw Error("condition is required")

    scope := _ResolveScope(params.Has("scope") ? params["scope"] : "Descendants")
    matchMode := _ResolveMatchMode(params.Has("matchMode") ? params["matchMode"] : "Exact")

    ; Get root element
    root := 0
    if hwnd {
        cr := _MakeCacheRequest()
        root := UIA.ElementFromHandle(hwnd, cr)
    } else {
        root := UIA.GetFocusedElement()
    }
    if !root
        throw Error("Could not resolve root")

    ; Poll
    start := A_TickCount
    loop {
        try {
            matches := root.FindAll(condMap, matchMode, scope)
            if IsObject(matches) && matches.Length > 0 {
                return {
                    found: true,
                    elapsed: A_TickCount - start,
                    element: _BuildFullElementResult(matches[1], root, hwnd, 0)
                }
            }
        }
        if A_TickCount - start >= timeout
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
_HandleGetElementAtPoint(params) {
    if !params.Has("x") || !params.Has("y")
        throw Error("x and y are required")

    x := params["x"], y := params["y"]

    ; Get window under point
    hwnd := 0
    try {
        pt := (x & 0xFFFFFFFF) | (y << 32)
        hwnd := DllCall("WindowFromPoint", "Int64", pt, "Ptr")
    }
    if !hwnd
        throw Error("No window at (" x ", " y ")")

    targetPid := WinGetPID("ahk_id " hwnd)

    cr := _MakeCacheRequest()
    windowEl := UIA.ElementFromHandle(hwnd, cr)
    el := UIA.ElementFromPoint(x, y)

    return _BuildFullElementResult(el, windowEl, hwnd, targetPid)
}

; ══════════════════════════════════════════════════════════════════
;  Full Element Result Builder (used by multiple handlers)
; ══════════════════════════════════════════════════════════════════

_BuildFullElementResult(el, windowEl, hwnd, targetPid) {
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
    if hwnd {
        try {
            result["WindowTitle"] := WinGetTitle(hwnd)
            result["WindowClass"] := WinGetClass(hwnd)
            result["WindowExe"] := ProcessGetName(targetPid ? targetPid : WinGetPID("ahk_id " hwnd))
        }
    }

    return result
}

; ══════════════════════════════════════════════════════════════════
;  TCP Server
; ══════════════════════════════════════════════════════════════════

_HandleRequest(jsonStr) {
    ; Parse JSON
    request := ""
    try request := JSON.Parse(jsonStr)
    catch {
        _Log(1, "JSON parse error: " SubStr(jsonStr, 1, 200))
        return _RpcError("", -32700, "Parse error")
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
        "get_bounding_rect",    _HandleGetBoundingRect,
        "wait_for_element",     _HandleWaitForElement,
        "get_element_at_point", _HandleGetElementAtPoint,
        "get_full_element",     _HandleGetElementProperties,  ; alias
        "shutdown",             (*) => (SetTimer(_DoShutdown, -1), "shutting down")
    )

    if !handlers.Has(method) {
        _Log(1, "Method not found: " method)
        return _RpcError(id, -32601, "Method not found: " method)
    }

    try {
        _Log(3, "Dispatching: " method)
        result := handlers[method](params)
        _Log(3, "Completed: " method)
        return _RpcResult(id, result)
    } catch as err {
        _Log(1, "Handler error [" method "]: " err.Message . (err.HasProp("What") ? " (" err.What ")" : ""))
        return _RpcError(id, -32000, err.Message, err.HasProp("What") ? err.What : "")
    }
}

_DoShutdown(*) {
    _Log(2, "Shutting down")
    FileDelete(PORT_FILE)
    try DllCall("Ws2_32\WSACleanup")
    ExitApp()
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
_Log(2, "Engine PID=" ProcessExist() " starting on port " ENGINE_PORT)

; Create listening socket
_OnAccept := _SocketOnAccept
_OnRecv   := _SocketOnRecv
_OnClose  := _SocketOnClose
try {
    ; Initialize Winsock (required before any socket calls)
    wsadata := Buffer(400, 0)
    r := DllCall("Ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsadata)
    if r != 0
        throw Error("WSAStartup() failed: " r)

    srv := DllCall("Ws2_32\socket", "Int", 2, "Int", 1, "Int", 0, "Ptr") ; AF_INET, SOCK_STREAM, 0
    if srv = -1
        throw Error("socket() failed: " WSAGetLastError())

    ; Allow address reuse
    optVal := 1
    DllCall("Ws2_32\setsockopt", "Ptr", srv, "Int", 0xFFFF, "Int", 4, "Ptr*", optVal, "Int", 4)

    ; Bind
    addr := Buffer(16, 0)
    NumPut("UShort", 2, "UShort", _Htons(ENGINE_PORT), "UInt", 0x0100007F, addr) ; AF_INET, port, 127.0.0.1
    r := DllCall("Ws2_32\bind", "Ptr", srv, "Ptr", addr, "Int", 16)
    if r != 0
        throw Error("bind() failed: " WSAGetLastError() " — port " ENGINE_PORT " may be in use")

    ; Listen
    DllCall("Ws2_32\listen", "Ptr", srv, "Int", 1)
    serverBound := true
    _Log(2, "TCP server bound to 127.0.0.1:" ENGINE_PORT)
} catch as err {
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
_InspectHotkeyHandler(*) {
    global _lastActivity
    _lastActivity := A_TickCount
    try {
        result := _HandleInspectAtCursor({})
    } catch as err {
        _Log(1, "Hotkey error: " err.Message)
        ToolTip("UIA inspect failed: " err.Message)
        SetTimer(() => ToolTip(), -3000)
        return
    }
    ; Handle graceful error objects
    isMap := (result is Map)
    if IsObject(result) && ((isMap && result.Has("error")) || (!isMap && result.HasProp("error"))) && result["error"] {
        msg := isMap ? result["message"] : result.HasProp("message") ? result.message : ""
        ToolTip(msg || "Not accessible")
        SetTimer(() => ToolTip(), -3000)
        return
    }
    ; Show result tooltip with full element info
    try {
        elType   := isMap ? (result.Has("LocalizedType") ? result["LocalizedType"] : result.Has("Type") ? result["Type"] : "") : ""
        elName   := isMap ? (result.Has("Name") ? result["Name"] : "") : ""
        elClass  := isMap ? (result.Has("ClassName") ? result["ClassName"] : "") : ""
        elAction := isMap ? (result.Has("InferredAction") ? result["InferredAction"] : "") : ""
        winTitle := isMap ? (result.Has("WindowTitle") ? result["WindowTitle"] : "") : ""

        if elType = ""
            elType := "?"
        if elName = ""
            elName := "(no name)"
        if elClass = ""
            elClass := "?"

        summary := ""
        if winTitle
            summary .= "Window: " winTitle "`n"
        summary .= Format("{} `"{}`"`nClass: {}", elType, elName, elClass)
        if elAction
            summary .= "`nAction: " elAction
        ToolTip(summary, , , 3)
        ToolTip(summary, , , 3)
        SetTimer(() => ToolTip(), -5000)

        try A_Clipboard := JSON.Stringify(result, 4)
        _Log(3, "Hotkey inspect: " elType " " elName)
    } catch as err2 {
        _Log(1, "Hotkey display error: " err2.Message)
    }
}

Hotkey(INSPECT_HOTKEY, _InspectHotkeyHandler, "On")
_Log(2, "Inspect hotkey registered: " INSPECT_HOTKEY)

; Keep tray icon visible so the user knows the engine is running.

_JoinPatterns(patterns) {
    if !IsObject(patterns) || !patterns.Length
        return "none"
    list := ""
    for i, p in patterns {
        if i > 1
            list .= ", "
        list .= p.name
        if p.HasProp("isReadOnly")
            list .= p.isReadOnly ? "(RO)" : "(RW)"
    }
    return list
}

; Announce ready
OutputDebug "UIA_MCP_Engine: listening on 127.0.0.1:" ENGINE_PORT "`n"

; ══════════════════════════════════════════════════════════════════
;  Socket Callbacks
; ══════════════════════════════════════════════════════════════════

global _clientSock := 0
global _recvBuf := ""

_SocketOnAccept(wp, lp, msg, hwnd) {
    global srv, _clientSock, _recvBuf, _OnRecv, _OnClose, _lastActivity

    ; Only accept if not already serving a client (single-connection model)
    if _clientSock {
        ; Reject extra connections
        tmpSock := DllCall("Ws2_32\accept", "Ptr", srv, "Ptr", 0, "Ptr", 0, "Ptr")
        if tmpSock != -1
            DllCall("Ws2_32\closesocket", "Ptr", tmpSock)
        return
    }

    _clientSock := DllCall("Ws2_32\accept", "Ptr", srv, "Ptr", 0, "Ptr", 0, "Ptr")
    if _clientSock = -1
        return
    _Log(3, "Client connected")

    _recvBuf := ""
    _lastActivity := A_TickCount

    RecvProc := CallbackCreate(_OnRecv, "", 4)
    CloseProc := CallbackCreate(_OnClose, "", 4)
    DllCall("Ws2_32\WSAAsyncSelect", "Ptr", _clientSock, "Ptr", A_ScriptHwnd, "UInt", 0x8000, "Int", 0x01 | 0x20) ; FD_READ | FD_CLOSE
}

_SocketOnRecv(wp, lp, msg, hwnd) {
    global _clientSock, _recvBuf, _lastActivity

    buf := Buffer(65536, 0)
    n := DllCall("Ws2_32\recv", "Ptr", _clientSock, "Ptr", buf, "Int", 65536, "Int", 0)
    if n <= 0 {
        _CloseClient()
        return
    }

    _recvBuf .= StrGet(buf, n, "UTF-8")
    _lastActivity := A_TickCount

    ; Process all complete JSON messages (newline-delimited)
    while (pos := InStr(_recvBuf, "`n")) {
        line := SubStr(_recvBuf, 1, pos - 1)
        _recvBuf := SubStr(_recvBuf, pos + 1)
        line := Trim(line, " `t`r")
        if line = ""
            continue
        response := _HandleRequest(line)
        _SendResponse(response)
    }
}

_SendResponse(str) {
    global _clientSock
    buf := Buffer(StrPut(str, "UTF-8"), 0)
    StrPut(str, buf, "UTF-8")
    DllCall("Ws2_32\send", "Ptr", _clientSock, "Ptr", buf, "Int", buf.Size - 1, "Int", 0)
}

_SocketOnClose(wp, lp, msg, hwnd) {
    _CloseClient()
}

_CloseClient() {
    global _clientSock, _recvBuf
    if _clientSock {
        DllCall("Ws2_32\closesocket", "Ptr", _clientSock)
        _clientSock := 0
    }
    _recvBuf := ""
}

_CheckIdle() {
    global _lastActivity, _clientSock
    if !_clientSock && (A_TickCount - _lastActivity > IDLE_TIMEOUT_MS) {
        OutputDebug "UIA_MCP_Engine: idle timeout, shutting down`n"
        _DoShutdown()
    }
}

; ══════════════════════════════════════════════════════════════════
;  Network Helpers
; ══════════════════════════════════════════════════════════════════

_Htons(val) {
    return DllCall("ws2_32\htons", "ushort", val, "ushort")
}

WSAGetLastError() {
    return DllCall("Ws2_32\WSAGetLastError")
}

; WM_SOCKET handler — AHK needs to receive the message via OnMessage
; We use a static variable to avoid registering multiple times
OnMessage(0x8000, _WmSocketHandler)

_WmSocketHandler(wp, lp, msg, hwnd) {
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
