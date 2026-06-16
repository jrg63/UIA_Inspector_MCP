#Requires AutoHotkey v2.0+

; ════════════════════════════════════════════════════════
;  AskAIChat — persistent, non-modal chat GUI bound to a
;  UIA_Inspector instance. User types questions, we prepend
;  UI-context as a system-authored user turn.
; ════════════════════════════════════════════════════════

class AskAIChat
{
    inspector := ""     ; parent UIA_Inspector
    model := ""
    gui := ""
    ddlScope := ""
    edtHistory := ""    ; chat transcript
    edtInput := ""      ; user-typed question
    btnSend := ""
    btnRefresh := ""
    btnClear := ""
    history := []       ; Array of {role, content} — user+assistant turns only
    contextText := ""   ; cached context user-turn

    __New(inspector, model)
    {
        this.inspector := inspector
        this.model := model
        this._Build()
    }

    _Build()
    {
        this.gui := Gui("+Resize +AlwaysOnTop", "Ask AI — UIA Inspector")
        this.gui.SetFont("s9", "Segoe UI")

        this.gui.AddText("xm ym", "Scope:")
        this.ddlScope := this.gui.AddDropDownList("x+6 yp-3 w180 Choose1",
            ["Ancestors + siblings", "Ancestors only", "Full captured tree"])
        this.btnRefresh := this.gui.AddButton("x+8 yp w110 h22", "Refresh context")
        this.btnRefresh.OnEvent("Click", (*) => this.RefreshContext())
        this.btnClear := this.gui.AddButton("x+6 yp w110 h22", "Clear chat")
        this.btnClear.OnEvent("Click", (*) => this.ClearChat())

        this.gui.AddText("xm y+10", "Conversation:")
        this.edtHistory := this.gui.AddEdit("xm y+2 w700 h380 ReadOnly +VScroll")

        this.gui.AddText("xm y+8", "Your question:")
        this.edtInput := this.gui.AddEdit("xm y+2 w700 h70 +Wrap +WantReturn")
        this.btnSend := this.gui.AddButton("xm y+6 w80 h26 Default", "Send")
        this.btnSend.OnEvent("Click", (*) => this._Send())
        this.gui.AddButton("x+6 yp w80 h26", "Close").OnEvent("Click", (*) => this.Hide())

        this.gui.OnEvent("Close", (*) => this.Hide())
        this.gui.OnEvent("Escape", (*) => this.Hide())
    }

    Show()
    {
        if this.contextText = ""
            this.RefreshContext()
        this.gui.Show()
        this.edtInput.Focus()
    }

    Hide()
    {
        this.gui.Hide()
    }

    ClearChat()
    {
        this.history := []
        this.edtHistory.Value := ""
    }

    ; Pull latest context from the inspector based on the chosen scope.
    RefreshContext()
    {
        scope := this._CurrentScope()
        summary := AIContext.BuildElementSummary(this.inspector)
        ancPath := AIContext.BuildAncestorPath(this.inspector)
        tree    := AIContext.BuildTreeSnippet(this.inspector, scope)
        this.contextText := summary
            . "`n`n=== AUTHORITATIVE ANCESTOR PATH (root -> selected) ===`n" ancPath
            . "`n`n" tree
    }

    _CurrentScope()
    {
        switch this.ddlScope.Value {
            case 2: return "ancestors"
            case 3: return "full"
            default: return "ancestors+siblings"
        }
    }

    _Send()
    {
        userMsg := Trim(this.edtInput.Value, " `t`r`n")
        if userMsg = ""
            return

        ; Refresh context if the user hasn't done it yet this session.
        if this.contextText = ""
            this.RefreshContext()

        this._Append("You", userMsg)
        this.edtInput.Value := ""
        this.history.Push({role: "user", content: userMsg})

        ; Build messages array
        systemPrompt :=
          "You are an AHK v2 UIA expert embedded inside the UIA Inspector, targeting the Descolada UIA-v2 library (S:\lib\v2\UIA2\UIA\UIA.ahk).`n"
        . "You receive authoritative context: the selected element's properties, its window info, the available UIA patterns, and a slice of the UIA tree. Use that data as ground truth.`n`n"
        . "When producing code, follow these API rules EXACTLY:`n"
        . "  - Use FindFirst(condition [, matchMode, scope])  and  FindAll(condition [, matchMode, scope])[index].`n"
        . "  - Do NOT use FindElement / FindElements / TreeWalker.`n"
        . "  - Conditions are object literals with UIA property names in CamelCase: {Type:'Button', Name:'OK', AutomationId:'...', ClassName:'...'}.`n"
        . "  - Valid Type values are UIA control types (Button, Edit, Pane, Group, Text, ListItem, TreeItem, Document, Image, Hyperlink, Window, MenuItem, Tab, TabItem, Custom, etc.) — NOT ARIA role names like RootWebArea, landmark, generic.`n"
        . "  - scope  : omit for default Descendants, or pass UIA.TreeScope.Children / UIA.TreeScope.Subtree / UIA.TreeScope.Element.`n"
        . "  - Assume winEl := UIA.ElementFromHandle(hwnd) is already available.`n"
        . "  - Prefer AutomationId > stable ancestor-then-chain > FindAll(...)[index].`n"
        . "Keep answers focused and technical. No markdown fences around code."

        messages := [
            {role: "system", content: systemPrompt},
            {role: "user",   content: "UI CONTEXT (automatically provided by inspector — not typed by the user):`n`n" this.contextText}
        ]
        for turn in this.history
            messages.Push({role: turn.role, content: turn.content})

        this.btnSend.Enabled := false
        this.btnSend.Text := "Thinking…"
        this._Append("AI", "(thinking…)")
        ; Let the GUI paint the "(thinking…)" placeholder before the blocking HTTP call
        Sleep(1)
        try {
            reply := CallOpenRouter(this.model, messages)
            ; Replace the placeholder line with the real response
            this._ReplaceLastPlaceholder(reply)
            this.history.Push({role: "assistant", content: reply})
        } catch Error as err {
            this._ReplaceLastPlaceholder("Error: " err.Message)
        }
        this.btnSend.Enabled := true
        this.btnSend.Text := "Send"
        this.edtInput.Focus()
    }

    ; Swap the trailing "(thinking…)" line we wrote as a placeholder with the
    ; real response, preserving scroll position.
    _ReplaceLastPlaceholder(newText)
    {
        current := this.edtHistory.Value
        placeholder := "(thinking…)"
        idx := InStr(current, placeholder, , -1)
        if idx
            this.edtHistory.Value := SubStr(current, 1, idx - 1) newText
        else
            this._Append("AI", newText)
        try {
            EM_SETSEL := 0xB1, WM_VSCROLL := 0x115, SB_BOTTOM := 7
            SendMessage(EM_SETSEL, -1, -1, this.edtHistory.Hwnd)
            SendMessage(WM_VSCROLL, SB_BOTTOM, 0, this.edtHistory.Hwnd)
        }
    }

    _Append(who, text)
    {
        sep := this.edtHistory.Value = "" ? "" : "`r`n`r`n"
        this.edtHistory.Value := this.edtHistory.Value sep "[" who "]`r`n" text
        ; Scroll to bottom
        try {
            EM_SETSEL := 0xB1, WM_VSCROLL := 0x115, SB_BOTTOM := 7
            SendMessage(EM_SETSEL, -1, -1, this.edtHistory.Hwnd)
            SendMessage(WM_VSCROLL, SB_BOTTOM, 0, this.edtHistory.Hwnd)
        }
    }
}

; ══════════════════════════════════════════════════
;  Shared OpenRouter caller — used by both the Ask AI
;  chat and the Find Unique one-shot.
;  Returns the assistant's text content. Throws on any
;  error (HTTP / JSON / missing key).
; ══════════════════════════════════════════════════
CallOpenRouter(model, messages)
{
    ; Authenticate from the inspector's own settings.ini — [OpenRouter] api_key.
    if !OpenRouter.authorized
    {
        apiKey := IniRead(A_ScriptDir "\settings.ini", "OpenRouter", "api_key", "")
        if apiKey = ""
            throw Error("No OpenRouter API key configured.`n`nOpen Preferences and paste your key into the 'OpenRouter API Key' field.")
        OpenRouter.Authenticate(apiKey)
    }

    ; Cap max_tokens so OpenRouter doesn't reserve a huge budget against the key's
    ; per-request credit limit (default models advertise 200k+ output, which blows
    ; the budget even when the actual reply will be short).
    maxTokens := IniRead(A_ScriptDir "\settings.ini", "AI", "MaxTokens", 2048) + 0
    if maxTokens <= 0
        maxTokens := 2048

    body := {model: model, messages: messages, max_tokens: maxTokens}
    response := OpenRouter.Chat.Completions(body)

    if !response.HasProp("choices")
    {
        msg := "OpenRouter returned no choices."
        if response.HasProp("error") {
            try msg .= "`n" response.error["message"]
        }
        if response.HasProp("ResponseText")
            msg .= "`n`nRaw:`n" SubStr(response.ResponseText, 1, 400)
        throw Error(msg)
    }

    choice := response.choices[1]
    if IsObject(choice) && choice.HasProp("message") && choice.message.HasProp("content")
        return choice.message.content
    ; cJSON may give Maps
    try return choice["message"]["content"]
    throw Error("Could not extract message content from response.")
}
