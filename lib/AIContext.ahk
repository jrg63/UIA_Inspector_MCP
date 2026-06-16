#Requires AutoHotkey v2.0+

; ════════════════════════════════════════════════════════
;  AIContext — builds prompt context for the UIA Inspector
;  AI buttons (Find Unique / Ask AI).
;
;  Pulls data from a UIA_Inspector instance:
;    - Window info rows from inspector.lvWin
;    - Element property rows from inspector.lvProps
;    - Supported patterns + children from inspector.tvPatterns
;    - Current condition string via inspector.BuildConditionString
;    - Last match count from inspector._lastMatchCount
;    - Tree snippet walked from inspector.tvUIA + treeViewMap
; ════════════════════════════════════════════════════════

class AIContext
{
    ; Picks a tree scope via a small modal dialog, blocking until the user chooses.
    ; @returns "" if cancelled, otherwise one of "ancestors", "ancestors+siblings", "full"
    static PickScope(defaultScope := "ancestors+siblings")
    {
        result := {value: ""}
        g := Gui("+AlwaysOnTop +ToolWindow", "Tree scope")
        g.SetFont("s9", "Segoe UI")
        g.AddText("xm ym", "How much of the UIA tree should we send to the AI?")
        rbA := g.AddRadio("xm y+8 Group", "Ancestors + siblings  (compact, recommended)")
        rbB := g.AddRadio("xm y+4",        "Ancestors only        (smallest)")
        rbC := g.AddRadio("xm y+4",        "Full captured tree    (largest)")
        switch defaultScope {
            case "ancestors":           rbB.Value := 1
            case "full":                rbC.Value := 1
            default:                    rbA.Value := 1
        }
        btnOk     := g.AddButton("xm y+12 w80 h24 Default", "Send")
        btnCancel := g.AddButton("x+6 yp w80 h24", "Cancel")
        btnOk.OnEvent("Click", (*) => (
            result.value := rbA.Value ? "ancestors+siblings" : rbB.Value ? "ancestors" : "full",
            g.Destroy()))
        btnCancel.OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Close", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        g.Show()
        WinWaitClose("ahk_id " g.Hwnd)
        return result.value
    }

    ; Build a plain-text summary of the selected element + its window + available
    ; patterns. Intended to be injected as a user-role message before the model
    ; answers.
    ; Walk from the captured element up via UIA.TreeWalkerTrue and produce an
    ; explicit ordered list of ancestors with their identifying fields. This is
    ; the single source of truth the AI must use when choosing an anchor.
    static BuildAncestorPath(inspector)
    {
        if !inspector.capturedElement
            return "(no selection)"
        chain := []
        try {
            el := inspector.capturedElement
            chain.Push(el)
            walker := UIA.TreeWalkerTrue
            parent := walker.GetParentElement(el)
            while parent {
                chain.Push(parent)
                parent := walker.GetParentElement(parent)
            }
        }
        if !chain.Length
            return "(ancestor walk failed)"

        out := "Order: root -> ... -> selected. Every line below is a valid ancestor anchor for the selected element."
        lines := []
        depth := chain.Length - 1
        for i, e in chain {
            idx := chain.Length - i + 1   ; root first
        }
        ; Build root-first
        loop chain.Length {
            e := chain[chain.Length - A_Index + 1]
            tag := (A_Index = chain.Length) ? "SELECTED" : "ANCESTOR"
            typ := "", nm := "", aid := "", cls := ""
            try typ := UIA_Type.HasValue(e.Type)
            try nm  := e.Name
            try aid := e.AutomationId
            try cls := e.ClassName
            desc := "[" tag "] Type='" typ "'"
            if nm  != ""
                desc .= " Name='" nm "'"
            if aid != ""
                desc .= " AutomationId='" aid "'"
            if cls != ""
                desc .= " ClassName='" cls "'"
            out .= "`n" desc
        }
        return out
    }

    static BuildElementSummary(inspector)
    {
        out := "=== SELECTED ELEMENT ==="
        out .= "`n-- Window Info --"
        try {
            loop inspector.lvWin.GetCount() {
                row := A_Index
                out .= "`n" inspector.lvWin.GetText(row, 1) ": " inspector.lvWin.GetText(row, 2)
            }
        }

        out .= "`n`n-- Properties --"
        try {
            loop inspector.lvProps.GetCount() {
                row := A_Index
                name := inspector.lvProps.GetText(row, 1)
                val  := inspector.lvProps.GetText(row, 2)
                if (name != "" || val != "")
                    out .= "`n" name ": " val
            }
        }

        out .= "`n`n-- Supported Patterns --"
        try {
            patNode := inspector.tvPatterns.GetChild(0)
            while patNode {
                out .= "`n* " inspector.tvPatterns.GetText(patNode)
                child := inspector.tvPatterns.GetChild(patNode)
                while child {
                    out .= "`n    - " inspector.tvPatterns.GetText(child)
                    child := inspector.tvPatterns.GetNext(child)
                }
                patNode := inspector.tvPatterns.GetNext(patNode)
            }
        }

        out .= "`n`n-- Current condition (non-unique) --"
        try {
            cond := inspector.BuildConditionString(inspector.capturedElement)
            out .= "`n" cond
            out .= "`nCurrent match count: " inspector._lastMatchCount
        }

        try {
            action := inspector._DetermineAction(inspector.capturedElement)
            out .= "`n`n-- Inferred action --`n" action
        }

        return out
    }

    ; Build a compact text representation of the UIA tree, marking the selected
    ; element with "<<< SELECTED" on its line.
    ;   scope = "ancestors"            : captured element's ancestor chain only
    ;   scope = "ancestors+siblings"   : ancestors plus each ancestor's direct siblings
    ;   scope = "full"                 : every element currently in treeViewMap
    static BuildTreeSnippet(inspector, scope := "ancestors+siblings")
    {
        if !inspector.treeViewMap.Count
            return "(empty tree)"

        ; Reverse lookup: UIA element => tvItem id
        elToItem := Map()
        for tvItem, el in inspector.treeViewMap
            elToItem[el] := tvItem

        selectedItem := 0
        if inspector.capturedElement && elToItem.Has(inspector.capturedElement)
            selectedItem := elToItem[inspector.capturedElement]

        out := "=== UIA TREE (scope=" scope ") ==="

        if scope = "full" {
            ; Walk the whole visible tree depth-first
            AIContext._DumpSubtree(inspector, 0, selectedItem, &out, 0)
            return out
        }

        ; Build the ancestor chain of the selected item
        chain := []
        cur := selectedItem
        while cur {
            chain.InsertAt(1, cur)
            cur := inspector.tvUIA.GetParent(cur)
        }
        if !chain.Length {
            ; No selection — fall back to roots
            AIContext._DumpSubtree(inspector, 0, selectedItem, &out, 0)
            return out
        }

        out .= "`nLegend: '==>' = on the selected element's ancestor path (valid parent to chain from); '<<< SELECTED' = the exact element to target; other lines are siblings (NOT ancestors — do not use them as anchors)."
        depth := 0
        for tvItem in chain {
            isSel := (tvItem = selectedItem)
            AIContext._AppendItemLine(inspector, tvItem, depth, isSel, &out, "", true)
            if scope = "ancestors+siblings" {
                parent := inspector.tvUIA.GetParent(tvItem)
                sib := inspector.tvUIA.GetChild(parent)
                while sib {
                    if sib != tvItem
                        AIContext._AppendItemLine(inspector, sib, depth, false, &out, "  (sibling of ancestor — NOT on selected path)", false)
                    sib := inspector.tvUIA.GetNext(sib)
                }
            }
            depth += 1
        }

        ; Include direct children of selected element (useful context)
        if selectedItem {
            child := inspector.tvUIA.GetChild(selectedItem)
            while child {
                AIContext._AppendItemLine(inspector, child, depth, false, &out, "  (child of selected)", false)
                child := inspector.tvUIA.GetNext(child)
            }
        }

        return out
    }

    static _DumpSubtree(inspector, parentItem, selectedItem, &out, depth)
    {
        item := inspector.tvUIA.GetChild(parentItem)
        while item {
            AIContext._AppendItemLine(inspector, item, depth, item = selectedItem, &out)
            AIContext._DumpSubtree(inspector, item, selectedItem, &out, depth + 1)
            item := inspector.tvUIA.GetNext(item)
        }
    }

    static _AppendItemLine(inspector, tvItem, depth, isSelected, &out, suffix := "", onPath := false)
    {
        indent := ""
        loop depth
            indent .= "  "
        label := ""
        try label := inspector.tvUIA.GetText(tvItem)
        prefix := isSelected ? "==>" : onPath ? "==>" : "   "
        marker := isSelected ? "  <<< SELECTED" : ""
        out .= "`n" prefix " " indent "[" depth "] " label suffix marker
    }
}
