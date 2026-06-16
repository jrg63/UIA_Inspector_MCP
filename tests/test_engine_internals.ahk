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

Assert(cond, name) {
    global _pass, _fail
    if cond {
        OutputDebug "  PASS: " name "`n"
        _pass++
    } else {
        OutputDebug "  FAIL: " name "`n"
        _fail++
    }
}

AssertEqual(actual, expected, name) {
    global _pass, _fail
    if actual = expected {
        OutputDebug "  PASS: " name "`n"
        _pass++
    } else {
        OutputDebug "  FAIL: " name " — expected '" expected "', got '" actual "'`n"
        _fail++
    }
}

AssertNotEqual(actual, unexpected, name) {
    global _pass, _fail
    if actual != unexpected {
        OutputDebug "  PASS: " name "`n"
        _pass++
    } else {
        OutputDebug "  FAIL: " name " — value is '" unexpected "'`n"
        _fail++
    }
}

AssertHas(obj, key, name) {
    global _pass, _fail
    if IsObject(obj) && obj.Has(key) {
        OutputDebug "  PASS: " name "`n"
        _pass++
    } else {
        OutputDebug "  FAIL: " name " — key '" key "' not found`n"
        _fail++
    }
}

AssertType(val, expectedType, name) {
    global _pass, _fail
    if Type(val) = expectedType {
        OutputDebug "  PASS: " name "`n"
        _pass++
    } else {
        OutputDebug "  FAIL: " name " — expected " expectedType ", got " Type(val) "`n"
        _fail++
    }
}

; ══════════════════════════════════════════════════════════════
;  Replicated helpers from UIA_MCP_Engine.ahk
;  (these must match exactly what the engine uses)
; ══════════════════════════════════════════════════════════════

_MakeCacheRequest() {
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

_BuildCondition(condObj) {
    condMap := Map()
    if !IsObject(condObj)
        return ""
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
    try {
        for key, val in condObj.OwnProps() {
            if val = ""
                continue
            propId := 0
            if nameToId.Has(key)
                propId := nameToId[key]
            else if key is Integer
                propId := key
            if propId
                condMap[propId] := String(val)
        }
    } catch {
        return ""
    }
    return condMap.Count ? condMap : ""
}

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

_ElementToMap(el) {
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
    try {
        raw := el.GetPropertyValue(30001)
        if IsObject(raw)
            m["BoundingRect"] := {left: raw.l, top: raw.t, right: raw.r, bottom: raw.b}
        else
            m["BoundingRect"] := ""
    } catch
        m["BoundingRect"] := ""
    try m["HWND"] := "0"
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

_GetPatterns(el) {
    patterns := []
    try {
        if el.GetPropertyValue(30031)
            patterns.Push({name: "Invoke"})
    }
    try {
        if el.GetPropertyValue(30041) {
            p := {name: "Toggle"}
            try p.state := el.GetPattern("Toggle").ToggleState
            patterns.Push(p)
        }
    }
    try {
        if el.GetPropertyValue(30028) {
            p := {name: "ExpandCollapse"}
            try p.state := Map(0, "Collapsed", 1, "Expanded", 2, "PartiallyExpanded")[el.GetPattern("ExpandCollapse").ExpandCollapseState]
            patterns.Push(p)
        }
    }
    try {
        if el.GetPropertyValue(30043) {
            p := {name: "Value"}
            try p.value := el.GetPattern("Value").Value
            try p.isReadOnly := el.GetPattern("Value").IsReadOnly
            patterns.Push(p)
        }
    }
    try {
        if el.GetPropertyValue(30036) {
            p := {name: "SelectionItem"}
            try p.isSelected := el.GetPattern("SelectionItem").IsSelected
            patterns.Push(p)
        }
    }
    try {
        if el.GetPropertyValue(30037) {
            p := {name: "Selection"}
            try p.canSelectMultiple := el.GetPattern("Selection").CanSelectMultiple
            patterns.Push(p)
        }
    }
    try {
        if el.GetPropertyValue(30034) {
            p := {name: "Scroll"}
            try p.horizontallyScrollable := el.GetPattern("Scroll").HorizontallyScrollable
            try p.verticallyScrollable := el.GetPattern("Scroll").VerticallyScrollable
            patterns.Push(p)
        }
    }
    return patterns
}

_GetAncestorChain(el) {
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

_IsBrowserProcess(pid) {
    try {
        exe := ProcessGetName(pid)
        exe := StrLower(exe)
        return InStr(exe, "chrome") || InStr(exe, "msedge") || InStr(exe, "opera") || InStr(exe, "brave") || InStr(exe, "firefox")
    }
    return false
}

; ══════════════════════════════════════════════════════════════
;  Tests
; ══════════════════════════════════════════════════════════════

Test_EscapeStr() {
    OutputDebug "=== Test _EscapeStr ===`n"
    AssertEqual(_EscapeStr('hello'), 'hello', "plain string unchanged")
    AssertEqual(_EscapeStr('say "hi"'), 'say \"hi\"', "quotes escaped")
    AssertEqual(_EscapeStr('a\b'), 'a\\b', "backslash escaped")
    AssertEqual(_EscapeStr(''), '', "empty string")
    AssertEqual(_EscapeStr('quote " and \ slash'), 'quote \" and \\ slash', "mixed escapes")
}

Test_Join() {
    OutputDebug "=== Test _Join ===`n"
    AssertEqual(_Join(["a"]), "a", "single element")
    AssertEqual(_Join(["a", "b"]), "a, b", "two elements")
    AssertEqual(_Join(["a", "b", "c"]), "a, b, c", "three elements")
    AssertEqual(_Join([]), "", "empty array")
}

Test_BuildCondition() {
    OutputDebug "=== Test _BuildCondition ===`n"

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

Test_MakeCacheRequest() {
    OutputDebug "=== Test _MakeCacheRequest ===`n"
    cr := _MakeCacheRequest()
    Assert(cr != "", "cache request created")
    ; We can't easily inspect the cache request internals, but the call shouldn't throw
}

Test_IsBrowserProcess() {
    OutputDebug "=== Test _IsBrowserProcess ===`n"
    ; Test with Explorer PID (should NOT be browser)
    explorerPid := ProcessExist("explorer.exe")
    if explorerPid
        Assert(!_IsBrowserProcess(explorerPid), "explorer.exe is not a browser")

    ; Test with own script PID (should NOT be browser)
    ownPid := ProcessExist()
    Assert(!_IsBrowserProcess(ownPid), "AutoHotkey.exe is not a browser")

    ; Known false negatives should not crash
    Assert(!_IsBrowserProcess(99999999), "nonexistent PID returns false")
}

Test_ElementSummary() {
    OutputDebug "=== Test _ElementSummary ===`n"
    ; Get a real element to test the summary function
    try {
        el := UIA.GetFocusedElement()
        if el {
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
    } catch as err {
        OutputDebug "  SKIP: could not get focused element (" err.Message ")`n"
    }
}

Test_ElementToMap() {
    OutputDebug "=== Test _ElementToMap ===`n"
    try {
        el := UIA.GetFocusedElement()
        if el {
            m := _ElementToMap(el)
            AssertType(m, "Map", "_ElementToMap returns Map")
            Assert(m.Has("Type"), "has Type")
            Assert(m.Has("Name"), "has Name")
            Assert(m.Has("AutomationId"), "has AutomationId")
            Assert(m.Has("ClassName"), "has ClassName")
            Assert(m.Has("IsEnabled"), "has IsEnabled")
            Assert(m.Has("FrameworkId"), "has FrameworkId")
        }
    } catch as err {
        OutputDebug "  SKIP: could not get focused element (" err.Message ")`n"
    }
}

Test_BuildConditionString() {
    OutputDebug "=== Test _BuildConditionString ===`n"
    try {
        el := UIA.GetFocusedElement()
        if el {
            cs := _BuildConditionString(el)
            Assert(cs != "{}", "condition string is not empty")
            Assert(InStr(cs, "{") = 1, "starts with {")
            Assert(SubStr(cs, -1) = "}", "ends with }")
            ; Should contain Type
            Assert(InStr(cs, "Type:"), "contains Type:")
        }
    } catch as err {
        OutputDebug "  SKIP: could not get focused element (" err.Message ")`n"
    }
}

Test_GetPatterns() {
    OutputDebug "=== Test _GetPatterns ===`n"
    try {
        el := UIA.GetFocusedElement()
        if el {
            patterns := _GetPatterns(el)
            AssertType(patterns, "Array", "patterns returns Array")
            ; Each pattern should have a name
            for p in patterns
                Assert(p.Has("name"), "pattern has name: " p.name)
        }
    } catch as err {
        OutputDebug "  SKIP: could not get focused element (" err.Message ")`n"
    }
}

Test_GetAncestorChain() {
    OutputDebug "=== Test _GetAncestorChain ===`n"
    try {
        el := UIA.GetFocusedElement()
        if el {
            chain := _GetAncestorChain(el)
            AssertType(chain, "Array", "ancestor chain is Array")
            Assert(chain.Length > 0, "chain has at least 1 element (self)")
            ; First element in chain should be the root
            OutputDebug "    Chain depth: " chain.Length "`n"
        }
    } catch as err {
        OutputDebug "  SKIP: could not get focused element (" err.Message ")`n"
    }
}

Test_DetermineAction() {
    OutputDebug "=== Test _DetermineAction ===`n"
    try {
        el := UIA.GetFocusedElement()
        if el {
            action := _DetermineAction(el)
            Assert(action != "", "action string is not empty")
            ; Should end with ()
            Assert(SubStr(action, -1) = ")", "action ends with )")
            Assert(InStr(action, "("), "action contains (")
            OutputDebug "    Inferred action: " action "`n"
        }
    } catch as err {
        OutputDebug "  SKIP: could not get focused element (" err.Message ")`n"
    }
}

Test_JSON_Serialize() {
    OutputDebug "=== Test JSON Serialize/Parse ===`n"

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

Test_BuildCondition_EdgeCases() {
    OutputDebug "=== Test _BuildCondition edge cases ===`n"

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
;  Main
; ══════════════════════════════════════════════════════════════

OutputDebug "`n╔════════════════════════════════════════════════╗`n"
OutputDebug "║  UIA_MCP_Engine Internal Unit Tests           ║`n"
OutputDebug "╚════════════════════════════════════════════════╝`n`n"

; Pure logic tests (no UIA dependency)
Test_EscapeStr()
Test_Join()
Test_BuildCondition()
Test_BuildCondition_EdgeCases()
Test_JSON_Serialize()
Test_IsBrowserProcess()

; Tests that require UIA (real element)
OutputDebug "`n--- Tests requiring UIA (real element) ---`n`n"
Test_MakeCacheRequest()
Test_ElementSummary()
Test_ElementToMap()
Test_BuildConditionString()
Test_GetPatterns()
Test_GetAncestorChain()
Test_DetermineAction()

; Report
OutputDebug "`n╔════════════════════════════════════════════════╗`n"
OutputDebug "║  Results                                       ║`n"
OutputDebug "╚════════════════════════════════════════════════╝`n"
OutputDebug "  Passed: " _pass "`n"
OutputDebug "  Failed: " _fail "`n"

if _fail > 0 {
    OutputDebug "`nSOME TESTS FAILED!`n"
    ExitApp(1)
}
OutputDebug "`nAll tests passed!`n"
ExitApp(0)
