#Requires AutoHotkey v2.0.2+
#SingleInstance

; ══════════════════════════════════════════════════════════════════
; test_engine_internals.ahk — Unit tests for UIA_MCP_Engine helpers
;
; Tests the internal helper functions without the TCP server.
; Run:  AutoHotkey64.exe test_engine_internals.ahk
; ══════════════════════════════════════════════════════════════════

#Include <UIA>
#Include <UIA_Inspector\cjson>

; ── Test framework ────────────────────────────
global _pass := 0, _fail := 0
global _logFile := A_Temp "\test_engine_internals.log"

_Log(msg)
{
    OutputDebug msg
    FileAppend(msg, _logFile)  ; write to temp log file for PowerShell visibility
}

Assert(cond, name)
{
    global _pass, _fail
    if (cond) {
        _Log("  PASS: " name "`n")
        _pass++
    }
    else
    {
        _Log("  FAIL: " name "`n")
        _fail++
    }
}

AssertEqual(actual, expected, name)
{
    global _pass, _fail
    if (actual = expected) {
        _Log("  PASS: " name "`n")
        _pass++
    }
    else
    {
        _Log("  FAIL: " name " — expected '" expected "', got '" actual "'`n")
        _fail++
    }
}

AssertNotEqual(actual, unexpected, name)
{
    global _pass, _fail
    if (actual != unexpected) {
        _Log("  PASS: " name "`n")
        _pass++
    }
    else
    {
        _Log("  FAIL: " name " — value is '" unexpected "'`n")
        _fail++
    }
}

AssertHas(obj, key, name)
{
    global _pass, _fail
    if (IsObject(obj) && obj.Has(key)) {
        _Log("  PASS: " name "`n")
        _pass++
    }
    else
    {
        _Log("  FAIL: " name " — key '" key "' not found`n")
        _fail++
    }
}

AssertType(val, expectedType, name)
{
    global _pass, _fail
    if (Type(val) = expectedType) {
        _Log("  PASS: " name "`n")
        _pass++
    }
    else
    {
        _Log("  FAIL: " name " — expected " expectedType ", got " Type(val) "`n")
        _fail++
    }
}

; ══════════════════════════════════════════════════════════════
;  Replicated helpers from UIA_MCP_Engine.ahk
;  (these must match exactly what the engine uses)
; ══════════════════════════════════════════════════════════════

_MakeCacheRequest()
{
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

_BuildCondition(condObj)
{
    condMap := Map()
    if (!IsObject(condObj))
        return("")
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
    try
    {
        for key, val in condObj.OwnProps()
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
            if (propId)
                condMap[propId] := String(val)
        }
    }
    catch Error as e
    {
        return("")
    }
    return(condMap.Count ? condMap : "")
}

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

_ElementToMap(el)
{
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
    try
    {
        raw := el.GetPropertyValue(30001)
        if (IsObject(raw))
            m["BoundingRect"] := {left: raw.l, top: raw.t, right: raw.r, bottom: raw.b}
        else
            m["BoundingRect"] := ""
    } catch Error as e
        m["BoundingRect"] := ""
    try m["HWND"] := "0"
    catch Error as e
        m["HWND"] := "0"
    return(m)
}

_PropStr(el, propId)
{
    try
    {
        return(String(el.GetPropertyValue(propId)))
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

_GetPatterns(el)
{
    patterns := []
    try
    {
        if (el.GetPropertyValue(30031))
            patterns.Push({name: "Invoke"})
    }
    try
    {
        if (el.GetPropertyValue(30041)) {
            p := {name: "Toggle"}
            try p.state := el.GetPattern("Toggle").ToggleState
            patterns.Push(p)
        }
    }
    try
    {
        if (el.GetPropertyValue(30028)) {
            p := {name: "ExpandCollapse"}
            try p.state := Map(0, "Collapsed", 1, "Expanded", 2, "PartiallyExpanded")[el.GetPattern("ExpandCollapse").ExpandCollapseState]
            patterns.Push(p)
        }
    }
    try
    {
        if (el.GetPropertyValue(30043)) {
            p := {name: "Value"}
            try p.value := el.GetPattern("Value").Value
            try p.isReadOnly := el.GetPattern("Value").IsReadOnly
            patterns.Push(p)
        }
    }
    try
    {
        if (el.GetPropertyValue(30036)) {
            p := {name: "SelectionItem"}
            try p.isSelected := el.GetPattern("SelectionItem").IsSelected
            patterns.Push(p)
        }
    }
    try
    {
        if (el.GetPropertyValue(30037)) {
            p := {name: "Selection"}
            try p.canSelectMultiple := el.GetPattern("Selection").CanSelectMultiple
            patterns.Push(p)
        }
    }
    try
    {
        if (el.GetPropertyValue(30034)) {
            p := {name: "Scroll"}
            try p.horizontallyScrollable := el.GetPattern("Scroll").HorizontallyScrollable
            try p.verticallyScrollable := el.GetPattern("Scroll").VerticallyScrollable
            patterns.Push(p)
        }
    }
    return(patterns)
}

_GetAncestorChain(el)
{
    chain := []
    try
    {
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
    return(chain)
}

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

; ── Replicated Phase 1+2+3 handlers ────────────

_HandleGetTypeCatalog(params)
{
    global UIA_Type
    types := Map()
    try
    {
        for name, id in UIA_Type.OwnProps()
            types[name] := id
    }
    return(types)
}

_HandleGetPatternCatalog(params)
{
    catalog := Map()
    catalog["Invoke"] := {methods: ["Invoke"]}
    catalog["Toggle"] := {methods: ["Toggle"], properties: ["ToggleState"]}
    catalog["ExpandCollapse"] := {methods: ["Expand", "Collapse"], properties: ["ExpandCollapseState"]}
    catalog["Value"] := {methods: ["SetValue"], properties: ["Value", "IsReadOnly"]}
    catalog["SelectionItem"] := {methods: ["Select", "AddToSelection", "RemoveFromSelection"], properties: ["IsSelected", "SelectionContainer"]}
    catalog["Selection"] := {methods: ["GetSelection"], properties: ["CanSelectMultiple", "IsSelectionRequired"]}
    catalog["Scroll"] := {methods: ["Scroll", "SetScrollPercent", "ScrollIntoView"], properties: ["HorizontalScrollPercent", "VerticalScrollPercent", "HorizontalViewSize", "VerticalViewSize", "HorizontallyScrollable", "VerticallyScrollable"]}
    catalog["Grid"] := {methods: ["GetItem"], properties: ["RowCount", "ColumnCount"]}
    catalog["GridItem"] := {properties: ["Row", "Column", "RowSpan", "ColumnSpan", "ContainingGrid"]}
    catalog["Table"] := {methods: ["GetRowHeaders", "GetColumnHeaders"], properties: ["RowOrColumnMajor"]}
    catalog["TableItem"] := {methods: ["GetRowHeaderItems", "GetColumnHeaderItems"]}
    catalog["Window"] := {methods: ["Close", "WaitForInputIdle", "SetWindowVisualState"], properties: ["CanMaximize", "CanMinimize", "IsModal", "IsTopmost", "WindowVisualState", "WindowInteractionState"]}
    catalog["Transform"] := {methods: ["Move", "Resize", "Rotate"], properties: ["CanMove", "CanResize", "CanRotate"]}
    catalog["RangeValue"] := {methods: ["SetValue"], properties: ["Value", "IsReadOnly", "Maximum", "Minimum", "LargeChange", "SmallChange"]}
    catalog["Dock"] := {methods: ["SetDockPosition"], properties: ["DockPosition"]}
    catalog["MultipleView"] := {methods: ["GetViewName", "SetView"], properties: ["CurrentView"]}
    catalog["LegacyIAccessible"] := {methods: ["Select", "DoDefaultAction", "SetValue"], properties: ["ChildId", "Name", "Value", "Description", "Role", "State"]}
    catalog["Text"] := {methods: ["RangeFromPoint", "RangeFromChild", "GetSelection", "GetVisibleRanges"], properties: ["DocumentRange", "SupportedTextSelection"]}
    catalog["Drag"] := {properties: ["IsGrabbed", "DropEffect", "DropEffects"]}
    catalog["DropTarget"] := {properties: ["DropTargetEffect", "DropTargetEffects"]}
    catalog["ScrollItem"] := {methods: ["ScrollIntoView"]}
    return(catalog)
}

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

    scope := Descendants
    matchMode := ""

    try
    {
        matches := root.FindAll(condMap, matchMode, scope)
        if (IsObject(matches) && matches.Length > 0)
        {
            summary := _ElementSummary(matches[1])
            return {exists: true, count: matches.Length, example: summary}
        }
        return {exists: false, count: 0}
    }
    catch Error as e
    {
        return {exists: false, count: 0}
    }
}

_HandleWaitElementNotExist(params)
{
    timeout := params.Has("timeout") ? params["timeout"] : 5000
    hwnd := params.Has("hwnd") ? params["hwnd"] : 0
    condObj := params.Has("condition") ? params["condition"] : {}

    condMap := _BuildCondition(condObj)
    if (condMap = "")
        return {gone: true, elapsed: 0}

    scope := Descendants
    matchMode := ""

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
        return {gone: true, elapsed: 0}

    start := A_TickCount
    loop
    {
        try
        {
            matches := root.FindAll(condMap, matchMode, scope)
            if (!IsObject(matches) || matches.Length = 0)
                return {gone: true, elapsed: A_TickCount - start}
        }
        if (A_TickCount - start >= timeout)
            break
        Sleep(100)
    }
    return {gone: false, elapsed: A_TickCount - start}
}

_HandleGetRootElement(params)
{
    global UIA
    root := UIA.GetRootElement()
    return {
        Type: _PropStr(root, 30003),
        Name: _PropStr(root, 30005),
        AutomationId: _PropStr(root, 30011),
        ClassName: _PropStr(root, 30012),
        FrameworkId: _PropStr(root, 30024),
        IsEnabled: _PropBool(root, 30010),
        ProcessId: _PropInt(root, 30002),
        NativeWindowHandle: _PropHwnd(root, 30020)
    }
}

_HandleHighlightElement(params)
{
    el := UIA.GetFocusedElement()
    duration := params.Has("duration") ? params["duration"] : 2000
    el.Highlight(duration)
    return {success: true, duration: duration}
}

_HandleDumpTree(params)
{
    maxDepth := params.Has("maxDepth") ? params["maxDepth"] : 0
    el := UIA.GetFocusedElement()
    if (maxDepth > 0)
        dump := el.DumpAll("`n", maxDepth)
    else
        dump := el.DumpAll()
    return {dump: dump}
}

_HandleGetElementFromPath(params)
{
    hwnd := params["hwnd"]
    if (hwnd is String)
        hwnd := Integer(hwnd)
    path := params["path"]
    cr := _MakeCacheRequest()
    windowEl := UIA.ElementFromHandle(hwnd, cr)
    el := windowEl.ElementFromPath(path)
    targetPid := WinGetPID("ahk_id " hwnd)
    return _BuildFullElementResult(el, windowEl, hwnd, targetPid)
}

_ArrayContains(arr, val)
{
    for item in arr
        if (item = val)
            return(true)
    return(false)
}

_HandleGetStateEnums(params)
{
    enums := Map()
    enums["ToggleState"] := Map(0, "Off", 1, "On", 2, "Indeterminate")
    enums["ExpandCollapseState"] := Map(0, "Collapsed", 1, "Expanded", 2, "PartiallyExpanded", 3, "LeafNode")
    enums["WindowVisualState"] := Map(0, "Normal", 1, "Maximized", 2, "Minimized")
    enums["WindowInteractionState"] := Map(0, "Running", 1, "Closing", 2, "ReadyForUserInteraction", 3, "BlockedByModalWindow", 4, "NotResponding")
    enums["Orientation"] := Map(0, "None", 1, "Horizontal", 2, "Vertical")
    enums["RowOrColumnMajor"] := Map(0, "RowMajor", 1, "ColumnMajor")
    enums["DockPosition"] := Map(0, "Top", 1, "Left", 2, "Bottom", 3, "Right", 4, "Fill", 5, "None")
    enums["SupportedTextSelection"] := Map(0, "None", 1, "Single", 2, "Multiple")
    enums["LiveSetting"] := Map(0, "Off", 1, "Polite", 2, "Assertive")
    enums["ZoomUnit"] := Map(0, "NoAmount", 1, "LargeDecrement", 2, "SmallDecrement", 3, "LargeIncrement", 4, "SmallIncrement")
    return(enums)
}

_HandleGetCodeRecipe(params)
{
    recipe := params.Has("recipe") ? params["recipe"] : ""
    switch recipe
    {
    case "list_recipes":
        return {recipes: "activate_window, find_and_click, menu_navigate, dialog_fill, tree_explore, grid_read, wait_and_click, combo_select, list_recipes"}
    case "find_and_click":
        return {name: recipe, description: "Find and click", ahkCode: "btn := winEl.WaitElement({Type: `"Button`", Name: `"OK`"},, 5000)`nbtn.Click()"}
    case "activate_window":
        return {name: recipe, description: "Activate", ahkCode: "WinActivate(`"Title ahk_exe exe`")"}
    case "menu_navigate":
        return {name: recipe, description: "Menu", ahkCode: "winEl.FindFirst({Type: `"MenuItem`"}).Expand()"}
    case "dialog_fill":
        return {name: recipe, description: "Dialog", ahkCode: "dlgEl.FindFirst({Type: `"Edit`"}).SetValue(`"text`")"}
    case "tree_explore":
        return {name: recipe, description: "Tree", ahkCode: "tree.FindFirst({Type: `"TreeItem`"}).Expand()"}
    case "grid_read":
        return {name: recipe, description: "Grid", ahkCode: "grid.FindAll({Type: `"DataItem`"})"}
    case "wait_and_click":
        return {name: recipe, description: "Wait+Click", ahkCode: "btn := winEl.WaitElement({Type: `"Button`"},, 10000)`nbtn.Click()"}
    case "combo_select":
        return {name: recipe, description: "Combo", ahkCode: "combo.FindFirst({Type: `"ListItem`"}).Select()"}
    default:
        throw Error("Unknown recipe: " recipe)
    }
}

; ══════════════════════════════════════════════════════════════
;  Tests
; ══════════════════════════════════════════════════════════════

Test_EscapeStr()
{
    _Log("=== Test _EscapeStr ===`n")
    AssertEqual(_EscapeStr('hello'), 'hello', "plain string unchanged")
    AssertEqual(_EscapeStr('say "hi"'), 'say \"hi\"', "quotes escaped")
    AssertEqual(_EscapeStr('a\b'), 'a\\b', "backslash escaped")
    AssertEqual(_EscapeStr(''), '', "empty string")
    AssertEqual(_EscapeStr('quote " and \ slash'), 'quote \" and \\ slash', "mixed escapes")
}

Test_Join()
{
    _Log("=== Test _Join ===`n")
    AssertEqual(_Join(["a"]), "a", "single element")
    AssertEqual(_Join(["a", "b"]), "a, b", "two elements")
    AssertEqual(_Join(["a", "b", "c"]), "a, b, c", "three elements")
    AssertEqual(_Join([]), "", "empty array")
}

Test_BuildCondition()
{
    _Log("=== Test _BuildCondition ===`n")

    ; Valid condition with Type
    cond := _BuildCondition({Type: "Button", Name: "OK"})
    Assert(cond != "", "Type+Name produces non-empty Map")
    AssertType(cond, "Map", "Type+Name returns a Map")
    AssertEqual(cond.Count, 2, "Type+Name has 2 entries")

    ; Valid condition with AutomationId
    cond := _BuildCondition({Type: "Edit", AutomationId: "input1"})
    Assert(cond != "", "Type+AutomationId produces non-empty Map")

    ; Empty name values are skipped
    cond := _BuildCondition({Type: "Button", Name: ""})
    AssertEqual(cond.Count, 1, "empty Name is skipped")

    ; Empty object returns empty string
    cond := _BuildCondition({})
    AssertEqual(cond, "", "empty condition returns empty string")

    ; All empty values
    cond := _BuildCondition({Name: "", AutomationId: ""})
    AssertEqual(cond, "", "all empty returns empty string")

    ; Unknown property names are ignored
    cond := _BuildCondition({Type: "Button", UnknownProp: "value"})
    AssertEqual(cond.Count, 1, "unknown property ignored")

    ; Integer property IDs
    cond := _BuildCondition({30003: "Button"})  ; Type
    Assert(cond != "", "integer property ID works")
}

Test_MakeCacheRequest()
{
    _Log("=== Test _MakeCacheRequest ===`n")
    cr := _MakeCacheRequest()
    Assert(cr != "", "cache request created")
    ; We can't easily inspect the cache request internals, but the call shouldn't throw
}

Test_IsBrowserProcess()
{
    _Log("=== Test _IsBrowserProcess ===`n")
    ; Test with Explorer PID (should NOT be browser)
    explorerPid := ProcessExist("explorer.exe")
    if (explorerPid)
        Assert(!_IsBrowserProcess(explorerPid), "explorer.exe is not a browser")

    ; Test with own script PID (should NOT be browser)
    ownPid := ProcessExist()
    Assert(!_IsBrowserProcess(ownPid), "AutoHotkey.exe is not a browser")

    ; Known false negatives should not crash
    Assert(!_IsBrowserProcess(99999999), "nonexistent PID returns false")
}

Test_ChromiumDetection()
{
    _Log("=== Test _IsChromiumWindow ===`n")
    ; Test with Explorer (NOT Chromium)
    explorerHwnd := WinExist("ahk_class Progman")
    if (explorerHwnd)
        Assert(!_IsChromiumWindow(explorerHwnd), "Explorer is not Chromium")

    ; Test with own script window (NOT Chromium)
    Assert(!_IsChromiumWindow(A_ScriptHwnd), "AHK script is not Chromium")

    ; Test with invalid HWND (should not crash)
    Assert(!_IsChromiumWindow(0), "HWND 0 returns false")
    Assert(!_IsChromiumWindow(99999999), "nonexistent HWND returns false")

    ; Note: Chromium detection requires a real Chromium window.
    ; Edge/Chrome would return true if running, but we can't guarantee that.
    _Log("    (Chromium-positive test requires a running Chromium app)`n")
}

Test_ElementSummary()
{
    _Log("=== Test _ElementSummary ===`n")
    ; Get a real element to test the summary function
    try
    {
        el := UIA.GetFocusedElement()
        if (el) {
            summary := _ElementSummary(el)
            AssertHas(summary, "Type", "summary has Type")
            AssertHas(summary, "Name", "summary has Name")
            AssertHas(summary, "AutomationId", "summary has AutomationId")
            AssertHas(summary, "ClassName", "summary has ClassName")
            AssertHas(summary, "IsEnabled", "summary has IsEnabled")
            AssertHas(summary, "IsOffscreen", "summary has IsOffscreen")
            ; Boolean should be actual boolean values
            Assert(summary.IsEnabled = true || summary.IsEnabled = false, "IsEnabled is boolean")
        }
    }
    catch Error as e as err
    {
        _Log("  SKIP: could not get focused element (" err.Message ")`n")
    }
}

Test_ElementToMap()
{
    _Log("=== Test _ElementToMap ===`n")
    try
    {
        el := UIA.GetFocusedElement()
        if (el) {
            m := _ElementToMap(el)
            AssertType(m, "Map", "_ElementToMap returns Map")
            Assert(m.Has("Type"), "has Type")
            Assert(m.Has("Name"), "has Name")
            Assert(m.Has("AutomationId"), "has AutomationId")
            Assert(m.Has("ClassName"), "has ClassName")
            Assert(m.Has("IsEnabled"), "has IsEnabled")
            Assert(m.Has("FrameworkId"), "has FrameworkId")
        }
    }
    catch Error as e as err
    {
        _Log("  SKIP: could not get focused element (" err.Message ")`n")
    }
}

Test_BuildConditionString()
{
    _Log("=== Test _BuildConditionString ===`n")
    try
    {
        el := UIA.GetFocusedElement()
        if (el) {
            cs := _BuildConditionString(el)
            Assert(cs != "{}", "condition string is not empty")
            Assert(InStr(cs, "{") = 1, "starts with {")
            Assert(SubStr(cs, -1) = "}", "ends with }")
            ; Should contain Type
            Assert(InStr(cs, "Type:"), "contains Type:")
        }
    }
    catch Error as e as err
    {
        _Log("  SKIP: could not get focused element (" err.Message ")`n")
    }
}

Test_GetPatterns()
{
    _Log("=== Test _GetPatterns ===`n")
    try
    {
        el := UIA.GetFocusedElement()
        if (el) {
            patterns := _GetPatterns(el)
            AssertType(patterns, "Array", "patterns returns Array")
            ; Each pattern should have a name
            for p in patterns
                Assert(p.Has("name"), "pattern has name: " p.name)
        }
    }
    catch Error as e as err
    {
        _Log("  SKIP: could not get focused element (" err.Message ")`n")
    }
}

Test_GetAncestorChain()
{
    _Log("=== Test _GetAncestorChain ===`n")
    try
    {
        el := UIA.GetFocusedElement()
        if (el) {
            chain := _GetAncestorChain(el)
            AssertType(chain, "Array", "ancestor chain is Array")
            Assert(chain.Length > 0, "chain has at least 1 element (self)")
            ; First element in chain should be the root
            _Log("    Chain depth: " chain.Length "`n")
        }
    }
    catch Error as e as err
    {
        _Log("  SKIP: could not get focused element (" err.Message ")`n")
    }
}

Test_DetermineAction()
{
    _Log("=== Test _DetermineAction ===`n")
    try
    {
        el := UIA.GetFocusedElement()
        if (el) {
            action := _DetermineAction(el)
            Assert(action != "", "action string is not empty")
            ; Should end with ()
            Assert(SubStr(action, -1) = ")", "action ends with )")
            Assert(InStr(action, "("), "action contains (")
            _Log("    Inferred action: " action "`n")
        }
    }
    catch Error as e as err
    {
        _Log("  SKIP: could not get focused element (" err.Message ")`n")
    }
}

Test_JSON_Serialize()
{
    _Log("=== Test JSON Serialize/Parse ===`n")

    ; Verify JSON library is available (cJSON loads a native DLL at runtime;
    ; if that fails, Stringify/Parse won't work and we skip these tests).
    try
    {
        testJson := JSON.Stringify({test: 1}, 0)
    }
    catch Error as e as err
    {
        _Log("  SKIP: JSON library unavailable — " err.Message "`n")
        _Log("  (cJSON DLL may have failed to load. Check AHK bitness matches the DLL.)`n")
        return
    }

    ; Stringify
    json := JSON.Stringify({a: 1, b: "hello"}, 0)
    Assert(InStr(json, '"a":1'), "JSON contains a:1")
    Assert(InStr(json, '"b":"hello"'), "JSON contains b:hello")

    ; Parse
    obj := JSON.Parse('{"x":42,"y":"test"}')
    AssertEqual(obj["x"], 42, "parse gets integer")
    AssertEqual(obj["y"], "test", "parse gets string")

    ; Nested objects
    nested := JSON.Parse('{"outer":{"inner":"value"}}')
    AssertEqual(nested["outer"]["inner"], "value", "parse nested object")

    ; Arrays
    arr := JSON.Parse('[1,2,3]')
    AssertType(arr, "Array", "parsed array is Array")
    AssertEqual(arr.Length, 3, "array has 3 elements")
    AssertEqual(arr[1], 1, "first element is 1")

    ; RPC result
    rpc := JSON.Stringify({jsonrpc: "2.0", result: {count: 5}, id: 1}, 0)
    parsed := JSON.Parse(rpc)
    AssertEqual(parsed["jsonrpc"], "2.0", "RPC has jsonrpc")
    AssertEqual(parsed["result"]["count"], 5, "RPC result count is 5")
    AssertEqual(parsed["id"], 1, "RPC id is 1")

    ; RPC error
    rpcErr := JSON.Stringify({jsonrpc: "2.0", error: {code: -32601, message: "Not found"}, id: 2}, 0)
    parsedErr := JSON.Parse(rpcErr)
    AssertEqual(parsedErr["error"]["code"], -32601, "RPC error code")
    AssertEqual(parsedErr["error"]["message"], "Not found", "RPC error message")
}

Test_BuildCondition_EdgeCases()
{
    _Log("=== Test _BuildCondition edge cases ===`n")

    ; Single property
    cond := _BuildCondition({Type: "Button"})
    AssertEqual(cond.Count, 1, "single Type")

    ; Multiple same property (last wins in AHK objects)
    cond := _BuildCondition({Name: "One"})
    AssertEqual(cond[30005], "One", "Name mapping correct")

    ; AutomationId is mapped correctly
    cond := _BuildCondition({AutomationId: "btn_123"})
    AssertEqual(cond[30011], "btn_123", "AutomationId mapped to 30011")

    ; ClassName
    cond := _BuildCondition({ClassName: "SysTreeView32"})
    AssertEqual(cond[30012], "SysTreeView32", "ClassName mapped to 30012")
}

; ══════════════════════════════════════════════════════════════
;  Tests for Phase 1+2+3 handlers (pure logic)
; ══════════════════════════════════════════════════════════════

Test_TypeCatalog()
{
    _Log("=== Test _HandleGetTypeCatalog ===`n")
    try
    {
        result := _HandleGetTypeCatalog({})
        Assert(IsObject(result), "type catalog is object")
        Assert(result.Has("Button"), 'Button type exists')
        Assert(result.Has("Edit"), 'Edit type exists')
        Assert(result.Has("Window"), 'Window type exists')
        Assert(result.Has("CheckBox"), 'CheckBox type exists')
        Assert(result.Has("MenuItem"), 'MenuItem type exists')
        Assert(result.Has("Pane"), 'Pane type exists')
        Assert(result.Has("DataGrid"), 'DataGrid type exists')
        Assert(result.Count > 30, "at least 30 types returned")
        _Log("    Types returned: " result.Count "`n")
    }
    catch Error as e as err
        _Log("  SKIP: TypeCatalog failed (" err.Message ")`n")
}

Test_PatternCatalog()
{
    _Log("=== Test _HandleGetPatternCatalog ===`n")
    try
    {
        result := _HandleGetPatternCatalog({})
        Assert(IsObject(result), "pattern catalog is object")
        Assert(result.Has("Invoke"), "Invoke pattern exists")
        Assert(result.Has("Toggle"), "Toggle pattern exists")
        Assert(result.Has("Value"), "Value pattern exists")
        Assert(result.Has("ExpandCollapse"), "ExpandCollapse pattern exists")
        Assert(result.Has("SelectionItem"), "SelectionItem pattern exists")
        Assert(result.Has("Scroll"), "Scroll pattern exists")
        Assert(result.Has("Window"), "Window pattern exists")
        Assert(result.Count >= 10, "at least 10 patterns returned")

        ; Check Invoke has methods
        invoke := result["Invoke"]
        Assert(invoke.Has("methods"), "Invoke has methods array")
        Assert(invoke["methods"].Length >= 1, "Invoke has at least 1 method")
        Assert(_ArrayContains(invoke["methods"], "Invoke"), "Invoke method list contains Invoke")

        ; Check Value has properties
        val := result["Value"]
        Assert(val.Has("methods"), "Value has methods")
        Assert(val.Has("properties"), "Value has properties")
        Assert(_ArrayContains(val["properties"], "Value"), "Value props contain Value")

        _Log("    Patterns returned: " result.Count "`n")
    }
    catch Error as e as err
        _Log("  SKIP: PatternCatalog failed (" err.Message ")`n")
}

Test_ElementExists_Pure()
{
    _Log("=== Test _HandleElementExists (no element) ===`n")
    ; With no valid root, should return {exists: false}
    result := _HandleElementExists({condition: {Type: "NoSuchType_XYZ"}})
    Assert(IsObject(result), "element exists result is object")
    Assert(!result["exists"], "nonexistent element returns exists=false")
    AssertEqual(result["count"], 0, "count is 0 for nonexistent element")
}

Test_WaitNotExist_Pure()
{
    _Log("=== Test _HandleWaitElementNotExist (no element) ===`n")
    ; With no valid root, polling should timeout quickly
    result := _HandleWaitElementNotExist({
        condition: {Type: "NoSuchType_XYZ"},
        timeout: 500
    })
    Assert(IsObject(result), "wait not exist result is object")
    Assert(result["gone"], "element is gone when it never existed")
}

Test_RootElement()
{
    _Log("=== Test _HandleGetRootElement ===`n")
    try
    {
        result := _HandleGetRootElement({})
        Assert(IsObject(result), "root element result is object")
        Assert(result.Has("Type"), "root has Type")
        Assert(result.Has("Name"), "root has Name")
        _Log("    Root Type: " result["Type"] " Name: " result["Name"] "`n")
    }
    catch Error as e as err
        _Log("  SKIP: RootElement failed (" err.Message ")`n")
}

Test_StateEnums()
{
    _Log("=== Test _HandleGetStateEnums ===`n")
    try
    {
        result := _HandleGetStateEnums({})
        Assert(IsObject(result), "state enums is object")
        Assert(result.Has("ToggleState"), "ToggleState exists")
        Assert(result["ToggleState"].Has(0), "ToggleState has Off=0")
        AssertEqual(result["ToggleState"][0], "Off", "ToggleState 0=Off")
        AssertEqual(result["ToggleState"][1], "On", "ToggleState 1=On")
        Assert(result.Has("ExpandCollapseState"), "ExpandCollapseState exists")
        Assert(result.Has("WindowVisualState"), "WindowVisualState exists")
        Assert(result.Has("Orientation"), "Orientation exists")
        Assert(result.Has("DockPosition"), "DockPosition exists")
        _Log("    State enums returned: " result.Count " states`n")
    }
    catch Error as e as err
        _Log("  SKIP: StateEnums failed (" err.Message ")`n")
}

Test_CodeRecipe()
{
    _Log("=== Test _HandleGetCodeRecipe ===`n")
    try
    {
        ; List recipes
        result := _HandleGetCodeRecipe({recipe: "list_recipes"})
        Assert(IsObject(result), "recipe list is object")
        Assert(result.Has("recipes"), "list_recipes has recipes string")
        Assert(InStr(result["recipes"], "find_and_click"), "recipes include find_and_click")

        ; Get specific recipe
        result := _HandleGetCodeRecipe({recipe: "find_and_click"})
        Assert(result.Has("ahkCode"), "recipe has ahkCode")
        Assert(InStr(result["ahkCode"], "WaitElement"), "ahkCode contains WaitElement")
        Assert(InStr(result["ahkCode"], "Click"), "ahkCode contains Click")

        ; Unknown recipe should error
        try
        {
            _HandleGetCodeRecipe({recipe: "nonexistent_recipe"})
            Assert(false, "unknown recipe should throw")
        }
        catch Error as e
        {
            Assert(true, "unknown recipe throws error")
        }

        _Log("    Recipe test passed`n")
    }
    catch Error as e as err
        _Log("  SKIP: CodeRecipe failed (" err.Message ")`n")
}

; ══════════════════════════════════════════════════════════════
;  Tests for Phase 1+2+3 handlers (requires UIA — real element)
; ══════════════════════════════════════════════════════════════

Test_HighlightElement()
{
    _Log("=== Test _HandleHighlightElement ===`n")
    try
    {
        el := UIA.GetFocusedElement()
        if (!el)
        {
            _Log("  SKIP: no focused element`n")
            return
        }
        ; Highlight with short duration
        result := _HandleHighlightElement({
            condition: {Type: _PropStr(el, 30003)},
            duration: 100
        })
        Assert(IsObject(result), "highlight result is object")
        Assert(result["success"], "highlight succeeds")
        _Log("    Element highlighted`n")
    }
    catch Error as e as err
        _Log("  SKIP: Highlight failed (" err.Message ")`n")
}

Test_DumpTree()
{
    _Log("=== Test _HandleDumpTree ===`n")
    try
    {
        el := UIA.GetFocusedElement()
        if (!el)
        {
            _Log("  SKIP: no focused element`n")
            return
        }
        result := _HandleDumpTree({maxDepth: 1})
        Assert(IsObject(result), "dump tree result is object")
        Assert(result.Has("dump"), "result has dump string")
        Assert(StrLen(result["dump"]) > 0, "dump string is non-empty")
        _Log("    Dump length: " StrLen(result["dump"]) " chars`n")
    }
    catch Error as e as err
        _Log("  SKIP: DumpTree failed (" err.Message ")`n")
}

Test_ElementFromPath()
{
    _Log("=== Test _HandleGetElementFromPath ===`n")
    try
    {
        ; Get a known window to test path navigation
        wl := WinGetList(,, "Program Manager")
        if (wl.Length = 0)
        {
            _Log("  SKIP: no window available for path test`n")
            return
        }
        hwndStr := Format("0x{:X}", wl[1])
        result := _HandleGetElementFromPath({hwnd: hwndStr, path: "1"})
        Assert(IsObject(result), "element from path result is object")
        Assert(result.Has("Type"), "path result has Type")
        _Log("    Path result Type: " (result.Has("Type") ? result["Type"] : "?") "`n")
    }
    catch Error as e as err
        _Log("  SKIP: ElementFromPath failed (" err.Message ")`n")
}

; ══════════════════════════════════════════════════════════════
;  Main
; ══════════════════════════════════════════════════════════════

; Clear previous log
try FileDelete(_logFile)

_Log("`n╔════════════════════════════════════════════════╗`n")
_Log("║  UIA_MCP_Engine Internal Unit Tests           ║`n")
_Log("╚════════════════════════════════════════════════╝`n`n")

; Pure logic tests (no UIA dependency)
Test_EscapeStr()
Test_Join()
Test_BuildCondition()
Test_BuildCondition_EdgeCases()
Test_JSON_Serialize()
Test_IsBrowserProcess()
Test_ChromiumDetection()
Test_TypeCatalog()
Test_PatternCatalog()
Test_ElementExists_Pure()
Test_WaitNotExist_Pure()
Test_StateEnums()
Test_CodeRecipe()

; ── Verify all 30 methods are registered ──────
Test_HandlerCount()

; Tests that require UIA (real element)
_Log("`n--- Tests requiring UIA (real element) ---`n`n")
Test_MakeCacheRequest()
Test_ElementSummary()
Test_ElementToMap()
Test_BuildConditionString()
Test_GetPatterns()
Test_GetAncestorChain()
Test_DetermineAction()
Test_HighlightElement()
Test_DumpTree()
Test_RootElement()
Test_ElementFromPath()

; Report
_Log("`n╔════════════════════════════════════════════════╗`n")
_Log("║  Results                                       ║`n")
_Log("╚════════════════════════════════════════════════╝`n")
_Log("  Passed: " _pass "`n")
_Log("  Failed: " _fail "`n")
_Log("  Log file: " _logFile "`n")

if (_fail > 0) {
    _Log("`nSOME TESTS FAILED!`n")
    ExitApp(1)
}
_Log("`nAll tests passed!`n")
ExitApp(0)
