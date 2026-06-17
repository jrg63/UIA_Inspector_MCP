#Requires AutoHotkey v2.0.2+
#SingleInstance Force
DetectHiddenWindows true

/**
 * =========================================================================== *
 * Want a clear path for learning AutoHotkey?                                  *
 * Take a look at our AutoHotkey courses here: the-Automator.com/Discover      *
 * They're structured in a way to make learning AHK EASY                       *
 * And come with a 200% moneyback guarantee so you have NOTHING to risk!       *
 * =========================================================================== *
 * @author      the-Automator                                                  *
 * @version     2.5.0                                                          *
 * @copyright   Copyright (c) 2026 the-Automator                               *
 * @link        https://the-Automator.com/UIA?src=app                 *
 * @created     2026-03-28                                                     *
 * @modified    2026-04-14                                                     *
 * @description Standalone UI Automation element inspector with macro recorder *
 * =========================================================================== *
 * @license     CC BY 4.0                                                      *
 * =========================================================================== *
   This work by the-Automator.com is licensed under CC BY 4.0

   Attribution - You must give appropriate credit , provide a link to the license,
   and indicate if changes were made.

   You may do so in any reasonable manner, but not in any way that suggests the licensor
   endorses you or your use.

   No additional restrictions - You may not apply legal terms or technological measures that
   legally restrict others from doing anything the license permits.
 */

;@Ahk2Exe-SetVersion     2.5.0
;@Ahk2Exe-SetMainIcon    res\UIA.ico
;@Ahk2Exe-SetProductName UIA Inspector
;@Ahk2Exe-SetDescription Standalone UI Automation element inspector with macro recorder

; ══════════════════════════════════════════════════════════════════
; UIA_Inspector.ahk — Standalone UI Automation element inspector
; No dependencies beyond UIA.ahk. No AI, no Triggers, no extras.
; Hotkey: F1 to capture element under mouse (configurable below)
; ══════════════════════════════════════════════════════════════════

#include <GetSpecialFolders>
#Include <UIA>
global UIA_INCLUDE_SOURCE := _ahklib "\UIA.ahk"  ; keep in sync with the #Include above — used when emitting generated scripts
UIAI_LibPath := _ahklib "\UIA_Inspector" ; used by UIA.ahk to resolve its own #Includes

; #Include <UIA>  ; put uia into the lib folder and enable this line
#Include <UIA_Inspector\Scintilla\scintilla>
#Include <UIA_Inspector\Triggers>
#Include <UIA_Inspector\WinTitleColor>
#Include <UIA_Inspector\ScriptObject>
#Include <UIA_Inspector\cjson>
#Include <UIA_Inspector\NotifyV2>
#Include <UIA_Inspector\OpenRouter>
#Include <UIA_Inspector\AIContext>
#Include <UIA_Inspector\AskAIChat>

; ── Script Object ───────────────────────────────
script := {
    base         : ScriptObj(),
    name         : "UIA Inspector",
    hwnd         : '',
    author       : "the-Automator",
    email        : "joe@the-automator.com",
    crtdate      : "2026-03-28",
    moddate      : "2026-04-14",
    resfolder    : A_ScriptDir "\res",
    iconfile     : A_ScriptDir '\res\main.ico',
    config       : A_ScriptDir "\UIA_Inspector_settings.ini",
    homepagetext : "UIA Inspector",
    homepagelink : "the-Automator.com/UIA?src=app",
    VideoLink    : "",
    DevPath      : "S:\lib\v2\UIA2\UIA_Inspector.ahk",
    donateLink   : "",
}
TraySetIcon UIAI_LibPath "\UIA.ico"
(Scintilla) ; Init Scintilla class (uses UIAI_LibPath for DLL paths when set)

; ── Triggers + Preferences ──────────────────────
triggers.AddHotkey(CaptureHotkeyFired, "Capture Element", "F1")
triggers.AddHotkey(TrackHotkeyFired,   "Toggle Tracking", "F2")
PrefUI.Build()
triggers.FinishMenu("Preferences")
PrefUI.HookSave()
global APP_SETTINGS := PrefUI.Load()
if !FileExist(triggers.ini)
    triggers.Show()
triggers.tray.Add("Mouse Tips", _ToggleTipsMenu, 'p3')
triggers.tray.Add()
triggers.tray.Add('About', (*) => script.About())
triggers.tray.AddStandard()

; ── Launch ──────────────────────────────────────
UIA_Inspector()

/**
 * F1 hotkey handler — capture the element under the mouse and populate the inspector.
 * Defined as a free function (not a method) so triggers.AddHotkey can take its name
 * for the user-facing rebind UI.
 */
CaptureHotkeyFired(*) {
    if IsSet(_inspector) && _inspector
        _inspector.CaptureFromMouse()
}

/**
 * F2 hotkey handler — toggle continuous mouse-follow tracking on/off.
 * Free function for the same reason as CaptureHotkeyFired.
 */
TrackHotkeyFired(*) {
    if IsSet(_inspector) && _inspector
        _inspector.ToggleTracking()
}

/** Tray-menu handler bound to "Mouse Tips" — flips the tips-disabled flag. */
_ToggleTipsMenu(*) {
    if IsSet(_inspector) && _inspector
        _inspector._ToggleTips()
}

; ════════════════════════════════════════════════════════
;  Inspector Class
; ════════════════════════════════════════════════════════
/**
 * UIA Inspector main class. Builds the inspector window and owns all interaction state.
 *
 * Roughly grouped responsibilities (see section comments throughout the file):
 *   • Capture        — read the element under the mouse + cached property bundle.
 *   • Populate       — render the captured data into 4 panels: Window Info, Properties,
 *                      Anchor Points, Patterns.
 *   • Tree           — recursive UIA tree view, with filter and Deep/Fast scan modes.
 *   • Highlight      — colored on-screen overlay around the captured element.
 *   • Macro Builder  — append "FindFirst(...).Action()" steps into a Scintilla editor;
 *                      copy / test / undo / save the generated AHK script.
 *   • Anchor Vars    — name an ancestor element so a macro can scope its searches to it.
 *   • Guide Mode     — a blue overlay walks new users through Capture → Add → Test.
 *   • Mouse Monitor  — status-bar polling for elevation/bitness of the window under cursor.
 *   • Tooltips       — context-sensitive hover hints on every control.
 *   • Tracking       — F2 toggles a 100ms timer that re-captures on mouse move.
 *
 * A single instance is exposed via the `_inspector` global so free functions
 * (hotkey handlers, tray callbacks) can route into it.
 */
class UIA_Inspector {
    ; Current state
    capturedElement := ""              ; the element we captured
    capturedWindowEl := ""             ; root element of captured window
    capturedHwnd := 0                  ; HWND of the captured window
    treeViewMap := Map()               ; TV item ID => Element
    capturing := false                 ; true while highlight loop is running
    highlightGui := ""                 ; highlight overlay GUI

    ; Guide mode — walks the user through the workflow with a blue highlight
    guideMode          := false
    _guideHighlightGui  := ""           ; primary overlay
    _guideHighlightGui2 := ""           ; secondary overlay (used when two controls are highlighted)
    _guideHideTimer    := ""            ; bound auto-hide callback
    _lastMatchCount   := -1            ; cached uniqueness probe from UpdateStatusBar
    _keyLegendGui   := ""              ; floating key legend panel
    _legendTimerFn  := ""              ; bound hide callback for legend timeout

    ; Tracking state
    tracking := false                  ; true while tracking mouse
    trackTimer := ""                   ; timer callback for tracking
    lastTrackRect := ""                ; avoid redundant updates

    ; Mouse monitor state (for status bar updates)
    _monitorTimer := ""
    _lastMonitorPid := 0
    _lastAdminPromptPid := 0

    ; Anchor variables — user-created named anchors for macro chaining
    anchorVars := Map()                ; name => {el, condition, label}
    _anchorVarCounter := 0             ; auto-increment for unique names
    _anchorDDLMap := Map()             ; DDL index => varName

    ; Pattern invoker — map of TV item => {pattern, kind} for double-click actions
    patternActionMap := Map()

    ; Mouse-over tip state
    lastTipHwnd      := 0              ; HWND of control whose tip is currently showing
    dismissedTipHwnd := 0              ; HWND whose tip was auto-hidden (don't re-show until cursor leaves)
    _tipHideFn       := ""             ; bound _hideTip callback (set in __New)
    _tooltipBound    := ""             ; bound _checkTooltip callback (set in __New)
    tipsDisabled     := 0              ; reserved for future "Disable Tips" toggle
    tipMap           := ""             ; Map() built on first hover (lazy init)

    /**
     * Build the inspector GUI and wire every event handler / hotkey / monitor.
     *
     * Layout, top to bottom:
     *   Row 1 — four side-by-side panels: Window Info | Properties | Anchor Points | Patterns
     *   Row 2 — Deep Scan checkbox, element count, filter box, "Path matches" indicator, Clear button
     *   Row 3 — main UIA tree TreeView (the big one)
     *   Row 4 — Macro builder controls: Anchor / Scope / Match / Action DDLs + "Add element"
     *   Row 5 — Scintilla code editor (the generated AHK macro)
     *   Row 6 — Test / Copy / Clear macro buttons
     *   Row 7 — Status bar with 4 parts: hint • elevation • bitness • inspector mode
     *
     * Side effects: stashes itself in the `_inspector` global, registers F1/F2 hotkeys
     * via the Triggers library, hooks OnExit/OnError, and starts the mouse monitor timer.
     */
    __New() {
        ; ── Build the GUI ───────────────────────
        global _inspector := this
        this.gui := Gui("-Resize" (APP_SETTINGS.alwaysOnTop ? " +AlwaysOnTop" : " -AlwaysOnTop"), this._BuildWindowTitle())
        this.gui.Opt('+DPIScale')
        this.gui.SetFont("s9", "Segoe UI")
        this.gui.OnEvent("Close", (*) => this.Exit())
        triggers.SetOwner(this.gui)
        triggers.ui.Opt((APP_SETTINGS.alwaysOnTop ? "+AlwaysOnTop" : "-AlwaysOnTop"))

        ; ── Info panels row ───────────────────
        this.gui.SetFont("s8", "Arial Narrow")

        ; Column 1: Window Info
        this.gui.SetFont("s8 bold")
        this.gui.AddText("xm y2 w180 Section", "Window Info")
        this.gui.SetFont("s8 norm")
        this.lvWin := this.gui.AddListView("xm y+2 w180 h140 -Hdr +LV0x4000 ReadOnly", ["Property", "Value"])
        this.lvWin.ModifyCol(1, 55)
        this.lvWin.ModifyCol(2, 115)
        for label in ["Title", "Class", "HWND", "PID", "Size"]
            this.lvWin.Add(, label, "")
        this.lvWin.OnEvent("Click", (lv, item) => this.LVCopyText(lv, item))
        this.lvWin.OnEvent("ContextMenu", (lv, item, *) => this.LVCopyText(lv, item))

        ; Column 2: Properties
        this.gui.SetFont("s8 bold")
        this.gui.AddText("x200 ys", "Properties")
        this.gui.SetFont("s8 norm")
        this.chkShowAllProps := this.gui.AddCheckbox("x+4 yp", "Show &All")
        this.chkShowAllProps.Value := APP_SETTINGS.showAllProps
        this.chkShowAllProps.OnEvent("Click", (*) => (
            IniWrite(this.chkShowAllProps.Value, A_ScriptDir "\UIA_Inspector_settings.ini", "Settings", "ShowAllProps"),
            this.PopulateProperties(this.capturedElement)))
        this.lvProps := this.gui.AddListView("x200 y+2 w210 h140 -Hdr +LV0x4000 ReadOnly", ["Property", "Value"])
        this.lvProps.ModifyCol(1, 85)
        this.lvProps.ModifyCol(2, 115)
        this.lvProps.OnEvent("ContextMenu", (lv, item, *) => this.LVCopyText(lv, item))
        this.lvProps.OnEvent("Click", (lv, item) => this.LVCopyText(lv, item))

        ; Column 3: Anchor Points
        this.gui.SetFont("s8 bold")
        this.gui.AddText("x420 ys", "Anchor Points")
        this.gui.SetFont("s8 norm")
        this.btnRefreshAnchors := this.gui.AddButton("x+4 yp-2 w55 h18", "Refresh")
        this.btnRefreshAnchors.OnEvent("Click", (*) => this.PopulateAnchorPoints())
        this.tvAnchors := this.gui.AddTreeView("x420 y+2 w230 h140 +HScroll ReadOnly")
        this.tvAnchors.OnEvent("Click", (tvCtrl, item) => this._OnAnchorClick(item))
        this.tvAnchors.OnEvent("ContextMenu", (tvCtrl, item, *) => this._OnAnchorContextMenu(item))
        this.parentStructureMap := Map()

        ; Column 4: Patterns
        this.gui.SetFont("s8 bold")
        this.gui.AddText("x660 ys", "Patterns")
        this.gui.SetFont("s8 norm")
        this.btnKeys := this.gui.AddButton("x780 yp-2 w60 h18", "Hotkeys")
        this.btnKeys.OnEvent("Click", (*) => this._ToggleKeyLegend())
        this.tvPatterns := this.gui.AddTreeView("x660 y+2 w180 h140 ReadOnly")
        this.tvPatterns.OnEvent("DoubleClick", (tv, item) => this._OnPatternInvoke(item))
        this.tvPatterns.OnEvent("Click", (tv, item) => this._CopyPatternMethod(item))

        ; Reset font for rest of GUI
        this.gui.SetFont("s9", "Segoe UI")

        ; ── Inspect row (above main tree, single row, no group box) ──
        this.chkDeepScan := this.gui.AddCheckbox("xm y+m-5 h32 ", "&Deep`nScan")
        this.chkDeepScan.Value := APP_SETTINGS.deepScan
        this.editElemCount := this.gui.AddEdit("x+5 yp+7 w95 h21 ReadOnly Center", "Elements: 0")
        ; this.btnTrack := this.gui.AddButton("x+m-15 h22", "⌖ Track (" triggers.gettrigger(TrackHotkeyFired) ")")
        ; this.btnTrack.OnEvent("Click", (*) => this.ToggleTracking())
        this.editFilter := this.gui.AddEdit("x+10 yp w140 h21")
        DllCall("User32.dll\SendMessageW", "Ptr", this.editFilter.Hwnd, "UInt", 0x1501, "Int", 1, "WStr", "Filter tree...")
        this._filterTimerFn := ObjBindMethod(this, "FilterTree")
        this.editFilter.OnEvent("Change", (*) => SetTimer(this._filterTimerFn, this.editFilter.Value = "" ? -1 : -300))
        this.gui.AddText("x+m yp h22 w90 right +0x200", "Path matches:")
        this.editTarget := this.gui.AddEdit("x+2 yp-4 w160 h21 ReadOnly", "-")
        this.btnFindUnique := this.gui.AddButton("x+4 yp w75 h21 Disabled", "Find Unique")
        this.btnFindUnique.OnEvent("Click", (*) => this.OnFindUnique())
        this.btnAskAI := this.gui.AddButton("x+4 yp w55 h21 Disabled", "Ask AI")
        this.btnAskAI.OnEvent("Click", (*) => this.OnAskAI())
        this._askAIChat := ""     ; lazy-created AskAIChat instance
        this._aiModel := IniRead(A_ScriptDir "\UIA_Inspector_settings.ini", "AI", "Model", "deepseek-v4-flash")
        this.btnClearInspector := this.gui.AddButton("x+4 yp w95 h21", "Clear Inspector")
        this.btnClearInspector.OnEvent("Click", (*) => this.ClearInspector())

        ; ── UIA Tree ──────────────────────────
        this.tvUIA := this.gui.AddTreeView("xm y+8 w830 h280 +HScroll")
        this.tvUIA.OnEvent("Click", (tv, item) => this.OnTreeClick(item))
        this.tvUIA.OnEvent("ContextMenu", (tv, item, *) => this.OnTreeContext(item))

        ; ── Macro row (below tree, single row, no group box) ──
        this.gui.AddText("xm y+10 w50 h22 +0x200", "Anchor:")
        this.ddlAnchor := this.gui.AddDropDownList("x+2 yp w115", ["(none)"])
        this.ddlAnchor.Choose(1)
        this.ddlAnchor.OnEvent("ContextMenu", (*) => this._ShowAnchorManager())
        this.gui.AddText("x+8 yp w45 h22 +0x200", "Scope:")
        this.ddlScope := this.gui.AddDropDownList("x+2 yp w110", ["Descendants", "Children", "Subtree", "Element", "Family", "ElementDescendants"])
        this.ddlScope.Choose(1)
        this.gui.AddText("x+8 yp w45 h22 +0x200", "Match:")
        this.ddlMatchMode := this.gui.AddDropDownList("x+2 yp w85", ["Exact", "Contains", "StartsWith", "EndsWith"])
        this.ddlMatchMode.Choose(1)
        this.gui.AddText("x+8 yp w45 h22 +0x200", "Action:")
        this.ddlAction := this.gui.AddDropDownList("x+2 yp w95", ["Highlight", "Click", "MouseClick", "ControlClick", "SetValue", "Invoke", "Toggle", "Expand", "Collapse", "Select", "ScrollIntoView", "SetFocus", "WaitElement"])
        this.ddlAction.Choose(1)
        this.gui.AddText("x+8 yp w10 h22 +0x200", "#:")
        this.edtIndex := this.gui.AddEdit("x+2 yp w40 h22 +Number", "1")
        this.udIndex := this.gui.AddUpDown("Range1-1", 1)
        this.btnAddElement := this.gui.AddButton("x+8 yp w90 h22", "Add element")
        this.btnAddElement.OnEvent("Click", (*) => this.MacroAddElement())

        ; ── Scintilla editor ──────────────────
        this.sciCtl := this.gui.AddScintilla("xm y+8 w830 h180 DefaultOpt DefaultTheme")
        this.sciCtl.CaseSense := false
        load_AHKV2_KeyWords(&_kw1, &_kw2, &_kw3, &_kw4, &_kw5, &_kw6, &_kw7)
        this.sciCtl.setKeywords(_kw1, _kw2, _kw3, _kw4, _kw5, _kw6, _kw7)
        this.sciCtl.Brace.Chars := "[]{}()"
        this.sciCtl.SyntaxEscapeChar := "``"
        this.sciCtl.SyntaxCommentLine := ";"
        this.sciCtl.CustomSyntaxHighlighting := true
        this.sciCtl.AutoSizeNumberMargin := true
        this.sciCtl.Tab.Use := false
        this.sciCtl.Tab.Width := 4
        this._ApplyMacroTheme()

        ; Filtered Scintilla message handling
        OnMessage(0x4E, this.sciCtl.msg_cb, 0)
        sciHwnd := this.sciCtl.hwnd
        origCb := ObjBindMethod(this.sciCtl, "wm_messages")
        this._sciFilteredCb := _SciFilteredWmNotify.Bind(sciHwnd, origCb)
        OnMessage(0x4E, this._sciFilteredCb)


        ; ── Macro action buttons (right-aligned row just above the status bar) ──
        this.btnTestMacro := this.gui.AddButton("x688 y+6 w48 h22", "Test")
        this.btnTestMacro.OnEvent("Click", (*) => this.MacroTest())
        this.btnCopyMacro := this.gui.AddButton("x+2 yp w48 h22", "Copy")
        this.btnCopyMacro.OnEvent("Click", (*) => this.MacroCopy())
        this.btnClearMacro := this.gui.AddButton("x+2 yp w48 h22", "Clear")
        this.btnClearMacro.OnEvent("Click", (*) => (this.macroSteps := [], this.sciCtl.Text := "", this._lastMacroWinTitle := "", this._UpdateControls()))

        ; ── Bottom: Status Bar ──────────────────
        this.sbMain := this.gui.AddStatusBar('-theme')
        this.sbMain.SetParts(560, 100, 70)
        this.sbMain.SetText(this._BuildHotkeyHint())
        this.sbMain.SetText("-", 2)
        this.sbMain.SetText("-", 3)
        this.sbMain.SetText(A_IsAdmin ? "Inspector: Admin" : "Inspector: User", 4)

        ; Disable controls that need state before they're usable
        this._UpdateControls()

        ; ── Register hotkeys ────────────────────
        HotIf()  ; clear any stale HotIf context left by triggers/PrefUI
        HotIfWinActive("ahk_id " this.gui.hwnd)
        Hotkey("NumpadAdd", ObjBindMethod(this, "NavigateElement", "child"))
        Hotkey("NumpadSub", ObjBindMethod(this, "NavigateElement", "parent"))
        Hotkey("^i", ObjBindMethod(this, "JumpToNearestAutomationId"))
        Hotkey("^z", ObjBindMethod(this, "MacroRemoveLast"))
        HotIfWinActive

        ; ── Cleanup handlers ─────────────────────
        OnExit(ObjBindMethod(this, "_OnExit"))
        OnError(ObjBindMethod(this, "_OnError"))

        ; ── Show ────────────────────────────────
        _showOpt := "w860"
        if APP_SETTINGS.rememberPos && APP_SETTINGS.winX != "" && APP_SETTINGS.winY != ""
            _showOpt := "x" APP_SETTINGS.winX " y" APP_SETTINGS.winY " w860"
        this.gui.Show(_showOpt)
        if A_IsAdmin
            SetCaptionColor(this.gui.Hwnd, 0x000000FF)  ; red title bar when running as admin

        ; Render the guide highlight now that the window has a real screen position.
        SetTimer(ObjBindMethod(this, "_UpdateGuide"), -50)

        ; ── Mouse-over tips ──────────────────────
        ; Notify defaults — applied once so per-call Show() stays terse.
        ; the-Automator.com brand palette: background #FFD23E, text #107C10.
        Notify.Default.HDText      := ""                ; per-tip header set in Show()
        Notify.Default.HDFont      := "Arial Black"     ; bold-by-design font (Notify can't toggle bold)
        Notify.Default.HDFontSize  := 14
        Notify.Default.HDFontColor := "black"        ; very dark green — contrasts the body
        Notify.Default.BDFont      := "Tahoma"
        Notify.Default.BDFontSize  := 12
        Notify.Default.BDFontColor := "black"        ; the-Automator.com highlight green
        Notify.Default.GenBGColor  := "0xFFD23E"        ; the-Automator.com base yellow
        Notify.Default.GenIcon     := ""                ; no icon
        Notify.Default.GenDuration := 3
        Notify.Default.GenLoc      := "Mouse"
        this._tipHideFn     := ObjBindMethod(this, "_hideTip")
        this._tooltipBound  := ObjBindMethod(this, "_checkTooltip")
        this._legendTimerFn := ObjBindMethod(this, "_hideLegend")
        OnMessage(0x200,  this._tooltipBound)
        ; WM_ENTERSIZEMOVE — hide legend the instant the main window is dragged
        _guiHwnd := this.gui.Hwnd
        _hideLegendFn := ObjBindMethod(this, "_hideLegend")
        OnMessage(0x0231, (wp, lp, msg, hwnd) => (hwnd = _guiHwnd ? _hideLegendFn() : ""))
        this.tipsDisabled := APP_SETTINGS.tipsDisabled
        if !this.tipsDisabled
            A_TrayMenu.Check("Mouse Tips")

        this.guideMode := APP_SETTINGS.guideMode

        ; ── Start mouse monitor for status bar ──
        this._monitorTimer := ObjBindMethod(this, "_MonitorMouseWindow")
        SetTimer(this._monitorTimer, 500)
    }

    /**
     * Resolve the absolute path to UIA.ahk for use in generated `#Include` lines.
     * Looks for `<inspector dir>\..\UIA\UIA.ahk` (matching the layout the inspector
     * itself uses at #Include time) and canonicalizes it via GetFullPathName so the
     * generated script has a clean absolute path with no `..` segments.
     *
     * Cached on first call so we don't re-hit the filesystem for every macro step.
     * Falls back to bare `UIA.ahk` (relying on the user's AHK Lib folder) if the
     * sibling-folder layout isn't present — happens when someone ships only the
     * compiled .exe without the source UIA.ahk alongside it.
     */
    _UIAIncludePath() {
        if this.HasOwnProp("_uiaIncludePathCache")
            return this._uiaIncludePathCache
        candidate := UIA_INCLUDE_SOURCE
        buf := Buffer(2048, 0)
        if DllCall("GetFullPathNameW", "wstr", candidate, "uint", 1024, "ptr", buf, "ptr", 0)
        {
            resolved := StrGet(buf, "UTF-16")
            if FileExist(resolved)
                return this._uiaIncludePathCache := resolved
        }
        if FileExist(candidate)
            return this._uiaIncludePathCache := candidate
        return this._uiaIncludePathCache := "UIA.ahk"
    }

    /**
     * Build the cache request used for window-wide UIA tree fetches.
     * Pre-loads ~22 element properties (Type, Name, ClassName, AutomationId, …) plus
     * ~13 Is*PatternAvailable flags so the tree walker doesn't pay a COM round-trip
     * per property per node. Used by CaptureFromMouse and SyncTree.
     * @returns A configured UIA.CacheRequest with TreeScope := Subtree.
     */
    _MakeCacheRequest() {
        cr := UIA.CreateCacheRequest()
        cr.TreeScope := UIA_TreeScope.Subtree
        ; Element properties (Type, Name, ClassName, AutomationId, ...)
        for propId in [30002, 30003, 30004, 30005, 30006, 30007, 30009,
                       30010, 30011, 30012, 30013, 30016, 30017, 30019,
                       30020, 30021, 30022, 30023, 30024, 30025, 30026,
                       30001]
            cr.AddProperty(propId)
        ; Pattern-availability checks (IsInvokePatternAvailable, ...)
        for propId in [30027, 30028, 30031, 30033, 30034, 30036, 30037,
                       30040, 30041, 30042, 30043, 30044, 30090]
            cr.AddProperty(propId)
        return cr
    }

    ; ════════════════════════════════════════════
    ;  Capture — grab element under the mouse
    ; ════════════════════════════════════════════
    /**
     * Snapshot the UI element under the cursor and populate every panel.
     *
     * Workflow:
     *   1. Read mouse position + window under it (skip self).
     *   2. Inspect the target process for elevation/bitness — if elevated and we're not
     *      admin, prompt to relaunch as admin (UIA can't peek into elevated windows).
     *   3. Nudge Chromium accessibility on if applicable.
     *   4. Build cached window root + live ElementFromPoint.
     *   5. Refill Window Info / Properties / Patterns / Anchor Points / Tree panels.
     *   6. Draw highlight overlay and update status bar.
     *
     * Wrapped in Critical("On") and gui.Opt("+Disabled") to prevent the user from
     * interacting mid-capture (the COM calls can take 100s of ms on heavy UIs).
     */
    CaptureFromMouse(*) {
        Critical("On")
        ; Stop any previous highlight
        this.StopCapture()

        ; Get mouse position
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mX, &mY, &winUnderMouse)

        if !winUnderMouse {
            this.sbMain.SetText("  No window found under cursor")
            return
        }

        ; Don't inspect ourselves
        if winUnderMouse = this.gui.Hwnd
            return

        ; Check elevation before attempting UIA access
        targetPid := WinGetPID("ahk_id " winUnderMouse)
        if IsBrowserProcess(targetPid)
        {
            this.sbMain.SetText("Browser", 2)
            this.sbMain.Opt("BackgroundDefault")
        }
        else if IsProcessElevated(targetPid)
        {
            this.sbMain.SetText("Admin", 2)
            this.sbMain.Opt("BackgroundRed")
            if !A_IsAdmin
            {
                this.gui.Opt("+OwnDialogs")
                targetName := ProcessGetName(targetPid)
                choice := MsgBox(
                    targetName " is running as Admin.`n"
                    "UIA can't inspect elevated windows without Admin rights.`n`n"
                    "Restart Inspector as Admin?",
                    "Target is Elevated", "Y/N Icon!")
                if choice = "Yes"
                {
                    Run("*RunAs " A_ScriptFullPath)
                    ExitApp()
                }
                return
            }
        }
        else
        {
            this.sbMain.SetText("Normal", 2)
            this.sbMain.Opt("BackgroundDefault")
        }
        try
        {
            targetPath := ProcessGetPath(targetPid)
            this.sbMain.SetText(CheckExeBitness(targetPath), 3)
        }
        catch
            this.sbMain.SetText("?", 3)

        this.sbMain.SetText("  Capturing...")
        this._DisableScintilla()
        this.gui.Opt("+Disabled") ; prevent interaction during capture

        try {
            ; Activate Chromium accessibility if needed
            try UIA.ActivateChromiumAccessibility(winUnderMouse)

            ; Build a cache request for the properties we want to display
            cr := this._MakeCacheRequest()

            ; Get the full window tree (cached)
            this.capturedHwnd := winUnderMouse
            this.capturedWindowEl := UIA.ElementFromHandle(winUnderMouse, cr)

            ; Get the specific element at the mouse position
            this.capturedElement := UIA.ElementFromPoint(mX, mY)

            ; Populate the GUI
            this.PopulateWindowInfo(winUnderMouse)
            this.PopulateProperties(this.capturedElement)
            this.PopulatePatterns(this.capturedElement)
            this.BuildTree()

            ; Populate anchor points panel
            this.PopulateAnchorPoints()

            ; Show highlight on captured element
            this.StartHighlight()

            ; Update index range based on match count
            this._UpdateIndexRange()

            ; Update status bar with element info
            this.UpdateStatusBar()

        } catch as err {
            errMsg := err.Message
            if err.HasProp("Stack")
                errMsg .= " | " err.Stack
            this.sbMain.SetText("  Error: " errMsg)
        }

        this.gui.Opt("-Disabled")
        this._EnableScintilla()
        this._UpdateControls()
        ; Focus main tree so the selected node is highlighted (blue) instead of greyed out
        try
        {
            WinActivate("ahk_id " this.gui.Hwnd)
            this.tvUIA.Focus()
        }
        Critical("Off")
    }

    ; ════════════════════════════════════════════
    ;  Window Info — top ListView
    ; ════════════════════════════════════════════
    /**
     * Fill the top-left ListView with the captured window's Title / Class / HWND / PID / Size.
     * Each property is wrapped in try{} — many WinGet* calls fail on elevated or just-closed
     * windows; we'd rather show partial info than throw.
     */
    PopulateWindowInfo(hwnd) {
        title := "", class := "", pid := 0
        try title := WinGetTitle(hwnd)
        try class := WinGetClass(hwnd)
        try pid := WinGetPID(hwnd)

        ; Get window rect
        rect := ""
        try {
            WinGetPos(&wx, &wy, &ww, &wh, hwnd)
            rect := wx "," wy " " ww "x" wh
        }

        this.lvWin.Modify(1,,, title)
        this.lvWin.Modify(2,,, class)
        this.lvWin.Modify(3,,, String(hwnd))
        this.lvWin.Modify(4,,, pid)
        this.lvWin.Modify(5,,, rect)
    }

    ; ════════════════════════════════════════════
    ;  Properties — middle ListView
    ; ════════════════════════════════════════════
    /**
     * Fill the Properties ListView from the captured element.
     * `propList` is the master display order; `important: true` rows show in the default
     * compact view, the rest only when "Show All" is checked. Each row's `fmt` field
     * controls how the raw VARIANT gets stringified (rect, bool, hwnd, type-name lookup).
     * After the static set, also tries to resolve a child HWND via _ResolveElementHwnd.
     */
    PopulateProperties(el) {
        this.lvProps.Delete()

        if !el
            return

        ; Properties to display in order (important: true = shown by default)
        static propList := [
            {name: "Type",              id: 30003, fmt: "type",  important: true},
            {name: "LocalizedType",     id: 30004, fmt: "str",   important: false},
            {name: "Name",              id: 30005, fmt: "str",   important: true},
            {name: "AutomationId",      id: 30011, fmt: "str",   important: true},
            {name: "ClassName",         id: 30012, fmt: "str",   important: true},
            {name: "FrameworkId",       id: 30024, fmt: "str",   important: false},
            {name: "BoundingRectangle", id: 30001, fmt: "rect",  important: false},
            {name: "IsEnabled",         id: 30010, fmt: "bool",  important: true},
            {name: "IsOffscreen",       id: 30022, fmt: "bool",  important: false},
            {name: "IsKeyboardFocusable", id: 30009, fmt: "bool", important: false},
            {name: "IsPassword",        id: 30019, fmt: "bool",  important: false},
            {name: "IsControlElement",  id: 30016, fmt: "bool",  important: false},
            {name: "IsContentElement",  id: 30017, fmt: "bool",  important: false},
            {name: "HelpText",          id: 30013, fmt: "str",   important: false},
            {name: "ItemType",          id: 30021, fmt: "str",   important: false},
            {name: "ItemStatus",        id: 30026, fmt: "str",   important: false},
            {name: "Orientation",       id: 30023, fmt: "int",   important: false},
            {name: "AccessKey",         id: 30007, fmt: "str",   important: false},
            {name: "AcceleratorKey",    id: 30006, fmt: "str",   important: false},
            {name: "ProcessId",         id: 30002, fmt: "int",   important: false},
            {name: "NativeWindowHandle", id: 30020, fmt: "hwnd", important: false}
        ]

        showAll := this.chkShowAllProps.Value

        for prop in propList {
            if !showAll && !prop.important
                continue
            val := ""
            try {
                raw := el.GetPropertyValue(prop.id)
                switch prop.fmt {
                    case "type":
                        typeName := UIA_Type.HasValue(raw)
                        val := typeName ? typeName " (" raw ")" : String(raw)
                    case "rect":
                        if IsObject(raw)
                            val := "l:" raw.l " t:" raw.t " r:" raw.r " b:" raw.b
                        else
                            val := String(raw)
                    case "bool":
                        val := raw ? "True" : "False"
                    case "hwnd":
                        val := raw ? Format("0x{:X}", raw) : "0"
                    case "int":
                        val := String(raw)
                    default: ; str
                        val := String(raw)
                }
            } catch {
                val := "(error)"
            }
            this.lvProps.Add(, prop.name, val)
        }

        ; HWND — 3-step fallback: NativeWindowHandle → WinId+DeepChild
        try
        {
            ctrlHwnd := this._ResolveElementHwnd(el)
            if ctrlHwnd
                this.lvProps.Add(, "HWND", Format("0x{:X}", ctrlHwnd))
        }
    }

    ; ════════════════════════════════════════════
    ;  Patterns — bottom TreeView
    ; ════════════════════════════════════════════
    /**
     * Fill the Patterns TreeView with every UIA pattern this element supports.
     * Probes via the Is*PatternAvailable property (cheap, no pattern instantiation).
     * Each supported pattern becomes a parent node; AddPatternDetails fills it with
     * state-aware children (e.g. "▶ Toggle()  — state: On").
     * Resets patternActionMap because TV item IDs change on every rebuild.
     */
    PopulatePatterns(el) {
        this.tvPatterns.Delete()
        this.patternActionMap := Map()  ; reset action lookup — TV item IDs change on rebuild

        if !el
            return

        ; Check each pattern by its availability property
        static patternChecks := [
            {name: "Invoke",           propId: 30031},
            {name: "ExpandCollapse",   propId: 30028},
            {name: "Toggle",           propId: 30041},
            {name: "Value",            propId: 30043},
            {name: "RangeValue",       propId: 30033},
            {name: "Scroll",           propId: 30034},
            {name: "SelectionItem",    propId: 30036},
            {name: "Selection",        propId: 30037},
            {name: "Text",             propId: 30040},
            {name: "Transform",        propId: 30042},
            {name: "Window",           propId: 30044},
            {name: "Dock",             propId: 30027},
            {name: "LegacyIAccessible", propId: 30090},
            {name: "ScrollItem",       propId: 30035}
        ]

        for check in patternChecks {
            try {
                if el.GetPropertyValue(check.propId) {
                    parentNode := this.tvPatterns.Add(check.name)
                    ; Add pattern-specific details
                    this.AddPatternDetails(el, check.name, parentNode)
                }
            }
        }
    }

    /**
     * Add a pattern's detail nodes under its parent in the Patterns TreeView.
     * Actionable leaves (▶ prefix) are registered in patternActionMap so a double-click
     * from _OnPatternInvoke fires the action on the captured element. Non-actionable
     * leaves are pure read-outs (Value contents, scroll percentages, etc.).
     */
    AddPatternDetails(el, patternName, parentNode) {
        try {
            pat := el.GetPattern(patternName)
            switch patternName {
                case "Invoke":
                    leaf := this.tvPatterns.Add("▶ Invoke()", parentNode)
                    this.patternActionMap[leaf] := {pattern: "Invoke", kind: "invoke"}
                case "Toggle":
                    state := pat.ToggleState
                    stateStr := state = 0 ? "Off" : (state = 1 ? "On" : "Indeterminate")
                    leaf := this.tvPatterns.Add("▶ Toggle()  — state: " stateStr, parentNode)
                    this.patternActionMap[leaf] := {pattern: "Toggle", kind: "toggle"}
                case "ExpandCollapse":
                    state := pat.ExpandCollapseState
                    stateStr := state = 0 ? "Collapsed" : (state = 1 ? "Expanded" : (state = 2 ? "PartiallyExpanded" : "LeafNode"))
                    leaf := this.tvPatterns.Add("▶ Expand / Collapse  — state: " stateStr, parentNode)
                    this.patternActionMap[leaf] := {pattern: "ExpandCollapse", kind: "expandCollapse"}
                case "Value":
                    val := ""
                    try val := pat.Value
                    readOnly := ""
                    try readOnly := pat.IsReadOnly ? " (ReadOnly)" : ""
                    this.tvPatterns.Add("Value: `"" val "`"" readOnly, parentNode)
                case "RangeValue":
                    val := "", min := "", max := ""
                    try val := pat.Value
                    try min := pat.Minimum
                    try max := pat.Maximum
                    this.tvPatterns.Add("Value: " val " (min:" min " max:" max ")", parentNode)
                case "SelectionItem":
                    sel := ""
                    try sel := pat.IsSelected ? "Selected" : "Not selected"
                    leaf := this.tvPatterns.Add("▶ Select()  — " sel, parentNode)
                    this.patternActionMap[leaf] := {pattern: "SelectionItem", kind: "select"}
                case "Window":
                    modal := ""
                    try modal := pat.IsModal ? "Modal" : "Not modal"
                    this.tvPatterns.Add(modal, parentNode)
                case "Scroll":
                    hPct := "", vPct := ""
                    try hPct := Round(pat.HorizontalScrollPercent, 1)
                    try vPct := Round(pat.VerticalScrollPercent, 1)
                    this.tvPatterns.Add("H:" hPct "% V:" vPct "%", parentNode)
                case "ScrollItem":
                    leaf := this.tvPatterns.Add("▶ ScrollIntoView()", parentNode)
                    this.patternActionMap[leaf] := {pattern: "ScrollItem", kind: "scrollIntoView"}
                case "LegacyIAccessible":
                    role := "", defAction := ""
                    try role := pat.Role
                    try defAction := pat.DefaultAction
                    if role
                        this.tvPatterns.Add("Role: " role, parentNode)
                    if defAction
                    {
                        leaf := this.tvPatterns.Add("▶ DoDefaultAction()  — " defAction, parentNode)
                        this.patternActionMap[leaf] := {pattern: "LegacyIAccessible", kind: "defaultAction"}
                    }
            }
        }
    }

    /**
     * Single-click handler for the Patterns TreeView — copies a `.GetPattern("X").Y()`
     * snippet to the clipboard so the user can paste it into their own scripts.
     * For non-action leaves, copies the leaf's display text instead.
     */
    _CopyPatternMethod(tvItem) {
        if !tvItem
            return
        if this.patternActionMap.Has(tvItem)
        {
            desc := this.patternActionMap[tvItem]
            method := ""
            switch desc.kind {
                case "invoke":         method := "Invoke()"
                case "toggle":         method := "Toggle()"
                case "expandCollapse": method := "Expand()"
                case "select":         method := "Select()"
                case "scrollIntoView": method := "ScrollIntoView()"
                case "defaultAction":  method := "DoDefaultAction()"
                default:               method := ""
            }
            snippet := method
                ? '.GetPattern("' desc.pattern '").' method
                : '.GetPattern("' desc.pattern '")'
            A_Clipboard := snippet
            this.sbMain.SetText("  Copied: " snippet)
            this._FlashCopyTip(snippet)
            return
        }
        ; Non-action leaf — copy its label text
        text := this.tvPatterns.GetText(tvItem)
        if text != ""
        {
            A_Clipboard := text
            this.sbMain.SetText("  Copied: " text)
            this._FlashCopyTip(text)
        }
    }

    /**
     * Double-click handler for the Patterns TreeView — actually fires the pattern action
     * (Invoke, Toggle, Expand/Collapse, Select, ScrollIntoView, DoDefaultAction) on the
     * captured element, then re-flashes the highlight and re-populates the patterns
     * panel after a short delay so state-reflecting labels update.
     * ExpandCollapse is special-cased to toggle based on current state.
     */
    _OnPatternInvoke(tvItem) {
        if !this.capturedElement || !this.patternActionMap.Has(tvItem)
            return
        desc := this.patternActionMap[tvItem]
        resultMsg := ""
        try {
            pat := this.capturedElement.GetPattern(desc.pattern)
            switch desc.kind {
                case "invoke":
                    pat.Invoke()
                    resultMsg := "Invoked"
                case "toggle":
                    pat.Toggle()
                    resultMsg := "Toggled"
                case "expandCollapse":
                    state := pat.ExpandCollapseState
                    if state = 1   ; Expanded — collapse it
                    {
                        pat.Collapse()
                        resultMsg := "Collapsed"
                    }
                    else           ; Collapsed / PartiallyExpanded / LeafNode — expand
                    {
                        pat.Expand()
                        resultMsg := "Expanded"
                    }
                case "select":
                    pat.Select()
                    resultMsg := "Selected"
                case "scrollIntoView":
                    pat.ScrollIntoView()
                    resultMsg := "Scrolled into view"
                case "defaultAction":
                    pat.DoDefaultAction()
                    resultMsg := "DoDefaultAction fired"
            }
            this.sbMain.SetText("  " resultMsg " — " desc.pattern " on captured element")
            ; Flash the element so the user sees which one was affected
            this.StartHighlight()
            ; Refresh the patterns panel (short delay lets the UI settle first)
            SetTimer(ObjBindMethod(this, "PopulatePatterns", this.capturedElement), -150)
        } catch as err {
            this.sbMain.SetText("  Pattern invoke failed: " err.Message)
        }
    }

    ; ════════════════════════════════════════════
    ;  UIA Tree — right panel TreeView
    ; ════════════════════════════════════════════
    /**
     * Render the captured window's full UIA subtree into the main TreeView.
     * Always uses a freshly fetched live root (not the cached one) so all children
     * are visible — the cached version may have been built with a non-Subtree scope.
     * After the build, scrolls the captured element into view via SelectCapturedInTree.
     */
    BuildTree() {
        this.tvUIA.Delete()
        this.treeViewMap := Map()

        if !this.capturedWindowEl
            return

        ; Use a live (non-cached) element for the tree so all children are visible
        try liveRoot := UIA.ElementFromHandle(this.capturedWindowEl.NativeWindowHandle)
        if !IsSet(liveRoot) || !liveRoot
            liveRoot := this.capturedWindowEl

        this.tvUIA.Opt("-Redraw")

        ; Recursively build from the window root
        this.RecurseTree(liveRoot, 0, 0)

        this.tvUIA.Opt("+Redraw")

        ; Select after redraw is re-enabled so Vis/VisFirst actually scrolls
        this.SelectCapturedInTree()

        n := this.treeViewMap.Count
        this.sbMain.SetText("  " n " element" (n = 1 ? "" : "s") " in tree")
        this._UpdateElementCount()
    }

    /** Refresh the "Elements: N" readout from the current tree map size. */
    _UpdateElementCount() {
        this.editElemCount.Value := "Elements: " this.treeViewMap.Count
    }

    /**
     * Recursive helper that walks the UIA tree depth-first into the TreeView.
     * @param depth  Used both for the recursion guard and to auto-expand the first 2 levels.
     *
     * Two child-walking strategies, switched by the Deep Scan checkbox:
     *   - Deep Scan ON:  TreeWalkerTrue (raw view) — sees every element including
     *                    layout containers; slower but complete.
     *   - Deep Scan OFF: el.FindAll(TrueCondition, scope=Children) — faster, may
     *                    miss elements that aren't in the default control view.
     */
    RecurseTree(el, parentTVItem, depth) {
        ; Build the display label
        label := this.GetLabel(el)

        ; Add to TreeView (expand first 2 levels)
        opts := depth < 2 ? "Expand" : ""
        tvItem := this.tvUIA.Add(label, parentTVItem, opts)

        ; Store mapping
        this.treeViewMap[tvItem] := el

        if this.chkDeepScan.Value
        {
            ; Deep scan: TreeWalkerTrue (raw view — sees everything, slower)
            try
            {
                child := UIA.TreeWalkerTrue.GetFirstChildElement(el)
                while child
                {
                    this.RecurseTree(child, tvItem, depth + 1)
                    child := UIA.TreeWalkerTrue.GetNextSiblingElement(child)
                }
            }
        }
        else
        {
            ; Fast scan: FindAll (may miss some elements)
            try
            {
                children := el.FindAll(UIA.TrueCondition, , UIA_TreeScope.Children)
                for child in children
                    this.RecurseTree(child, tvItem, depth + 1)
            }
        }
    }

    /**
     * Build the display label for one TreeView node.
     * Format priority: `Name (ClassName) [AutomationId]`. Falls back to the type name
     * (or `Type:N`) if the element has no name/class. Each property is try-wrapped so a
     * partially-broken provider doesn't blank out the whole label.
     */
    GetLabel(el) {
        name := ""
        try name := el.Name

        className := ""
        try className := el.ClassName

        automationId := ""
        try automationId := el.AutomationId

        label := name ? name : ""
        if className
            label .= (label ? " " : "") "(" className ")"
        if automationId
            label .= " [" automationId "]"
        if !label
        {
            ; Fallback to type if nothing else
            try
            {
                typeId := el.Type
                result := UIA_Type.HasValue(typeId)
                label := result ? result : "Type:" typeId
            }
            catch
                label := "?"
        }
        return label
    }

    /**
     * Locate the captured element in the rendered TreeView and select+scroll-to it.
     * Two-pass match — strong identity first, weaker geometric match second:
     *   Pass 1: AutomationId + Type — unique within a window when AID is present.
     *   Pass 2: Type + Name + identical BoundingRectangle — copes with elements that
     *           have no AID (most legacy Win32 controls).
     * @returns true if found and selected, false otherwise (caller may rebuild the tree).
     */
    SelectCapturedInTree() {
        if !this.capturedElement
            return false

        ; Gather target properties
        targetAid := ""
        try targetAid := this.capturedElement.AutomationId
        targetType := ""
        try targetType := this.capturedElement.Type
        targetName := ""
        try targetName := this.capturedElement.Name
        targetRect := ""
        try targetRect := this.capturedElement.BoundingRectangle

        ; Pass 1: match by AutomationId + Type (best, unique identifier)
        if targetAid
        {
            for tvItem, el in this.treeViewMap
            {
                try
                {
                    if el.AutomationId = targetAid && el.Type = targetType
                    {
                        this.tvUIA.Modify(tvItem, "Select Vis")
                        this.tvUIA.Modify(tvItem, "VisFirst")
                        return true
                    }
                }
            }
        }

        ; Pass 2: match by Type + Name + BoundingRectangle
        for tvItem, el in this.treeViewMap
        {
            match := false
            try
            {
                if el.Type = targetType
                {
                    elName := ""
                    try elName := el.Name
                    if elName = targetName
                    {
                        elRect := el.BoundingRectangle
                        if targetRect && elRect.l = targetRect.l && elRect.t = targetRect.t
                        && elRect.r = targetRect.r && elRect.b = targetRect.b
                            match := true
                    }
                }
            }
            if match
            {
                this.tvUIA.Modify(tvItem, "Select Vis")
                this.tvUIA.Modify(tvItem, "VisFirst")
                return true
            }
        }
        return false
    }

    /**
     * Re-render the TreeView keeping only nodes whose label contains the filter text
     * (or whose descendants do). Wired to the editFilter Change event with a 300ms
     * debounce in __New, so rapid typing doesn't kick off N redundant tree walks.
     *
     * Two-phase implementation: _CollectFiltered walks UIA once and produces a tree of
     * matched-or-has-matching-descendant nodes; _RenderFiltered renders that tree into
     * the TreeView. The previous implementation walked each subtree twice.
     */
    FilterTree() {
        filterText := this.editFilter.Value
        this._DisableScintilla()

        if !filterText
        {
            ; Empty filter — show the full tree
            this.BuildTree()
            this.sbMain.SetText("  Filter cleared")
            this._EnableScintilla()
            return
        }

        if !this.capturedWindowEl
        {
            this._EnableScintilla()
            return
        }

        ; Use a live (non-cached) root so Deep Scan walks all descendants
        try liveRoot := UIA.ElementFromHandle(this.capturedWindowEl.NativeWindowHandle)
        if !IsSet(liveRoot) || !liveRoot
            liveRoot := this.capturedWindowEl

        deepScan := this.chkDeepScan.Value

        ; Phase 1 — single walk of the UIA tree, collecting matches into a plain-object tree.
        ; Each UIA element is visited exactly once (the previous two-function version walked
        ; every subtree twice — once to test for matches, again to add matched nodes).
        matched := this._CollectFiltered(liveRoot, filterText, deepScan)

        ; Phase 2 — render the collected match tree into the TreeView
        this.tvUIA.Delete()
        this.treeViewMap := Map()
        this.tvUIA.Opt("-Redraw")
        if matched
            this._RenderFiltered(matched, 0)
        this.tvUIA.Opt("+Redraw")

        n := this.treeViewMap.Count
        this.sbMain.SetText("  Filter '" filterText "': " n " element" (n = 1 ? "" : "s") " matched")
        this._UpdateElementCount()

        this._EnableScintilla()
    }

    /**
     * Phase 1 of FilterTree. Recursively walks the UIA subtree rooted at `el` and
     * returns a {el, label, children} object for every node that matches the filter
     * OR has a descendant that does. Returns 0 to signal "this whole branch is dead".
     * Honors Deep Scan (raw walker vs control-view FindAll).
     */
    _CollectFiltered(el, filterText, deepScan) {
        label := this.GetLabel(el)
        selfMatches := InStr(label, filterText)

        matchedKids := []
        if deepScan
        {
            ; Raw-view walk — sees every element including layout containers
            try
            {
                child := UIA.TreeWalkerTrue.GetFirstChildElement(el)
                while child
                {
                    sub := this._CollectFiltered(child, filterText, deepScan)
                    if sub
                        matchedKids.Push(sub)
                    child := UIA.TreeWalkerTrue.GetNextSiblingElement(child)
                }
            }
        }
        else
        {
            ; Control-view walk — faster, hides layout noise
            try
            {
                for child in el.FindAll(UIA.TrueCondition, , UIA_TreeScope.Children)
                {
                    sub := this._CollectFiltered(child, filterText, deepScan)
                    if sub
                        matchedKids.Push(sub)
                }
            }
        }

        if !selfMatches && !matchedKids.Length
            return 0
        return {el: el, label: label, children: matchedKids}
    }

    /**
     * Phase 2 of FilterTree. Recursively renders the {el, label, children} tree
     * returned by _CollectFiltered into the TreeView. Always parent-before-children
     * so each child has a valid parent TV item. Auto-expands every node so matches
     * are visible without the user having to click open the parents.
     */
    _RenderFiltered(node, parentTVItem) {
        tvItem := this.tvUIA.Add(node.label, parentTVItem, "Expand")
        this.treeViewMap[tvItem] := node.el
        for child in node.children
            this._RenderFiltered(child, tvItem)
    }

    ; ════════════════════════════════════════════
    ;  Highlight — draw a border around captured element
    ; ════════════════════════════════════════════
    /**
     * Draw a colored rectangle outline around the currently captured element.
     * Color depends on the target process: red for elevated (we may not be able to
     * interact), green for normal. Re-uses a single hidden Gui via WinSetRegion to
     * carve out the inside, leaving just a border.
     */
    StartHighlight() {
        this.StopCapture()
        if !this.capturedElement
            return
        try {
            loc := this.capturedElement.BoundingRectangle
            color := (this._lastMonitorPid && IsProcessElevated(this._lastMonitorPid)) ? "Red" : "Green"
            this.ShowHighlightRect(loc.l, loc.t, loc.r - loc.l, loc.b - loc.t, color)
        }
    }

    /**
     * Low-level highlight primitive — draws a hollow rectangle at screen coords.
     * Lazy-creates the borderless AlwaysOnTop tool window on first use and re-shapes it
     * via WinSetRegion (an outer rect minus an inner rect = just the border).
     */
    ShowHighlightRect(x, y, w, h, color := "Green", thickness := 2) {
        if !this.highlightGui {
            this.highlightGui := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")
        }
        g := this.highlightGui
        g.BackColor := color
        d := thickness
        iw := w + d, ih := h + d
        totalW := w + d * 2, totalH := h + d * 2
        drawX := x - d, drawY := y - d
        WinSetRegion("0-0 " totalW "-0 " totalW "-" totalH " 0-" totalH " 0-0 "
            . d "-" d " " iw "-" d " " iw "-" ih " " d "-" ih " " d "-" d, g.Hwnd)
        g.Show("NA x" drawX " y" drawY " w" totalW " h" totalH)
    }

    /** Hide the highlight overlay (does not destroy it — kept for reuse). */
    ClearHighlight() {
        if this.highlightGui {
            try this.highlightGui.Hide()
        }
    }

    /**
     * Cycle the highlight through Red/Blue/Green twice as a visual "look here" pulse.
     * Used by the tree context menu's Highlight option to draw attention to a specific
     * element without permanently selecting it.
     */
    BlinkHighlight(el) {
        try loc := el.BoundingRectangle
        catch
            return
        x := loc.l, y := loc.t, w := loc.r - loc.l, h := loc.b - loc.t
        colors   := ["Red", "Blue", "Green", "Red", "Blue", "Green"]
        interval := 300
        loop colors.Length
            SetTimer(ObjBindMethod(this, "ShowHighlightRect", x, y, w, h, colors[A_Index]), -(interval * (A_Index - 1) + 1))
        SetTimer(ObjBindMethod(this, "ClearHighlight"), -(interval * colors.Length + 1))
    }

    /** Currently just a thin alias for ClearHighlight — kept for naming clarity. */
    StopCapture() {
        this.ClearHighlight()
    }

    /**
     * Reset every panel and clear all captured state. Stops tracking if active and
     * collapses the status bar back to the F1-prompt hint. Does NOT exit the app.
     */
    ClearInspector() {
        this.StopCapture()
        if this.tracking
            this.StopTracking()

        this.capturedElement   := ""
        this.capturedWindowEl  := ""
        this.capturedHwnd      := 0
        this.treeViewMap       := Map()
        this.patternActionMap  := Map()
        this.parentStructureMap := Map()
        this._lastMatchCount   := -1

        this.tvUIA.Delete()
        this.tvAnchors.Delete()
        this.tvPatterns.Delete()
        this.lvProps.Delete()
        loop 5
            this.lvWin.Modify(A_Index,,, "")

        this.editTarget.Value := "-"
        this.editFilter.Value := ""
        this._UpdateElementCount()

        this.sbMain.SetText("  Inspector cleared. Press " triggers.gettrigger(CaptureHotkeyFired) " to capture.")
        this.sbMain.SetText("-", 2)
        this.sbMain.SetText("-", 3)
        this.sbMain.Opt("BackgroundDefault")

        this._UpdateControls()
    }

    ; ════════════════════════════════════════════
    ;  Keyboard Navigation — walk the TreeView nodes
    ; ════════════════════════════════════════════
    /**
     * Move the TreeView selection one hop in the given direction and re-inspect.
     * Bound to NumpadAdd (child — falls back to next sibling if no child exists),
     * NumpadSub (parent), and the up/down directions are reachable programmatically.
     * After the move, re-runs property/pattern/highlight population on the new node.
     */
    NavigateElement(direction, *) {
        selected := this.tvUIA.GetSelection()
        if !selected
        {
            this.sbMain.SetText("  No element selected in tree (press " triggers.gettrigger(CaptureHotkeyFired) " first)")
            return
        }

        target := 0
        switch direction
        {
            case "child":
                target := this.tvUIA.GetChild(selected)
                if !target
                    target := this.tvUIA.GetNext(selected)
            case "parent":
                target := this.tvUIA.GetParent(selected)
            case "next":
                target := this.tvUIA.GetNext(selected)
            case "prev":
                target := this.tvUIA.GetPrev(selected)
        }

        if !target
        {
            this.sbMain.SetText("  No " direction " node")
            return
        }

        ; Select in tree and update inspector
        this.tvUIA.Modify(target, "Select Vis")
        this.tvUIA.Modify(target, "VisFirst")
        this._SelectTreeNode(target)
    }

    /**
     * Make sure the captured element is selected in the current tree, rebuilding the
     * tree from its top-level window if necessary. Used after operations that may have
     * jumped to an element outside the previously-captured window's subtree.
     * @returns true if the element ended up selected, false if neither the existing
     *          tree nor a fresh rebuild contained it.
     */
    SyncTree() {
        if !this.capturedElement
            return false
        if this.treeViewMap.Count && this.SelectCapturedInTree()
            return true
        ; Element not in tree — rebuild from its window
        try
        {
            hwnd := this.capturedElement.WinId
            if hwnd
            {
                cr := this._MakeCacheRequest()
                this._DisableScintilla()
                this.capturedWindowEl := UIA.ElementFromHandle(hwnd, cr)
                this.PopulateWindowInfo(hwnd)
                this.BuildTree()
                this._EnableScintilla()
                ; Try selecting again after rebuild
                return this.SelectCapturedInTree()
            }
        }
        return false
    }

    ; ════════════════════════════════════════════
    ;  Jump to nearest ancestor with AutomationId (walks TreeView nodes)
    ; ════════════════════════════════════════════
    /**
     * Bound to Ctrl+I. Walks up the TreeView from the current selection until it finds
     * an element with a non-empty AutomationId, then selects that node. Useful when the
     * user clicked on a label/text leaf and wants to anchor a macro on the surrounding
     * named container instead.
     */
    JumpToNearestAutomationId(*) {
        selected := this.tvUIA.GetSelection()
        if !selected
        {
            this.sbMain.SetText("  No element selected in tree (press " triggers.gettrigger(CaptureHotkeyFired) " first)")
            return
        }

        ; Check current node
        if this.treeViewMap.Has(selected)
        {
            try
            {
                aid := this.treeViewMap[selected].AutomationId
                if aid
                {
                    this.sbMain.SetText("  Current element already has AutomationId: " aid)
                    return
                }
            }
        }

        ; Walk up TreeView parents
        node := selected
        loop
        {
            node := this.tvUIA.GetParent(node)
            if !node
                break
            if !this.treeViewMap.Has(node)
                continue
            el := this.treeViewMap[node]
            try
            {
                aid := el.AutomationId
                if aid
                {
                    this.tvUIA.Modify(node, "Select Vis")
                    this.tvUIA.Modify(node, "VisFirst")
                    this._SelectTreeNode(node)
                    this.sbMain.SetText("  Jumped to AutomationId: " aid)
                    return
                }
            }
        }

        this.sbMain.SetText("  No ancestor with AutomationId found")
    }

    /**
     * Switch the captured element to the one mapped from a TreeView item, then
     * refresh Properties / Patterns / Highlight / Status bar. Shared by every code
     * path that "selects" a node in the main tree (click, navigate, jump-to-AID).
     */
    _SelectTreeNode(tvItem) {
        if !this.treeViewMap.Has(tvItem)
            return
        el := this.treeViewMap[tvItem]
        this.capturedElement := el
        this.PopulateProperties(el)
        this.PopulatePatterns(el)
        this.StartHighlight()
        this._UpdateIndexRange()
        this.UpdateStatusBar()
    }

    ; ════════════════════════════════════════════
    ;  Control enable/disable based on current state
    ; ════════════════════════════════════════════
    /**
     * Three-tier enable matrix based on what the user has done so far:
     *   - hasTree     → enables filter (a tree must exist to filter)
     *   - hasCaptured → enables macro DDLs + Add Element + Refresh Anchors
     *   - hasSteps    → enables Copy/Test/Clear macro buttons
     * Also re-runs the guide-mode highlight, since the next-step suggestion depends on
     * which of these tiers we're at.
     */
    _UpdateControls() {
        hasCaptured := this.capturedElement != ""
        hasTree     := this.treeViewMap.Count > 0
        hasSteps    := this.macroSteps.Length > 0

        ; Inspect group
        this.editFilter.Enabled   := hasTree

        ; Macro group — DDLs need a captured element
        this.ddlAction.Enabled    := hasCaptured
        this.ddlMatchMode.Enabled := hasCaptured
        this.ddlScope.Enabled     := hasCaptured
        this.ddlAnchor.Enabled    := hasCaptured
        this.btnAddElement.Enabled := hasCaptured
        this.btnRefreshAnchors.Enabled := hasCaptured

        ; Macro buttons — Test/Copy operate on the editor text, Clear on the steps
        hasCode := Trim(this.sciCtl.Text) != ""
        this.btnCopyMacro.Enabled  := hasCode
        this.btnTestMacro.Enabled  := hasCode
        this.btnClearMacro.Enabled := hasCode || hasSteps

        ; AI buttons
        if this.HasProp("btnAskAI")
            this.btnAskAI.Enabled := hasCaptured
        if this.HasProp("btnFindUnique")
            this.btnFindUnique.Enabled := hasCaptured && this._lastMatchCount > 1

        this._UpdateGuide()
    }

    ; ════════════════════════════════════════════
    ;  Guide mode — blue highlight that walks the
    ;  user through Capture → Add element → Test
    ; ════════════════════════════════════════════
    /**
     * Decide where to draw the blue "next thing to click" highlight, given current state.
     * State machine:
     *   - guide off                → nothing.
     *   - no captured element      → highlight the F1-hint part of the status bar.
     *   - captured but no steps,
     *     and the path is unique   → highlight "Add element".
     *   - captured but no steps,
     *     and >1 matches           → highlight Anchor Points + Anchor DDL (need scoping).
     *   - has steps                → highlight "Test" so the user can run their macro.
     * Auto-hides after 4s via _ArmGuideAutoHide so the overlay doesn't get in the way.
     */
    _UpdateGuide() {
        if !this.guideMode
        {
            this._ClearGuideHighlight()
            return
        }
        if !this.capturedElement
        {
            ; Highlight only the first status-bar part — the one with the F1 hint
            if this._GetStatusBarPartRect(0, &x, &y, &w, &h)
                this._GuideHighlightRect(x, y, w, h)
            this._ArmGuideAutoHide()
            return
        }
        if this.macroSteps.Length = 0
        {
            ; Path is ambiguous (>1 match) → guide the user to add/pick an anchor
            ; so they can scope the search and make the path unique.
            if this._lastMatchCount > 1
            {
                this._GuideHighlight(this.tvAnchors.Hwnd)
                this._GuideHighlightSecondary(this.ddlAnchor.Hwnd)
                this.sbMain.SetText("  Path is not unique — right-click on Anchor Points → Create Anchor, then pick from Anchor dropdown.")
            }
            else
                this._GuideHighlight(this.btnAddElement.Hwnd)
        }
        else
            this._GuideHighlight(this.btnTestMacro.Hwnd)
        this._ArmGuideAutoHide()
    }

    /** Schedule the guide highlight to auto-hide in 4s — restart-able on each call. */
    _ArmGuideAutoHide() {
        if !this._guideHideTimer
            this._guideHideTimer := ObjBindMethod(this, "_ClearGuideHighlight")
        SetTimer(this._guideHideTimer, -4000)   ; hide after 4s (within the 3-5s window)
    }

    /**
     * Compute the screen rect of one part of the status bar via SB_GETRECT (0x40A) +
     * ClientToScreen. Used by the guide-mode highlight to box just the F1-hint part
     * instead of the whole status bar.
     * @returns true on success and writes via the by-ref params; false if the part is empty.
     */
    _GetStatusBarPartRect(partIdx, &x, &y, &w, &h) {
        sbHwnd := this.sbMain.Hwnd
        rc := Buffer(16, 0)
        ; SB_GETRECT = 0x40A — returns the part rect in client coords of the status bar
        if !SendMessage(0x40A, partIdx, rc.Ptr, , sbHwnd)
            return false
        l := NumGet(rc, 0, "Int"), t := NumGet(rc, 4, "Int")
        r := NumGet(rc, 8, "Int"), b := NumGet(rc, 12, "Int")
        if (r - l) <= 0 || (b - t) <= 0
            return false
        ; Convert the top-left from status-bar client coords to screen coords
        pt := Buffer(8, 0)
        NumPut("Int", l, "Int", t, pt)
        DllCall("ClientToScreen", "ptr", sbHwnd, "ptr", pt)
        x := NumGet(pt, 0, "Int"), y := NumGet(pt, 4, "Int")
        w := r - l, h := b - t
        return true
    }

    /** Wrap a control's screen rect in a blue guide highlight box. */
    _GuideHighlight(hwnd, thickness := 3) {
        rc := Buffer(16, 0)
        if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", rc)
            return
        x := NumGet(rc, 0, "Int"), y := NumGet(rc, 4, "Int")
        w := NumGet(rc, 8, "Int") - x, h := NumGet(rc, 12, "Int") - y
        if w <= 0 || h <= 0
            return
        this._GuideHighlightRect(x, y, w, h, thickness)
    }

    /**
     * Second guide overlay used when two controls need to be highlighted together
     * (e.g. Anchor Points panel + Anchor DDL when prompting the user to scope a path).
     * Lives on its own Gui so it can coexist with the primary _GuideHighlight box.
     */
    _GuideHighlightSecondary(hwnd, thickness := 3) {
        rc := Buffer(16, 0)
        if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", rc)
            return
        x := NumGet(rc, 0, "Int"), y := NumGet(rc, 4, "Int")
        w := NumGet(rc, 8, "Int") - x, h := NumGet(rc, 12, "Int") - y
        if w <= 0 || h <= 0
            return
        if !this._guideHighlightGui2
            this._guideHighlightGui2 := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000 +Owner" this.gui.Hwnd)
        g := this._guideHighlightGui2
        g.BackColor := "0066FF"
        d := thickness
        iw := w + d, ih := h + d
        totalW := w + d * 2, totalH := h + d * 2
        drawX := x - d, drawY := y - d
        WinSetRegion("0-0 " totalW "-0 " totalW "-" totalH " 0-" totalH " 0-0 "
            . d "-" d " " iw "-" d " " iw "-" ih " " d "-" ih " " d "-" d, g.Hwnd)
        g.Show("NA x" drawX " y" drawY " w" totalW " h" totalH)
    }

    /**
     * Core primitive for guide highlights — draws a blue hollow rect at screen coords.
     * Hides any secondary overlay so the previous "two highlights" state doesn't leak
     * into the next one-highlight call.
     */
    _GuideHighlightRect(x, y, w, h, thickness := 3) {
        ; Hide the secondary overlay — callers re-show it only when they need two highlights
        if this._guideHighlightGui2
            try this._guideHighlightGui2.Hide()
        if !this._guideHighlightGui
            this._guideHighlightGui := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000 +Owner" this.gui.Hwnd)
        g := this._guideHighlightGui
        g.BackColor := "0066FF"   ; blue (green/red are taken by element highlights)
        d := thickness
        iw := w + d, ih := h + d
        totalW := w + d * 2, totalH := h + d * 2
        drawX := x - d, drawY := y - d
        WinSetRegion("0-0 " totalW "-0 " totalW "-" totalH " 0-" totalH " 0-0 "
            . d "-" d " " iw "-" d " " iw "-" ih " " d "-" ih " " d "-" d, g.Hwnd)
        g.Show("NA x" drawX " y" drawY " w" totalW " h" totalH)
    }

    /** Hide both guide overlays. Called from the auto-hide timer and on shutdown. */
    _ClearGuideHighlight() {
        if this._guideHighlightGui
            try this._guideHighlightGui.Hide()
        if this._guideHighlightGui2
            try this._guideHighlightGui2.Hide()
    }

    ; ════════════════════════════════════════════
    ;  Anchor Points — flat list of queryable ancestors
    ;  Right-click builds a chained FindFirst path from
    ;  the anchor down to the selected element in the main tree.
    ; ════════════════════════════════════════════
    /**
     * Walk up from the captured element to the root, collecting every ancestor that's
     * "queryable" (has enough identifying info — AID, or Type+Name, etc. — for a stable
     * FindFirst). Renders the result into the Anchor Points TreeView, closest first.
     * Also refreshes the Anchor DDL on the macro row so the user can pick scopes.
     */
    PopulateAnchorPoints(*) {
        if !this.capturedElement
        {
            this.sbMain.SetText("  Capture an element first (press " triggers.gettrigger(CaptureHotkeyFired) ")")
            return
        }

        ; Collect full parent chain (captured element first, root last)
        fullChain := []
        el := this.capturedElement
        fullChain.Push(el)
        loop
        {
            try
                el := UIA.TreeWalkerTrue.GetParentElement(el)
            catch
                break
            if !el
                break
            fullChain.Push(el)
        }

        ; Filter to queryable anchors, keep order (closest first)
        this._anchors := []
        for ancestor in fullChain
        {
            info := this._GetAnchorInfo(ancestor)
            if info.queryable
                this._anchors.Push({el: ancestor, info: info})
        }

        if !this._anchors.Length
        {
            this.sbMain.SetText("  No queryable ancestors found")
            return
        }

        ; Populate embedded Anchor Points TreeView
        this.tvAnchors.Delete()
        this.parentStructureMap := Map()

        ; Flat list — closest anchor at top, root at bottom
        total := this._anchors.Length
        for i, anchor in this._anchors
        {
            anchor.pos := total - i + 1
            tvItem := this.tvAnchors.Add(anchor.info.label, 0)
            this.parentStructureMap[tvItem] := anchor
        }

        ; Select first item (closest to captured element)
        first := this.tvAnchors.GetChild(0)
        if first
            this.tvAnchors.Modify(first, "Select Vis")

        ; Refresh anchor DDL for macro section
        this._RefreshAnchorDDL()
    }

    /**
     * Inspect one element and decide how to identify it as an anchor. Picks the
     * strongest available combo:
     *   - AutomationId (+ Type if known)
     *   - Type + Name (+ ClassName if known)
     *   - Name + ClassName
     * Returns {queryable: bool, label: friendly-string, condition: AHK-object-literal}.
     * `queryable: false` means we couldn't form a stable selector.
     */
    _GetAnchorInfo(el) {
        aid := "", name := "", className := "", typeName := ""
        try aid := el.AutomationId
        try name := el.Name
        try className := el.ClassName
        try
        {
            typeId := el.Type
            result := UIA_Type.HasValue(typeId)
            typeName := result ? result : ""
        }

        label := name ? name : (className ? "(" className ")" : (typeName ? typeName : "?"))

        if aid
        {
            cond := '{AutomationId: "' aid '"'
            if typeName
                cond .= ', Type: "' typeName '"'
            cond .= "}"
            return {queryable: true, label: label, condition: cond}
        }
        if name && typeName
        {
            cond := '{Type: "' typeName '", Name: "' name '"'
            if className
                cond .= ', ClassName: "' className '"'
            cond .= "}"
            return {queryable: true, label: label, condition: cond}
        }
        if name && className
            return {queryable: true, label: label, condition: '{Name: "' name '", ClassName: "' className '"}'}

        return {queryable: false, label: label, condition: ""}
    }

    /**
     * Build a chained `.FindFirst(...).FindFirst(...)` string starting from an anchor
     * and walking down to the captured element. anchorIndex is the position in
     * `this._anchors` (1 = closest to captured element, N = root).
     */
    _BuildChainedPath(anchorIndex) {
        ; anchors[1] = captured element (or closest), anchors[N] = root
        ; We want: anchor.FindFirst(next).FindFirst(next)...FindFirst(target)
        ; The chain goes from anchorIndex down to index 1
        if anchorIndex <= 1
            return ".FindFirst(" this._anchors[1].info.condition ")"

        chain := ""
        Loop anchorIndex - 1
        {
            idx := anchorIndex - A_Index
            chain .= ".FindFirst(" this._anchors[idx].info.condition ")"
        }
        return chain
    }

    /** Anchor TreeView click — re-inspect the anchor element (jumps captured to it). */
    _OnAnchorClick(tvItem) {
        if !this.parentStructureMap.Has(tvItem)
            return
        anchor := this.parentStructureMap[tvItem]
        this.capturedElement := anchor.el
        this.PopulateProperties(anchor.el)
        this.PopulatePatterns(anchor.el)
        this.StartHighlight()
        this.UpdateStatusBar()
    }

    /**
     * Right-click on an anchor — show context menu (Copy Code / Jump / Add to Macro /
     * Create Anchor Variable). Stashes tvItem in _anchorContextItem so the per-action
     * handlers can re-resolve which anchor was clicked.
     */
    _OnAnchorContextMenu(tvItem) {
        if !this.parentStructureMap.Has(tvItem)
            return
        this._anchorContextItem := tvItem

        anchorMenu := Menu()
        anchorMenu.Add("Copy Code", (*) => this._OnAnchorAction("CopyCode"))
        anchorMenu.Disable("Copy Code")
        anchorMenu.Add("Jump to Element", (*) => this._OnAnchorAction("JumpToElement"))
        anchorMenu.Add("Add to Macro", (*) => this._OnAnchorAction("AddToMacro"))
        anchorMenu.Disable("Add to Macro")
        anchorMenu.Add()  ; separator
        anchorMenu.Add("Create Anchor Variable", (*) => this._OnAnchorAction("CreateAnchorVar"))
        anchorMenu.Show()
    }

    /**
     * Dispatch table for anchor context-menu actions.
     *   "CopyCode"         → copy a `winEl.FindFirst(...)` snippet.
     *   "JumpToElement"    → set captured = anchor element and select it in the tree.
     *   "AddToMacro"       → push a step using this anchor's condition.
     *   "CreateAnchorVar"  → name this anchor and store it for use as a macro scope.
     */
    _OnAnchorAction(action) {
        tvItem := this._anchorContextItem
        if !this.parentStructureMap.Has(tvItem)
            return
        anchor := this.parentStructureMap[tvItem]

        if action = "CopyCode"
        {
            this._OnAnchorCopy(tvItem)
            return
        }

        if action = "JumpToElement"
        {
            this.capturedElement := anchor.el
            this.SelectCapturedInTree()
            this.PopulateProperties(anchor.el)
            this.PopulatePatterns(anchor.el)
            this.StartHighlight()
            this.UpdateStatusBar()
            return
        }

        if action = "AddToMacro"
        {
            macroAction := this.ddlAction.Text
            anchorName := this._GetSelectedAnchor()
            matchMode  := this.ddlMatchMode.Text
            scopeText  := this.ddlScope.Text
            this.macroSteps.Push({condition: anchor.info.condition, action: macroAction, anchor: anchorName, matchMode: matchMode, scopeText: scopeText})
            this._AppendMacroStep(anchor.info.condition, macroAction, anchorName, matchMode, scopeText)
            count    := this._CountMatches(anchor.info.condition, anchorName, scopeText, matchMode)
            countMsg := this._FormatMatchCount(count)
            this.sbMain.SetText("  Added step " this.macroSteps.Length ": " macroAction " on " anchor.info.condition (countMsg ? "  · " countMsg : ""))
            this._UpdateControls()
            return
        }

        if action = "CreateAnchorVar"
        {
            this._CreateAnchorVariable(anchor)
            return
        }
    }

    /**
     * Modal popup that prompts the user for a variable name, then stores
     * the anchor under `this.anchorVars[name]`. Prefills `<TypeName>Anc<N>` so the
     * user can usually just hit Enter. Validates the name as a legal AHK identifier.
     */
    _CreateAnchorVariable(anchor) {
        ; Build a unique prefill name from element type
        typeName := ""
        try typeName := anchor.el.LocalizedControlType
        if !typeName
            try typeName := UIA.Type[anchor.el.Type]
        if !typeName
            typeName := "Element"
        typeName := RegExReplace(typeName, "\s+", "")

        this._anchorVarCounter++
        prefill := typeName "Anc" this._anchorVarCounter

        ; Popup GUI for user to confirm/edit the variable name
        popupGui := Gui("+Owner" this.gui.Hwnd " +ToolWindow", "Create Anchor Variable")
        popupGui.SetFont("s9", "Segoe UI")
        popupGui.AddText("xm y10 w280", "Variable name for this anchor:")
        editName := popupGui.AddEdit("xm y+6 w280 h24", prefill)
        popupGui.AddText("xm y+8 w280 c666666", "Condition: " anchor.info.condition)

        result := ""
        btnOk := popupGui.AddButton("xm y+12 w80 h26 Default", "OK")
        btnOk.OnEvent("Click", (*) => (result := editName.Text, popupGui.Destroy()))
        btnCancel := popupGui.AddButton("x+10 yp w80 h26", "Cancel")
        btnCancel.OnEvent("Click", (*) => popupGui.Destroy())
        popupGui.OnEvent("Close", (*) => popupGui.Destroy())
        popupGui.OnEvent("Escape", (*) => popupGui.Destroy())

        popupGui.Show()
        WinWaitClose(popupGui.Hwnd)

        if !result
            return

        ; Validate name — must be a valid AHK identifier
        if !RegExMatch(result, "^[a-zA-Z_]\w*$")
        {
            this.sbMain.SetText("  Invalid variable name: " result)
            return
        }

        ; Store the anchor variable
        this.anchorVars[result] := {el: anchor.el, condition: anchor.info.condition, label: anchor.info.label}
        this._RefreshAnchorDDL()
        this.sbMain.SetText("  Created anchor variable: " result " := ...FindFirst(" anchor.info.condition ")")
    }

    ; ════════════════════════════════════════════
    ;  Anchor variable manager — delete / rename
    ;  Triggered by right-clicking the Anchor DDL
    ; ════════════════════════════════════════════
    /**
     * Pop a manager dialog listing every stored anchor variable plus its usage count
     * across macroSteps. Lets the user rename (cascading the change to every step that
     * referenced it) or delete (blocked while still referenced).
     */
    _ShowAnchorManager(*) {
        if !this.anchorVars.Count
        {
            this.sbMain.SetText("  No anchor variables defined yet — create one from the Anchor Points panel")
            return
        }

        mgr := Gui("+Owner" this.gui.Hwnd " +ToolWindow", "Manage Anchor Variables")
        mgr.SetFont("s9", "Segoe UI")

        mgr.AddText("xm ym w520", "Stored anchor variables. Delete is blocked while a variable is in use by a macro step; rename updates both the step references and the generated script.")

        lv := mgr.AddListView("xm y+8 w520 h220", ["Name", "Condition", "Used"])
        lv.ModifyCol(1, 120)
        lv.ModifyCol(2, 340)
        lv.ModifyCol(3, 50)

        refreshLV := ObjBindMethod(this, "_PopulateAnchorManagerLV", lv)
        refreshLV.Call()

        btnDelete := mgr.AddButton("xm y+10 w80 h26", "Delete")
        btnDelete.OnEvent("Click", (*) => this._AnchorManagerDelete(lv, refreshLV))
        btnRename := mgr.AddButton("x+6 yp w80 h26", "Rename")
        btnRename.OnEvent("Click", (*) => this._AnchorManagerRename(lv, refreshLV, mgr))
        btnClose := mgr.AddButton("x+200 yp w80 h26 Default", "Close")
        btnClose.OnEvent("Click", (*) => mgr.Destroy())
        mgr.OnEvent("Close", (*) => mgr.Destroy())
        mgr.OnEvent("Escape", (*) => mgr.Destroy())

        mgr.Show()
    }

    /** Refill the anchor manager ListView from anchorVars + per-anchor reference counts. */
    _PopulateAnchorManagerLV(lv) {
        lv.Delete()
        for name, def in this.anchorVars
        {
            refCount := this._CountAnchorRefs(name)
            lv.Add(, name, def.condition, refCount)
        }
    }

    /** Count how many macroSteps currently reference this anchor variable name. */
    _CountAnchorRefs(name) {
        count := 0
        for step in this.macroSteps
        {
            if step.HasProp("anchor") && step.anchor = name
                count++
        }
        return count
    }

    /**
     * Delete the selected anchor variable. Blocked when refCount > 0 — deleting an
     * in-use anchor would leave dangling references in the generated script.
     */
    _AnchorManagerDelete(lv, refreshLV) {
        row := lv.GetNext()
        if !row
        {
            this.sbMain.SetText("  Select an anchor variable to delete")
            return
        }
        name     := lv.GetText(row, 1)
        refCount := Number(lv.GetText(row, 3))

        if refCount > 0
        {
            MsgBox("Cannot delete '" name "' — " refCount " macro step(s) reference it.`n`nRemove those steps first, then try again.",
                   "Anchor in use", "Iconx")
            return
        }

        this.anchorVars.Delete(name)
        refreshLV.Call()
        this._RefreshAnchorDDL()
        this.sbMain.SetText("  Deleted anchor variable: " name)
    }

    /**
     * Rename an anchor variable. Cascades the rename through every macroStep that
     * referenced the old name and re-renders the editor so the visible script picks
     * up the change. Validates that the new name is a legal AHK identifier and unused.
     */
    _AnchorManagerRename(lv, refreshLV, parentGui) {
        row := lv.GetNext()
        if !row
        {
            this.sbMain.SetText("  Select an anchor variable to rename")
            return
        }
        oldName := lv.GetText(row, 1)
        newName := this._PromptAnchorName("Rename Anchor Variable", "New name for '" oldName "':", oldName, parentGui)
        if newName = "" || newName = oldName
            return

        if !RegExMatch(newName, "^[a-zA-Z_]\w*$")
        {
            MsgBox("Invalid variable name: " newName "`n`nMust start with a letter or underscore and contain only letters, digits, and underscores.",
                   "Rename failed", "Iconx")
            return
        }
        if this.anchorVars.Has(newName)
        {
            MsgBox("An anchor variable named '" newName "' already exists.",
                   "Rename failed", "Iconx")
            return
        }

        ; Move the entry under the new key
        def := this.anchorVars[oldName]
        this.anchorVars.Delete(oldName)
        this.anchorVars[newName] := def

        ; Update every macro step that referenced the old name
        updated := 0
        for step in this.macroSteps
        {
            if step.HasProp("anchor") && step.anchor = oldName
            {
                step.anchor := newName
                updated++
            }
        }

        ; Re-render the editor so the script reflects the new name
        if updated
            this._RerenderEditor()

        refreshLV.Call()
        this._RefreshAnchorDDL()
        this.sbMain.SetText("  Renamed '" oldName "' → '" newName "'"
                           . (updated ? " (updated " updated " step(s))" : ""))
    }

    /**
     * Generic modal "name this thing" popup — single line edit, OK + Cancel.
     * Blocks via WinWaitClose. Returns the entered text (or "" if cancelled).
     * Shared by both Create and Rename anchor flows.
     */
    _PromptAnchorName(title, label, prefill, ownerGui) {
        popup := Gui("+Owner" ownerGui.Hwnd " +ToolWindow", title)
        popup.SetFont("s9", "Segoe UI")
        popup.AddText("xm y10 w280", label)
        editName := popup.AddEdit("xm y+6 w280 h24", prefill)

        result := ""
        btnOk := popup.AddButton("xm y+12 w80 h26 Default", "OK")
        btnOk.OnEvent("Click", (*) => (result := editName.Text, popup.Destroy()))
        btnCancel := popup.AddButton("x+10 yp w80 h26", "Cancel")
        btnCancel.OnEvent("Click", (*) => popup.Destroy())
        popup.OnEvent("Close", (*) => popup.Destroy())
        popup.OnEvent("Escape", (*) => popup.Destroy())

        popup.Show()
        WinWaitClose(popup.Hwnd)
        return result
    }

    /**
     * Rebuild the macro-row Anchor DDL. Item 0 is the captured window (default scope);
     * remaining items are stored anchor variables — but only those that are actually
     * ancestors of the captured element (matched by RuntimeId). Filtering this way
     * prevents the user from picking an anchor that wouldn't be in scope at runtime.
     */
    _RefreshAnchorDDL() {
        winLabel := "(none)"
        if this.capturedWindowEl
        {
            try
            {
                lbl := this.GetLabel(this.capturedWindowEl)
                if lbl != ""
                    winLabel := lbl
            }
        }
        items := [winLabel]
        this._anchorDDLMap := Map()  ; index => varName

        if this.capturedElement && this.anchorVars.Count
        {
            ; Build ancestor chain of the current element
            ancestors := Map()
            el := this.capturedElement
            loop
            {
                try
                    el := UIA.TreeWalkerTrue.GetParentElement(el)
                catch
                    break
                if !el
                    break
                ; Use RuntimeId as key for comparison
                try rid := el.GetRuntimeId()
                if IsSet(rid) && rid
                    ancestors[this._RuntimeIdStr(rid)] := true
            }

            ; Filter anchor vars to those in the ancestor chain
            for varName, anchor in this.anchorVars
            {
                try rid := anchor.el.GetRuntimeId()
                if IsSet(rid) && rid && ancestors.Has(this._RuntimeIdStr(rid))
                {
                    items.Push(varName)
                    this._anchorDDLMap[items.Length] := varName
                }
            }
        }

        this.ddlAnchor.Delete()
        this.ddlAnchor.Add(items)
        this.ddlAnchor.Choose(1)
    }

    /** Stringify a UIA RuntimeId array for use as a Map key (e.g. "42.7.1.0"). */
    _RuntimeIdStr(rid) {
        s := ""
        for v in rid
            s .= (s ? "." : "") v
        return s
    }

    /**
     * "Copy Code" handler from the anchor context menu. Builds a small standalone AHK
     * snippet (with #Requires + #Include) that resolves this anchor under its window,
     * copies it to the clipboard.
     */
    _OnAnchorCopy(tvItem) {
        if !this.parentStructureMap.Has(tvItem)
            return
        anchor := this.parentStructureMap[tvItem]

        winTitle := this._GetWinTitle()
        code := '#Requires AutoHotkey v2.0.2+`n'
        code .= '#Include ' this._UIAIncludePath() '`n`n'
        code .= 'winEl := UIA.ElementFromHandle("' winTitle '")`n'
        code .= "anchorEl := winEl.FindFirst(" anchor.info.condition ")"

        A_Clipboard := code
        this.sbMain.SetText("  Copied: " code)
    }

    ; ════════════════════════════════════════════
    ;  Macro Creator
    ; ════════════════════════════════════════════
    /**
     * Structured representation of the user's macro — a flat array of step records:
     *   {condition, action, anchor, matchMode, scopeText}
     * This is the source of truth; the Scintilla editor is rendered from it.
     */
    macroSteps := []

    /**
     * Live "would this condition uniquely identify one element?" probe.
     * Re-runs FindAll with the same root/scope/matchMode the generated code will use
     * so the user gets honest feedback before they hit Test. Used by UpdateStatusBar
     * (Path matches edit) and MacroAddElement (status bar message).
     * @returns The match count, or -1 on parse/search failure.
     */
    _CountMatches(condStr, anchorName := "", scopeName := "Descendants", matchMode := "Exact") {
        ; Determine search root — an anchor element if one is selected, else window root
        root := 0
        if anchorName && this.anchorVars.Has(anchorName)
            root := this.anchorVars[anchorName].el
        if !root
            root := this.capturedWindowEl
        if !root
            return -1

        condObj := this._ParseConditionString(condStr)
        if !IsObject(condObj)
            return -1

        try scope := UIA_TreeScope.%scopeName%
        if !IsSet(scope)
            scope := UIA_TreeScope.Descendants

        try {
            matches := root.FindAll(condObj, matchMode, scope)
            if IsObject(matches)
                return matches.Length
        }
        return -1
    }

    /**
     * Convert a match count into a short user-facing tag.
     * @returns "unique" / "N matches — narrow with anchor" / "not found in current tree" / "".
     *          Empty string when count is -1, so callers can append unconditionally.
     */
    _FormatMatchCount(count) {
        if count = 1
            return "unique"
        if count > 1
            return count " matches — narrow with anchor"
        if count = 0
            return "not found in current tree"
        return ""
    }

    /**
     * Update the UpDown index control range to reflect the number of FindAll matches
     * for the current captured element's condition. Resets value to 1.
     */
    _UpdateIndexRange()
    {
        if !this.capturedElement
            return
        cond      := this.BuildConditionString(this.capturedElement)
        anchor    := this._GetSelectedAnchor()
        scopeText := this.ddlScope.Text
        matchMode := this.ddlMatchMode.Text
        count     := this._CountMatches(cond, anchor, scopeText, matchMode)
        if count < 1
            count := 1
        this.udIndex.Opt("Range1-" count)
        this.udIndex.Value := 1
    }

    /**
     * Handler for the "Add element" button — appends one step to the macro.
     * Pulls action/anchor/matchMode/scope from the four DDLs and condition from the
     * captured element, pushes onto macroSteps, appends the code to the Scintilla
     * editor via _AppendMacroStep, then reports the match count in the status bar.
     */
    MacroAddElement(*) {
        if !this.capturedElement
        {
            this.sbMain.SetText("  Capture an element first")
            return
        }
        action     := this.ddlAction.Text
        anchorName := this._GetSelectedAnchor()
        cond       := this.BuildConditionString(this.capturedElement)
        matchMode  := this.ddlMatchMode.Text
        scopeText  := this.ddlScope.Text
        elIndex    := this.udIndex.Value
        this.macroSteps.Push({condition: cond, action: action, anchor: anchorName, matchMode: matchMode, scopeText: scopeText, index: elIndex})
        this._AppendMacroStep(cond, action, anchorName, matchMode, scopeText, elIndex)

        ; Uniqueness check — resolve the condition against the live tree so the user
        ; knows whether the step will hit exactly one element at runtime.
        count    := this._CountMatches(cond, anchorName, scopeText, matchMode)
        countMsg := this._FormatMatchCount(count)
        this.sbMain.SetText("  Added step " this.macroSteps.Length ": " action " on " cond (countMsg ? "  · " countMsg : ""))
        this._UpdateControls()
    }

    /** @returns The currently-selected anchor DDL variable name, or "" for "(none)". */
    _GetSelectedAnchor() {
        idx := this.ddlAnchor.Value
        if idx > 1 && this._anchorDDLMap.Has(idx)
            return this._anchorDDLMap[idx]
        return ""
    }

    /**
     * Append the code for one macro step to the Scintilla buffer.
     * Uses InsertText/AppendText (delta updates) instead of replacing the whole document
     * — that keeps Scintilla's existing syntax styling intact and avoids a full re-color.
     *
     * Lazily prepends `#Requires + #Include + winEl := …` the first time. Re-emits
     * `winEl := …` when the captured window changes between steps. Inserts `Sleep 50`
     * between adjacent steps (UI needs a beat to settle between actions).
     */
    _AppendMacroStep(condition, action, anchorName := "", matchMode := "Exact", scopeText := "Descendants", elIndex := 1) {
        code := this.sciCtl.Text

        ; Prepend #Requires + #Include + winEl if missing — use InsertText/AppendText instead of
        ; replacing the whole document so that Scintilla only re-highlights the changed portion
        ; and existing styling is never lost.
        winTitle    := this._GetWinTitle()
        needsHeader := !InStr(code, "#Include")
        needsWinEl  := !InStr(code, "ElementFromHandle")
        winChanged  := !needsWinEl && (winTitle != (this.HasOwnProp("_lastMacroWinTitle") ? this._lastMacroWinTitle : ""))

        if needsHeader || needsWinEl
        {
            header := ""
            if needsHeader
            {
                header .= "#Requires AutoHotkey v2.0.2+`r`n"
                header .= "#Include " this._UIAIncludePath() "`r`n`r`n"
            }
            if needsWinEl
                header .= 'winEl := UIA.ElementFromHandle("' winTitle '")`r`n`r`n'
            if code = ""
                this.sciCtl.AppendText(StrLen(header), header)
            else
                this.sciCtl.InsertText(0, header)
            this._lastMacroWinTitle := winTitle
        }
        else if winChanged
        {
            ; Window changed — emit a new winEl line before this step
            winElLine := '`r`n`r`nwinEl := UIA.ElementFromHandle("' winTitle '")`r`n'
            this.sciCtl.AppendText(StrLen(winElLine), winElLine)
            this._lastMacroWinTitle := winTitle
        }
        else if code != ""
        {
            sleepLine := "Sleep 50`r`n"
            this.sciCtl.AppendText(StrLen(sleepLine), sleepLine)
        }

        ; Append anchor variable assignment if needed (after winEl)
        if anchorName && !InStr(code, anchorName " :=")
        {
            anchorDef := this.anchorVars[anchorName]
            anchorLine := anchorName ' := winEl.FindFirst(' anchorDef.condition ')`r`n'
            this.sciCtl.AppendText(StrLen(anchorLine), anchorLine)
        }

        baseVar  := anchorName ? anchorName : "winEl"
        mmStr    := '"' matchMode '"'
        scopeStr := scopeText != "Descendants" ? "UIA_TreeScope." scopeText : ""
        findArgs := condition ", " mmStr (scopeStr ? ", " scopeStr : "")
        waitArgs := condition ", " mmStr ", 5000" (scopeStr ? ", " scopeStr : "")
        findExpr := baseVar '.FindAll(' findArgs ')[' elIndex ']'

        if action = "SetValue"
            newLine := findExpr '.SetValue("")`r`n'
        else if action = "WaitElement"
            newLine := baseVar '.WaitElement(' waitArgs ')`r`n'
        else
            newLine := findExpr '.' action '()`r`n'

        this.sciCtl.AppendText(StrLen(newLine), newLine)
    }

    /**
     * Build a WinTitle string for the captured window, suitable for ElementFromHandle.
     * Format: `<title> ahk_exe <name>`. Falls back to `ahk_id <hwnd>` if the title or
     * exe isn't readable (closed/elevated windows).
     */
    _GetWinTitle() {
        winTitle := ""
        try
        {
            hwnd := this.capturedHwnd
            if hwnd
            {
                title := WinGetTitle(hwnd)
                exe := ProcessGetName(WinGetPID(hwnd))
                winTitle := title " ahk_exe " exe
            }
        }
        if !winTitle
            winTitle := "ahk_id " this.capturedHwnd
        return winTitle
    }

    /**
     * Re-render the macro from scratch (via _GenerateMacroCode), drop it into the
     * Scintilla editor, and copy it to the clipboard. Sets `sciCtl.loading := 1` so
     * the syntax highlighter recolors the entire document instead of doing partial
     * updates — important after a full Text replace.
     */
    MacroCopy(*) {
        if !this.macroSteps.Length
        {
            this.sbMain.SetText("  No macro steps to copy")
            return
        }
        code := this._GenerateMacroCode()
        this.sciCtl.loading := 1  ; full-document load — tell DLL to recolor entire document
        this.sciCtl.Text := code
        A_Clipboard := code
        this.sbMain.SetText("  Copied macro (" this.macroSteps.Length " steps)")
    }

    ; ════════════════════════════════════════════
    ;  Macro persistence — save/load via JSON
    ; ════════════════════════════════════════════
    /**
     * Bound to Ctrl+Z. Pops the last macro step and re-renders the editor from
     * the remaining steps. **By design, this overwrites any hand-edits to the
     * Scintilla buffer** — the structured macroSteps array is the source of truth.
     * If the user wants to preserve edits, they should Copy first.
     */
    MacroRemoveLast(*) {
        if !this.macroSteps.Length
        {
            this.sbMain.SetText("  No macro steps to remove")
            return
        }
        removed := this.macroSteps.Pop()
        this._RerenderEditor()
        this.sbMain.SetText("  Removed: " removed.action " on " removed.condition "  —  " this.macroSteps.Length " step(s) remaining")
        this._UpdateControls()
    }

    /**
     * Replace the editor contents with a fresh render of the current macroSteps.
     * Shared by MacroRemoveLast and the anchor-rename flow. Sets `loading := 1` for
     * a full recolor pass.
     */
    _RerenderEditor() {
        this.sciCtl.loading := 1
        if this.macroSteps.Length
            this.sciCtl.Text := this._GenerateMacroCode()
        else
            this.sciCtl.Text := ""
    }

    /**
     * Generate the full AHK script that represents the current macroSteps.
     * Order: header → winEl assignment → anchor variable assignments (only those
     * actually used) → one line per step (FindFirst.Action() / WaitElement / SetValue),
     * with `Sleep 50` between each. Shared by MacroCopy and _RerenderEditor so the
     * "Copy" button and the "Undo" button can never produce divergent outputs.
     */
    _GenerateMacroCode() {
        winTitle := this._GetWinTitle()

        code := '#Requires AutoHotkey v2.0.2+`n'
        code .= '#Include ' this._UIAIncludePath() '`n`n'
        code .= 'winEl := UIA.ElementFromHandle("' winTitle '")`n`n'

        ; Emit anchor variable assignments (only those used in steps)
        emittedAnchors := Map()
        for i, step in this.macroSteps
        {
            anchorName := step.HasProp("anchor") ? step.anchor : ""
            if anchorName && !emittedAnchors.Has(anchorName) && this.anchorVars.Has(anchorName)
            {
                anchorDef := this.anchorVars[anchorName]
                code .= anchorName ' := winEl.FindFirst(' anchorDef.condition ')`n'
                emittedAnchors[anchorName] := true
            }
        }
        if emittedAnchors.Count
            code .= '`n'

        for i, step in this.macroSteps
        {
            anchorName := step.HasProp("anchor") ? step.anchor : ""
            baseVar    := anchorName ? anchorName : "winEl"
            mm         := step.HasProp("matchMode") ? step.matchMode : "Exact"
            sc         := step.HasProp("scopeText")  ? step.scopeText  : "Descendants"
            mmStr      := '"' mm '"'
            scopeStr   := sc != "Descendants" ? "UIA_TreeScope." sc : ""
            findArgs   := step.condition ", " mmStr (scopeStr ? ", " scopeStr : "")
            waitArgs   := step.condition ", " mmStr ", 5000" (scopeStr ? ", " scopeStr : "")

            if step.action = "SetValue"
                code .= baseVar '.FindFirst(' findArgs ').SetValue("")`n'
            else if step.action = "WaitElement"
                code .= baseVar '.WaitElement(' waitArgs ')`n'
            else
                code .= baseVar '.FindFirst(' findArgs ').' step.action '()`n'
            if i < this.macroSteps.Length
                code .= 'Sleep 50`n'
        }

        return code
    }

    /**
     * Save the current editor contents to a temp file, /Validate it for syntax, and
     * if it's clean, Run it. On a syntax error, surfaces the first line in the status
     * bar plus a 6-second tooltip with the full message. Does not capture stdout from
     * the running script — the test child is fire-and-forget.
     */
    MacroTest(*) {
        code := this.sciCtl.Text
        if !Trim(code)
        {
            this.sbMain.SetText("  Nothing in the editor to test")
            return
        }

        tempFile := A_Temp "\UIA_MacroTest.ahk"
        errFile  := A_Temp "\UIA_MacroTest_err.txt"

        if FileExist(tempFile)
            FileDelete(tempFile)
        if FileExist(errFile)
            FileDelete(errFile)

        FileAppend(code, tempFile, "UTF-8")

        ; --- validate syntax before launching ---
        exitCode := RunWait('"' A_AhkPath '" /ErrorStdOut /Validate "' tempFile '" 2>"' errFile '"',, "Hide")
        if exitCode != 0
        {
            errText   := FileExist(errFile) ? FileRead(errFile, "UTF-8") : "Unknown syntax error."
            firstLine := Trim(RegExReplace(errText, "\r?\n.*", "", , 1))
            if StrLen(firstLine) > 120
                firstLine := SubStr(firstLine, 1, 117) "..."
            this.sbMain.SetText("  Syntax error: " firstLine)
            ToolTip(errText)
            SetTimer(() => ToolTip(), -6000)
            return
        }

        ; Temporarily remove AlwaysOnTop so error dialogs aren't hidden
        if APP_SETTINGS.alwaysOnTop
        {
            this.gui.Opt("-AlwaysOnTop")
            triggers.ui.Opt("-AlwaysOnTop")
        }

        RunWait('"' A_AhkPath '" /ErrorStdOut "' tempFile '"')

        ; Restore AlwaysOnTop after test script finishes
        if APP_SETTINGS.alwaysOnTop
        {
            this.gui.Opt("+AlwaysOnTop")
            triggers.ui.Opt("+AlwaysOnTop")
        }
        this.sbMain.SetText("  Test complete: " tempFile)
    }

    /**
     * Hand-rolled parser for `{Key: "value", Other: 42}` literals — used to convert
     * the condition strings stored in macroSteps back into AHK objects so _CountMatches
     * can pass them to FindAll. Doesn't depend on cJson because the literal format isn't
     * valid JSON (unquoted keys). Returns an Object on success, or "" on parse failure.
     */
    _ParseConditionString(condStr) {
        condStr := Trim(condStr)
        if SubStr(condStr, 1, 1) != "{" || SubStr(condStr, -1) != "}"
            return ""
        inner := SubStr(condStr, 2, StrLen(condStr) - 2)
        condObj := {}
        pos := 1
        len := StrLen(inner)
        while pos <= len
        {
            ; Skip whitespace and commas
            while pos <= len && RegExMatch(SubStr(inner, pos, 1), "[\s,]")
                pos++
            if pos > len
                break
            ; Read key (up to colon)
            colonPos := InStr(inner, ":", , pos)
            if !colonPos
                return ""
            key := Trim(SubStr(inner, pos, colonPos - pos))
            pos := colonPos + 1
            ; Skip whitespace
            while pos <= len && SubStr(inner, pos, 1) = " "
                pos++
            if pos > len
                return ""
            ; Read value
            ch := SubStr(inner, pos, 1)
            if ch = '"'
            {
                ; Quoted string value
                pos++
                endQuote := InStr(inner, '"', , pos)
                if !endQuote
                    return ""
                val := SubStr(inner, pos, endQuote - pos)
                pos := endQuote + 1
            }
            else
            {
                ; Numeric or unquoted value
                endPos := InStr(inner, ",", , pos)
                if !endPos
                    endPos := len + 1
                val := Trim(SubStr(inner, pos, endPos - pos))
                if IsNumber(val)
                    val := Number(val)
                pos := endPos
            }
            condObj.%key% := val
        }
        return condObj
    }

    ; ════════════════════════════════════════════
    ;  Mouse Tracking — continuous element inspection
    ; ════════════════════════════════════════════
    /** F2 hotkey handler — flip continuous mouse-follow tracking on/off. */
    ToggleTracking(*) {
        if this.tracking
            this.StopTracking()
        else
            this.StartTracking()
    }

    /** Start the 100ms _TrackTick timer that re-inspects on every mouse move. */
    StartTracking() {
        this.tracking := true
        this.lastTrackRect := ""
        hk := triggers.gettrigger(TrackHotkeyFired)
        this.sbMain.SetText("  Tracking... move mouse over elements. Press " hk " to stop.")
        this.trackTimer := ObjBindMethod(this, "_TrackTick")
        SetTimer(this.trackTimer, 100)
    }

    /**
     * Stop tracking, do one final full Capture so the inspector lands in a clean
     * fully-populated state (tracking only does partial updates), then reactivate
     * our window so the user can keep working.
     */
    StopTracking() {
        this.tracking := false
        if this.trackTimer
        {
            SetTimer(this.trackTimer, 0)
            this.trackTimer := ""
        }
        this.CaptureFromMouse()
        WinActivate("ahk_id " this.gui.Hwnd)
    }

    /**
     * 100ms tick during tracking — read element under mouse, skip if it's the same
     * element as last tick (compared by bounding rect — much cheaper than RuntimeId),
     * else update Properties / Patterns / Highlight / Status bar. Skipped entirely
     * when the cursor is over our own GUI to prevent recursive inspection.
     */
    _TrackTick() {
        if !this.tracking
            return

        CoordMode("Mouse", "Screen")
        MouseGetPos(&mX, &mY, &winUnderMouse)

        ; Skip our own window
        if !winUnderMouse || winUnderMouse = this.gui.Hwnd
            return

        try
        {
            el := UIA.ElementFromPoint(mX, mY)
            if !el
                return

            ; Skip if same element (compare by bounding rect)
            try
            {
                newRect := el.BoundingRectangle
                rectKey := newRect.l "," newRect.t "," newRect.r "," newRect.b
                if rectKey = this.lastTrackRect
                    return
                this.lastTrackRect := rectKey
            }

            this.capturedElement := el

            ; Update window info if needed
            topWin := DllCall("GetAncestor", "ptr", winUnderMouse, "uint", 2, "ptr")
            this.PopulateWindowInfo(topWin)

            ; Update properties, patterns, highlight
            this.PopulateProperties(el)
            this.PopulatePatterns(el)
            this.StartHighlight()
            this.UpdateStatusBar()
        }
    }

    ; ════════════════════════════════════════════
    ;  Copy Helpers
    ; ════════════════════════════════════════════
    /**
     * Copy a one-line `winEl.FindFirst(condition).Action()` snippet to the clipboard,
     * picking the action automatically via _DetermineAction. Smaller cousin of
     * CopyFullSnippet — for users who already have a `winEl` defined in their script.
     */
    CopyFindFirstCode(*) {
        if !this.capturedElement
        {
            this.sbMain.SetText("  No element captured")
            return
        }
        condStr := this.BuildConditionString(this.capturedElement)
        action := this._DetermineAction(this.capturedElement)
        code := "winEl.FindFirst(" condStr ")." action
        A_Clipboard := code
        this.sbMain.SetText("  Copied: " code)
    }

    /**
     * Copy a complete, runnable AHK script to the clipboard:
     * `#Requires + #Include + winEl := … + winEl.FindFirst(…).Action()`.
     * @param el Optional override; defaults to the captured element. Used by the
     *           tree context menu to copy a snippet for any node, not just the captured one.
     */
    CopyFullSnippet(el?) {
        if !IsSet(el)
            el := this.capturedElement
        if !el
        {
            this.sbMain.SetText("  No element captured")
            return
        }
        condStr := this.BuildConditionString(el)
        action := this._DetermineAction(el)

        winTitle := ""
        try
        {
            hwnd := el.WinId
            if hwnd
            {
                title := WinGetTitle(hwnd)
                exe := ProcessGetName(WinGetPID(hwnd))
                winTitle := title " ahk_exe " exe
            }
        }
        if !winTitle
            winTitle := "ahk_id " (el.WinId || 0)

        code := '#Requires AutoHotkey v2.0.2+`n'
        code .= '#Include ' this._UIAIncludePath() '`n`n'
        code .= 'winEl := UIA.ElementFromHandle("' winTitle '")`n'
        code .= 'winEl.FindFirst(' condStr ').' action '`n'

        A_Clipboard := code
        this.sbMain.SetText("  Copied full snippet (" StrLen(code) " chars)")
    }

    /**
     * Build a breadcrumb-style path string from the root down to `el`, using each
     * node's GetLabel() representation joined with " › ". Capped at 40 levels to
     * defend against pathological cyclic providers.
     */
    _GetElementPath(el) {
        parts := []
        current := el
        loop 40 {
            try {
                parts.InsertAt(1, this.GetLabel(current))
                current := UIA.TreeWalkerTrue.GetParentElement(current)
                if !current
                    break
            } catch
                break
        }
        result := ""
        for i, part in parts
            result .= (i > 1 ? " › " : "") part
        return result
    }

    ; ════════════════════════════════════════════
    ;  Mouse monitor — update status bar with window under mouse
    ; ════════════════════════════════════════════
    /**
     * Background timer (500ms) — keeps the status bar's elevation/bitness indicators
     * in sync with whatever window the cursor is currently over. Three responsibilities:
     *   1. Update the "Browser/Admin/Normal" badge + colored background.
     *   2. Update the bitness ("32-bit"/"64-bit") badge.
     *   3. The first time the cursor enters an Admin-owned window while we're not
     *      elevated, prompt to relaunch as Admin (one prompt per unique PID).
     * Skips windows owned by our own process to avoid pestering on tooltips/dropdowns.
     */
    _MonitorMouseWindow() {
        CoordMode("Mouse", "Screen")
        MouseGetPos(,, &winHwnd)
        if !winHwnd
        {
            this._lastMonitorPid := 0
            return
        }

        ; Get the PID that owns this window (kernel-level, works for transient popups)
        DllCall("GetWindowThreadProcessId", "ptr", winHwnd, "uint*", &targetPid := 0)
        if !targetPid
            return

        ; Skip any window belonging to our own process (GUI, DDL popups, tooltips, dialogs)
        if targetPid = DllCall("GetCurrentProcessId")
        {
            this._lastMonitorPid := 0
            return
        }

        ; Only update when the window changes
        if targetPid = this._lastMonitorPid
            return
        this._lastMonitorPid := targetPid

        ; Part 2 — update status bar elevation/bitness indicators
        if IsBrowserProcess(targetPid)
        {
            this.sbMain.SetText("Browser", 2)
            this.sbMain.Opt("BackgroundDefault")
        }
        else if IsProcessElevated(targetPid)
        {
            this.sbMain.SetText("Admin", 2)
            this.sbMain.Opt("BackgroundRed")

            ; Part 3 — prompt to restart as admin (once per unique elevated process)
            if !A_IsAdmin && targetPid != this._lastAdminPromptPid
            {
                this._lastAdminPromptPid := targetPid
                this.gui.Opt("+OwnDialogs")
                try targetName := ProcessGetName(targetPid)
                catch
                    return
                choice := MsgBox(
                    targetName " is running as Admin.`n"
                    "UIA can't inspect elevated windows without Admin rights.`n`n"
                    "Restart Inspector as Admin?",
                    "Target is Elevated", "Y/N Icon!")
                if choice = "Yes"
                {
                    Run("*RunAs " A_ScriptFullPath)
                    ExitApp()
                }
            }
        }
        else
        {
            this.sbMain.SetText("Normal", 2)
            this.sbMain.Opt("BackgroundDefault")
        }

        ; Part 3 — update bitness indicator
        try
        {
            targetPath := ProcessGetPath(targetPid)
            this.sbMain.SetText(CheckExeBitness(targetPath), 3)
        }
        catch
            this.sbMain.SetText("?", 3)
    }

    ; ════════════════════════════════════════════
    ;  Status Bar — show element path/condition
    ; ════════════════════════════════════════════
    /**
     * Refresh the "Path matches" indicator showing how unique the captured element's
     * condition is. Green text for unique (1 match), red for ambiguous (>1 or 0).
     * Skipped during tracking — the live FindAll probe is too expensive to run on
     * every 100ms tick.
     * Also caches the count in `_lastMatchCount` so _UpdateGuide can decide whether
     * to suggest "Add element" or "create an anchor first".
     */
    UpdateStatusBar() {
        if !this.capturedElement
            return

        cond := this.BuildConditionString(this.capturedElement)

        ; Skip the live FindAll probe while tracking — the 100ms tracking timer
        ; can't afford a full-tree search on every tick.
        if this.tracking
        {
            this.editTarget.Value := ""
            this.editTarget.Opt("+cBlack")
            this.editTarget.Redraw()
            return
        }

        count := this._CountMatches(cond)
        this._lastMatchCount := count
        this.editTarget.Value := this._FormatMatchCount(count)
        ; Green when the condition uniquely identifies one element, red otherwise
        this.editTarget.Opt(count = 1 ? "+c008000" : "+cC00000")
        this.editTarget.Redraw()
        if this.HasProp("btnFindUnique")
            this.btnFindUnique.Enabled := this.capturedElement && count > 1
        this._UpdateGuide()
    }

    /**
     * Build a `{Type: "X", AutomationId: "Y"}` literal for `el`, picking the most
     * stable identifier available and short-circuiting on the first hit:
     *   1. AutomationId — gold standard (WinUI numeric IDs accepted as strings).
     *   2. Name         — localized but usually stable within an app version.
     *   3. ClassName    — last resort, only for legacy Win32 controls.
     * All string values are passed through _EscapeStr so embedded quotes don't
     * break the generated code. @returns "{}" when nothing identifying is available.
     */
    BuildConditionString(el) {
        parts := []

        ; Always include Type if resolvable
        try {
            typeId := el.Type
            typeName := UIA_Type.HasValue(typeId)
            if typeName
                parts.Push('Type: "' typeName '"')
        }

        ; AutomationId — best identifier; early return the moment we have one
        try {
            aid := el.AutomationId
            if aid != "" {
                parts.Push('AutomationId: "' this._EscapeStr(String(aid)) '"')
                return "{" this._Join(parts) "}"
            }
        }

        ; Name — next best
        try {
            name := el.Name
            if name {
                parts.Push('Name: "' this._EscapeStr(name) '"')
                return "{" this._Join(parts) "}"
            }
        }

        ; ClassName — fallback
        try {
            cn := el.ClassName
            if cn
                parts.Push('ClassName: "' this._EscapeStr(cn) '"')
        }

        if !parts.Length
            return "{}"
        return "{" this._Join(parts) "}"
    }

    /**
     * Pick a sensible default action for `el` by probing pattern availability in priority
     * order: Invoke → Toggle → ExpandCollapse (chooses Expand or Collapse based on
     * current state) → Value (SetValue("")) → SelectionItem.Select. Falls back to Click().
     * @returns A fully-formed AHK expression like `Invoke()` or `SetValue("")`.
     */
    _DetermineAction(el) {
        try {
            if el.GetPropertyValue(30031)  ; Invoke
                return "Invoke()"
        }
        try {
            if el.GetPropertyValue(30041)  ; Toggle
                return "Toggle()"
        }
        try {
            if el.GetPropertyValue(30028) { ; ExpandCollapse
                state := el.GetPattern("ExpandCollapse").ExpandCollapseState
                return state = 0 ? "Expand()" : "Collapse()"
            }
        }
        try {
            if el.GetPropertyValue(30043)  ; Value pattern
                return 'SetValue("")'
        }
        try {
            if el.GetPropertyValue(30036)  ; SelectionItem
                return "Select()"
        }
        return "Click()"
    }

    ; ════════════════════════════════════════════
    ;  AI buttons — Find Unique / Ask AI
    ; ════════════════════════════════════════════
    /**
     * Find Unique — send the UIA tree + selected element to DeepSeek and ask
     * for a resilient AHK v2 UIA snippet that uniquely targets the element.
     * Only meaningful when _lastMatchCount > 1.
     */
    OnFindUnique() {
        if !this.capturedElement {
            MsgBox("Capture an element first (F1).", "Find Unique", "Iconi")
            return
        }
        if this._lastMatchCount <= 1 {
            MsgBox("The current condition already matches exactly " this._lastMatchCount " element(s).", "Find Unique", "Iconi")
            return
        }

        scope := AIContext.PickScope()
        if scope = ""
            return

        sbText := ""
        try sbText := this.sbMain.GetText(1)
        this.btnFindUnique.Enabled := false
        this.btnFindUnique.Text := "Thinking…"
        busy := this._ShowAIBusy("Asking AI for a unique UIA selector…")
        Sleep(1)   ; let the GUI paint before the blocking HTTP call

        try {
            summary  := AIContext.BuildElementSummary(this)
            tree     := AIContext.BuildTreeSnippet(this, scope)
            ancPath  := AIContext.BuildAncestorPath(this)

            sys :=
              "You are an AHK v2 UIA expert targeting the Descolada UIA-v2 library (S:\lib\v2\UIA2\UIA\UIA.ahk).`n"
            . "Your job: given a selected Windows UI element, its window, its supported patterns, and a slice of the UIA tree, return an AHK v2 snippet that UNIQUELY targets the selected element.`n`n"
            . "API RULES — use these EXACT method names and argument shapes:`n"
            . "  - FindFirst(condition [, matchMode, scope])   -> returns first match or throws if none.`n"
            . "  - FindAll(condition [, matchMode, scope])     -> returns an array; use [index] to pick one.`n"
            . "  - DO NOT use FindElement / FindElements / TreeWalker / FindFirstBuildCache.`n"
            . "  - condition is an object literal of UIA properties, e.g.  {Type:'Button', Name:'OK'}  or  {AutomationId:'submitBtn'}.`n"
            . "    Use CamelCase UIA property names only: Type, Name, AutomationId, ClassName, LocalizedControlType.`n"
            . "    Do NOT use web/ARIA role names like RootWebArea, landmark, generic — those are not UIA control types.`n"
            . "    Valid Type values: Button, Edit, Text, CheckBox, RadioButton, ComboBox, List, ListItem, TreeItem, Pane, Group, Document, Image, Hyperlink, Window, MenuItem, Tab, TabItem, DataItem, ToolBar, StatusBar, Custom, etc.`n"
            . "  - matchMode (string): '2' or 2 for contains, '1' or 1 for startswith; default exact.`n"
            . "  - scope  : omit for default Descendants, or pass UIA.TreeScope.Children / UIA.TreeScope.Subtree / UIA.TreeScope.Element.`n"
            . "  - Assume `winEl` already exists: winEl := UIA.ElementFromHandle(hwnd).`n"
            . "  - Highlight the found element at the end with .Highlight() so the user can visually verify.`n`n"
            . "CRITICAL — picking the right anchor:`n"
            . "  - In the tree, lines prefixed with '==>' are ancestors of the SELECTED element. The line ending in '<<< SELECTED' is the exact target.`n"
            . "  - Only use '==>' lines as anchors. NEVER anchor on a sibling — sibling lines are explicitly marked '(sibling of ancestor — NOT on selected path)'.`n"
            . "  - Example: if three Tiles (A, B, C) exist and only Tile B has '==>', then Tile B is the correct parent; Tiles A and C are siblings and must NOT be used.`n`n"
            . "STRATEGY — pick the simplest one that resolves to exactly ONE match:`n"
            . "  1. If the SELECTED element itself has a unique AutomationId, use it directly:   winEl.FindFirst({AutomationId:'...'})`n"
            . "  2. Else chain from a '==>' ancestor that itself uniquely identifies (Name or AutomationId):`n"
            . "       anchor := winEl.FindFirst({Type:'Document', Name:'<==> ancestor Name>'})`n"
            . "       btn    := anchor.FindFirst({Type:'Button', Name:'Save'})`n"
            . "  3. Else, if the selected element is the Nth among identical siblings, use FindAll with the right index:`n"
            . "       btn := winEl.FindAll({Type:'Button', Name:'Save'})[N]`n`n"
            . "OUTPUT PREAMBLE — the inspector already emits `#Include` and the `winEl := UIA.ElementFromHandle(...)` line. DO NOT emit those — start your snippet directly with a variable assignment or `winEl.FindFirst(...)`.`n"
            . "OUTPUT RULES:`n"
            . "  - Output ONLY AHK v2 code, no markdown fences, no prose outside `;` comments.`n"
            . "  - Start with ONE `;` strategy comment, then the code.`n"
            . "  - End with `.Highlight()` on the final element so the user can confirm the match visually."

            user :=
              "CONTEXT`n=======`n" summary
            . "`n`n=== AUTHORITATIVE ANCESTOR PATH (root -> selected) ===`n" ancPath
            . "`n`n" tree
            . "`n`nTASK`n====`n"
            . "Write an AHK v2 UIA snippet that resolves to EXACTLY ONE match for the SELECTED element.`n"
            . "MANDATORY: any anchor you choose must appear in the AUTHORITATIVE ANCESTOR PATH above — that list is the ground truth. Do not pick anchors that only appear in the tree dump outside this path; those are siblings/cousins and will target the WRONG element."

            messages := [
                {role: "system", content: sys},
                {role: "user",   content: user}
            ]

            reply := CallOpenRouter(this._aiModel, messages)
            try busy.Destroy()
            this._AppendAISuggestion(reply)
            this.sbMain.SetText("  AI suggestion appended to the editor — click Test to verify.")

        } catch Error as err {
            try busy.Destroy()
            MsgBox("Find Unique failed:`n`n" err.Message, "DeepSeek error", "Iconx")
            this.sbMain.SetText(sbText)
        }

        this.btnFindUnique.Text := "Find Unique"
        this.btnFindUnique.Enabled := this.capturedElement && this._lastMatchCount > 1
        this._UpdateControls()
    }

    /**
     * Ask AI — open (or re-show) a persistent chat GUI seeded with the current
     * element + tree context. User drives the conversation.
     */
    OnAskAI() {
        if !this.capturedElement {
            MsgBox("Capture an element first (F1).", "Ask AI", "Iconi")
            return
        }
        if !this._askAIChat
            this._askAIChat := AskAIChat(this, this._aiModel)
        this._askAIChat.RefreshContext()
        this._askAIChat.Show()
    }

    /**
     * Show a small always-on-top "Contacting AI…" dialog. Returns the Gui so the
     * caller can .Destroy() it when the sync call returns. The GUI also paints a
     * brief message on the status bar so the main window visibly changes state.
     */
    _ShowAIBusy(title := "Contacting AI…") {
        g := Gui("+AlwaysOnTop +ToolWindow -SysMenu", "AI")
        g.SetFont("s10", "Segoe UI")
        g.BackColor := 0x202830
        g.AddText("xm ym w280 h30 cFFFFFF Center +0x200", title)
        g.AddText("xm y+4 w280 h18 c808080 Center +0x200", "This can take a few seconds…")
        ; Center over the inspector window
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " this.gui.Hwnd)
            g.Show("w300 h70 x" (wx + (ww - 300)//2) " y" (wy + (wh - 70)//2))
        } catch
            g.Show("w300 h70")
        this.sbMain.SetText("  " title)
        return g
    }

    /** Ensure the editor has `#Requires + #Include + winEl := …` before any user
     *  code. Idempotent — no-op if the current text already defines them.
     */
    _EnsureMacroHeader() {
        code := this.sciCtl.Text
        needsHeader := !InStr(code, "#Include")
        needsWinEl  := !InStr(code, "ElementFromHandle")
        if !needsHeader && !needsWinEl
            return
        winTitle := this._GetWinTitle()
        header := ""
        if needsHeader {
            header .= "#Requires AutoHotkey v2.0.2+`r`n"
            header .= "#Include " this._UIAIncludePath() "`r`n`r`n"
        }
        if needsWinEl
            header .= 'winEl := UIA.ElementFromHandle("' winTitle '")`r`n`r`n'
        if code = ""
            this.sciCtl.AppendText(StrLen(header), header)
        else
            this.sciCtl.InsertText(0, header)
        this._lastMacroWinTitle := winTitle
    }

    /** Append an AI-generated snippet to the Scintilla editor with markers.
     *  Emits the header if missing, then strips any duplicate prelude lines the
     *  AI may have included (directives, `winEl := ...`, markdown fences).
     */
    _AppendAISuggestion(text) {
        this._EnsureMacroHeader()

        cleaned := ""
        for line in StrSplit(text, "`n", "`r") {
            trimmed := Trim(line)
            ; Skip markdown fences (triple backtick — built via Chr to avoid escape-quoting issues)
            if SubStr(trimmed, 1, 3) = Chr(96) Chr(96) Chr(96)
                continue
            ; Skip #Requires / #Include / #SingleInstance directives
            if RegExMatch(trimmed, "i)^#(Requires|Include|SingleInstance)\b")
                continue
            ; Skip winEl := UIA.ElementFromHandle(...) — the inspector already wrote it
            if RegExMatch(trimmed, "i)^winEl\s*:=\s*UIA\.ElementFromHandle\b")
                continue
            cleaned .= line "`n"
        }
        cleaned := Trim(cleaned, "`r`n")

        stamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        block := "`n; ─── AI suggestion (" stamp ") ───`n" cleaned "`n; ─── end ───`n"
        try
            this.sciCtl.AppendText(StrLen(block), block)
        catch
            this.sciCtl.Text := this.sciCtl.Text . block
    }

    ; ════════════════════════════════════════════
    ;  Tree Events
    ; ════════════════════════════════════════════
    /** Tree click — re-inspect the clicked element and refresh anchor points. */
    OnTreeClick(tvItem) {
        if !tvItem || !this.treeViewMap.Has(tvItem)
            return

        el := this.treeViewMap[tvItem]
        this._SelectTreeNode(tvItem)
        this.PopulateAnchorPoints()
    }

    /**
     * Right-click on a tree node — pop a context menu with five copy-to-clipboard
     * variants (Condition / FindFirst / Full snippet / Path) plus a "Highlight" pulse.
     */
    OnTreeContext(tvItem) {
        if !tvItem || !this.treeViewMap.Has(tvItem)
            return

        el := this.treeViewMap[tvItem]
        condStr := this.BuildConditionString(el)
        action := this._DetermineAction(el)

        ctxMenu := Menu()
        ctxMenu.Add("Copy Condition", (*) => (A_Clipboard := condStr, this.sbMain.SetText("  Copied: " condStr)))
        ctxMenu.Add("Copy FindFirst", (*) => (A_Clipboard := "winEl.FindFirst(" condStr ")." action, this.sbMain.SetText("  Copied FindFirst")))
        ctxMenu.Add("Copy Full Snippet", (*) => this.CopyFullSnippet(el))
        ctxMenu.Add("Copy Path from Root", (*) => (A_Clipboard := this._GetElementPath(el), this.sbMain.SetText("  Copied path from root")))
        ctxMenu.Add()
        ctxMenu.Add("Highlight", (*) => this.BlinkHighlight(el))
        ctxMenu.Show()
    }

    ; ════════════════════════════════════════════
    ;  ListView context menu — copy cell text
    ; ════════════════════════════════════════════
    /**
     * Click/right-click handler shared by the Window Info and Properties ListViews.
     * Always copies column 2 (the value) — column 1 is just a label.
     */
    LVCopyText(lv, item) {
        if !item
            return
        text := lv.GetText(item, 2) ; get value column
        A_Clipboard := text
        this.sbMain.SetText("  Copied: " text)
        this._FlashCopyTip(text)
    }

    /** Flash a 800ms tooltip confirming what was just copied. Uses tooltip slot 2. */
    _FlashCopyTip(text) {
        ToolTip('Copied: "' text '"', , , 2)
        SetTimer(() => ToolTip(, , , 2), -800)
    }


    ; ════════════════════════════════════════════
    ;  Recording — capture clicks as code steps
    ; ════════════════════════════════════════════
    /** Escape `"` → `\"` so a string can be safely embedded in a generated `"..."` literal. */
    _EscapeStr(s) => StrReplace(s, '"', '``"')

    /** Join an array with `, ` — used to assemble condition-object key:value pairs. */
    _Join(arr) {
        result := ""
        for i, v in arr {
            if i > 1
                result .= ", "
            result .= v
        }
        return result
    }

    ; ════════════════════════════════════════════
    ;  Diagnostic logging — element not found in tree
    ; ════════════════════════════════════════════
    /**
     * Append a deep diagnostic dump to UIA_Inspector.log when SelectCapturedInTree
     * fails to find an element it should have found. Records the target's identifying
     * properties, the parent chain (so we can see where the chain diverges from the
     * tree root), and the first 20 tree entries for visual comparison.
     * Only invoked manually during dev — not part of normal flow.
     */
    _LogTreeMiss(el, aid := "") {
        logFile := A_ScriptDir "\UIA_Inspector.log"

        ; Info about the target element
        targetType := "", targetName := "", targetClass := "", targetRect := ""
        try targetType := el.Type
        try targetName := el.Name
        try targetClass := el.ClassName
        try
        {
            r := el.BoundingRectangle
            targetRect := r.l "," r.t "," r.r "," r.b
        }
        targetHwnd := 0
        try targetHwnd := el.NativeWindowHandle
        targetWinId := 0
        try targetWinId := el.WinId

        log := "═══ TREE MISS " FormatTime(, "yyyy-MM-dd HH:mm:ss") " ═══`n"
        log .= "TARGET element:`n"
        log .= "  AutomationId : " aid "`n"
        log .= "  Type         : " targetType "`n"
        log .= "  Name         : " targetName "`n"
        log .= "  ClassName    : " targetClass "`n"
        log .= "  Rect         : " targetRect "`n"
        log .= "  HWND         : " Format("0x{:X}", targetHwnd) "`n"
        log .= "  WinId        : " Format("0x{:X}", targetWinId) "`n"

        ; Info about the tree
        log .= "TREE state:`n"
        log .= "  treeViewMap count: " this.treeViewMap.Count "`n"

        ; Check what the tree root window is
        rootHwnd := 0
        try rootHwnd := this.capturedWindowEl.NativeWindowHandle
        log .= "  Tree root HWND   : " Format("0x{:X}", rootHwnd) "`n"

        ; Walk parents of target to see if any match tree root
        log .= "PARENT CHAIN of target:`n"
        walker := el
        depth := 0
        loop 10
        {
            try
                walker := walker.Parent
            catch
                break
            if !walker
                break
            depth++
            pType := "", pName := "", pAid := "", pHwnd := 0
            try pType := walker.Type
            try pName := walker.Name
            try pAid := walker.AutomationId
            try pHwnd := walker.NativeWindowHandle
            log .= "  [" depth "] Type:" pType " Name:`"" pName "`" AID:`"" pAid "`" HWND:" Format("0x{:X}", pHwnd) "`n"
        }

        ; Dump first 20 tree entries for comparison
        log .= "TREE ENTRIES (first 20):`n"
        count := 0
        for tvItem, tvEl in this.treeViewMap
        {
            if ++count > 20
                break
            tType := "", tName := "", tAid := "", tRect := ""
            try tType := tvEl.Type
            try tName := tvEl.Name
            try tAid := tvEl.AutomationId
            try
            {
                r := tvEl.BoundingRectangle
                tRect := r.l "," r.t "," r.r "," r.b
            }
            log .= "  Type:" tType " Name:`"" tName "`" AID:`"" tAid "`" Rect:" tRect "`n"
        }
        log .= "`n"

        FileAppend(log, logFile)
        FileAppend(log, "*")  ; also to stdout
    }

    ; ════════════════════════════════════════════
    ;  Exit
    ; ════════════════════════════════════════════
    /**
     * Apply a VS Code Dark+ inspired syntax theme to the Scintilla macro editor.
     * Emphasizes the parts the user actually edits — strings (conditions, window
     * titles, values) and methods (actions) — while toning down boilerplate
     * directives and punctuation. Sets defaults first then ClearAll() so every style
     * inherits the dark background.
     */
    _ApplyMacroTheme()
    {
        sc := this.sciCtl.cust

        ; Set default first, then ClearAll so every style inherits this background
        ; (otherwise keyword/string/number styles keep the old near-black back).
        sc.Editor.Back := 0x1E1E1E
        sc.Editor.Fore := 0xD4D4D4
        sc.Editor.Font := "Consolas"
        sc.Editor.Size := 12
        this.sciCtl.Style.ClearAll()

        sc.Caret.LineBack  := 0x2A2D2E
        sc.Caret.Fore      := 0xAEAFAD
        sc.Margin.Back     := 0x252526
        sc.Margin.Fore     := 0x858585
        sc.Selection.Back  := 0x264F78

        sc.Comment1.Fore   := 0x6A9955
        sc.Comment2.Fore   := 0x6A9955
        sc.String1.Fore    := 0xCE9178  ; "..."  — conditions, window titles, values (the stuff you edit)
        sc.String2.Fore    := 0xCE9178  ; '...'
        sc.Number.Fore     := 0xB5CEA8  ; sleep delays, timeouts

        sc.Brace.Fore      := 0xD4D4D4
        sc.BraceH.Fore     := 0xFFD700  ; matched brace — gold
        sc.BraceHBad.Fore  := 0xF44747
        sc.Punct.Fore      := 0xD4D4D4

        sc.kw1.Fore := 0xC586C0  ; flow control (if/else/return/loop) — purple
        sc.kw2.Fore := 0xDCDCAA  ; functions (Sleep, ElementFromHandle) — pale yellow
        sc.kw3.Fore := 0xDCDCAA  ; methods (FindFirst, Click, SetValue) — pale yellow
        sc.kw4.Fore := 0x9CDCFE  ; properties — light blue
        sc.kw5.Fore := 0x4FC1FF  ; built-in vars (A_*) — bright blue
        sc.kw6.Fore := 0xC586C0  ; directives (#Include, #Requires) — purple
        sc.kw7.Fore := 0x569CD6  ; var decl — blue
    }

    /**
     * Disable Scintilla during a long-running operation (capture, filter rebuild).
     * Removes our WM_NOTIFY filter callback AND grays the control. Without this, the
     * Scintilla DLL can re-enter our handlers mid-COM-call and crash.
     */
    _DisableScintilla() {
        try
        {
            if this.HasOwnProp("_sciFilteredCb")
                OnMessage(0x4E, this._sciFilteredCb, 0)
            if this.HasOwnProp("sciCtl")
                this.sciCtl.Opt("+Disabled")
        }
    }

    /** Re-enable Scintilla — re-adds the WM_NOTIFY filter and ungrays the control. */
    _EnableScintilla() {
        try
        {
            if this.HasOwnProp("_sciFilteredCb")
                OnMessage(0x4E, this._sciFilteredCb)
            if this.HasOwnProp("sciCtl")
                this.sciCtl.Opt("-Disabled")
        }
    }

    /** Permanent cleanup — drop the WM_NOTIFY filter on exit/error. */
    _CleanupScintilla() {
        try
        {
            if this.HasOwnProp("_sciFilteredCb")
                OnMessage(0x4E, this._sciFilteredCb, 0)
        }
    }

    ; ════════════════════════════════════════════
    ;  Resolve the best available HWND for a UIA element
    ; ════════════════════════════════════════════
    /**
     * Find the most useful HWND for a UIA element via a 3-step fallback:
     *   1. el.NativeWindowHandle — non-zero only for proper Win32 controls.
     *   2. For browser processes, return capturedHwnd unchanged — every page element
     *      shares one Chrome_RenderWidgetHostHWND, so DeepChildFromPoint is useless.
     *   3. Otherwise, walk child windows from capturedHwnd to the element's centre
     *      via _DeepChildFromPoint and return whatever we land on.
     * @returns Window handle, or 0 if nothing resolves.
     */
    _ResolveElementHwnd(el) {
        ; Step 1 — NativeWindowHandle (non-zero only for Win32 controls)
        try {
            h := el.NativeWindowHandle
            if h
                return h
        }

        ; Step 2 — walk child windows from the captured root down to element centre
        ; Skip for browsers: all page elements share Chrome_RenderWidgetHostHWND,
        ; so DeepChildFromPoint would return the same render surface for everything.
        try {
            pid := WinGetPID("ahk_id " this.capturedHwnd)
            if IsBrowserProcess(pid)
                return this.capturedHwnd   ; return root — at least it's stable
        }

        try {
            rect := el.BoundingRectangle
            screenX := rect.l + (rect.r - rect.l) // 2
            screenY := rect.t + (rect.b - rect.t) // 2
            parentHwnd := this.capturedHwnd
            if parentHwnd
                return this._DeepChildFromPoint(parentHwnd, screenX, screenY)
        }

        return 0
    }

    /**
     * Recursively descend through child HWNDs at the given screen point until a leaf
     * is found. Uses ChildWindowFromPointEx with CWP_SKIPINVISIBLE so transparent
     * overlays don't intercept the lookup.
     */
    _DeepChildFromPoint(parentHwnd, screenX, screenY) {
        pt := Buffer(8)
        NumPut("Int", screenX, "Int", screenY, pt)
        DllCall("ScreenToClient", "Ptr", parentHwnd, "Ptr", pt)
        clientX := NumGet(pt, 0, "Int")
        clientY := NumGet(pt, 4, "Int")
        child := DllCall("ChildWindowFromPointEx", "Ptr", parentHwnd,
                         "Int", clientX, "Int", clientY,
                         "UInt", 0x0001,   ; CWP_SKIPINVISIBLE
                         "Ptr")
        if child && child != parentHwnd
            return this._DeepChildFromPoint(child, screenX, screenY)
        return parentHwnd
    }

    /**
     * OnExit handler — clean up the Scintilla WM_NOTIFY filter, persist window
     * position (if RememberPos is on), persist the tips-disabled flag.
     */
    _OnExit(reason, code) {
        this._CleanupScintilla()
        PrefUI.SavePosition(this.gui.Hwnd)
        try IniWrite(this.tipsDisabled, A_ScriptDir "\UIA_Inspector_settings.ini", "Settings", "TipsDisabled")
    }

    /**
     * Global OnError handler — drop the Scintilla filter so the error dialog can
     * paint, then return 0 to let AHK display the error normally.
     */
    _OnError(err, mode) {
        this._CleanupScintilla()
        return 0
    }

    /**
     * Full graceful shutdown: stop monitor/tracking timers, hide highlights, unregister
     * window-scoped hotkeys, then ExitApp. Wired to the Gui Close event in __New.
     */
    Exit() {
        this._CleanupScintilla()
        if this._monitorTimer
            SetTimer(this._monitorTimer, 0)
        if this.tracking
            this.StopTracking()
        this.StopCapture()
        this._ClearGuideHighlight()
        try
        {
            ; Hotkey("F2", "Off")
            Hotkey("NumpadAdd", "Off")
            Hotkey("NumpadSub", "Off")
            Hotkey("^i", "Off")
            Hotkey("^z", "Off")

        }
        ExitApp()
    }

    ; ════════════════════════════════════════════
    ;  Mouse-over tips
    ; ════════════════════════════════════════════
    /**
     * WM_MOUSEMOVE (0x200) handler — show a context-sensitive tooltip when the cursor
     * lingers over a registered control. Tip text comes from `tipMap`, which is built
     * lazily on first hover (we need every control's HWND to exist first). After 3s
     * the tip auto-hides; the same tip won't reappear until the cursor leaves and
     * comes back, so it doesn't keep popping up while you mouse around.
     * The whole system is gated by tipsDisabled — toggled via the tray menu.
     */
    _checkTooltip(wParam, lParam, msg, hwndWin) {
        if this.tipsDisabled {
            if this.lastTipHwnd != 0 {
                this.lastTipHwnd := 0
                this.dismissedTipHwnd := 0
                SetTimer(this._tipHideFn, 0)
                Notify.CloseAll()
            }
            return
        }

        if !hwndWin
            return

        topParent := DllCall("GetAncestor", "Ptr", hwndWin, "UInt", 2, "Ptr")
        if (topParent != this.gui.Hwnd && hwndWin != this.gui.Hwnd)
            return

        ctrlHwnd := 0
        MouseGetPos(, , , &ctrlHwnd, 2)
        if !ctrlHwnd
            ctrlHwnd := hwndWin

        ; Lazy-init: build tip map on first hover (all HWNDs are registered by now)
        if !IsObject(this.tipMap) {
            this.tipMap := Map()
            this.tipMap[this.lvWin.Hwnd]             := {HD: "Window Info",        BD: "Captured window: Title, Class, HWND, PID, and Size."}
            this.tipMap[this.chkShowAllProps.Hwnd]   := {HD: "Show All Properties", BD: "Toggle between important properties only and all available UIA properties."}
            this.tipMap[this.lvProps.Hwnd]           := {HD: "Element Properties", BD: "UIA properties of the selected element.`nRight-click a row to copy the value."}
            this.tipMap[this.btnRefreshAnchors.Hwnd] := {HD: "Refresh Anchors",    BD: "Re-scan the captured window to update the Anchor Points list."}
            this.tipMap[this.tvAnchors.Hwnd]         := {HD: "Anchor Points",      BD: "Named anchor points for macro chaining.`nClick to inspect the element; right-click for options."}
            this.tipMap[this.tvPatterns.Hwnd]        := {HD: "Control Patterns",   BD: "UIA control patterns supported by the element.`nDouble-click a ▶ leaf to fire the action on the captured element."}
            this.tipMap[this.tvUIA.Hwnd]             := {HD: "UIA Tree",           BD: "Click a node to inspect; right-click to generate code.`nNumpadAdd=child  NumpadSub=parent  ↑↓=siblings  Ctrl+I=jump to AutomationId"}
            this.tipMap[this.chkDeepScan.Hwnd]       := {HD: "Deep Scan",          BD: "Full recursive tree scan.`nSlower, but reveals all descendants including off-screen elements."}
            this.tipMap[this.editElemCount.Hwnd]     := {HD: "Element Count",      BD: "Total UIA elements in the captured window's tree.`nRead-only — updates after each capture or refresh."}
            this.tipMap[this.editFilter.Hwnd]        := {HD: "Tree Filter",        BD: "Filter the UIA tree by element name or type.`nType to highlight matching nodes."}
            this.tipMap[this.ddlAction.Hwnd]         := {HD: "Action",             BD: "UIA action to perform on the selected element when building a macro step."}
            this.tipMap[this.edtIndex.Hwnd]          := {HD: "Match Index",        BD: "Which match to use when the condition resolves to multiple elements.`n1 = first match (default); use the spinner or type a number."}
            this.tipMap[this.udIndex.Hwnd]           := {HD: "Index Spinner",      BD: "Bumps the # field up or down.`nRange auto-adjusts to the current match count."}
            this.tipMap[this.sbMain.Hwnd]            := {HD: "Status Bar",         BD: "Shows the current match count, last action result, and AI feedback."}
            this.tipMap[this.ddlAnchor.Hwnd]         := {HD: "Anchor",             BD: "Anchor point to scope the element search during macro execution.`nRight-click to delete or rename stored anchor variables."}
            this.tipMap[this.ddlMatchMode.Hwnd]      := {HD: "Match Mode",         BD: "How the element Name is matched.`nExact = full string; Contains = anywhere; StartsWith / EndsWith = partial."}
            this.tipMap[this.ddlScope.Hwnd]          := {HD: "Search Scope",       BD: "Where in the tree to search.`nDescendants = all levels (default); Children = direct children only."}
            this.tipMap[this.btnKeys.Hwnd]           := {HD: "Hotkeys Legend",     BD: "Show/hide the hotkeys legend (F1 capture, F2 track, tree navigation)."}
            this.tipMap[this.editTarget.Hwnd]        := {HD: "Path Matches",       BD: "How many elements the current condition matches.`n1 = uniquely targeted; >1 = ambiguous (use Find Unique)."}
            this.tipMap[this.btnFindUnique.Hwnd]     := {HD: "Find Unique (AI)",   BD: "Ask the AI to refine the current selector so it targets exactly ONE element.`nUses ancestors with Name/AutomationId or indexed FindAll as a last resort.`nEnabled only when the condition matches more than one element."}
            this.tipMap[this.btnAskAI.Hwnd]          := {HD: "Ask AI",             BD: "Open a persistent AI chat seeded with the captured element, its window,`nUIA tree slice and supported patterns. Ask follow-ups, request alternative`nselectors, or have the AI explain why a match is failing."}
            this.tipMap[this.btnAddElement.Hwnd]     := {HD: "Add Element",        BD: "Add the current element + action as a step in the macro script."}
            this.tipMap[this.btnCopyMacro.Hwnd]      := {HD: "Copy Macro",         BD: "Copy the generated macro script to the clipboard."}
            this.tipMap[this.btnTestMacro.Hwnd]      := {HD: "Test Macro",         BD: "Run the macro script immediately to test it."}
            this.tipMap[this.btnClearMacro.Hwnd]     := {HD: "Clear Macro",        BD: "Clear all macro steps and reset the code editor."}
            this.tipMap[this.btnClearInspector.Hwnd] := {HD: "Clear Inspector",    BD: "Clear the captured element, tree, properties, anchors and patterns."}
            this.tipMap[this.sciCtl.Hwnd]            := {HD: "Macro Code",         BD: "Generated AHK macro code.`nEdit directly or copy to your script."}
            if this.tipMap.Has(0)
                this.tipMap.Delete(0)
            this._mapLabelHwnds()
        }

        if this.tipMap.Has(ctrlHwnd) {
            if (ctrlHwnd = this.dismissedTipHwnd)
                return                            ; already auto-hidden — wait for cursor to leave
            if (ctrlHwnd != this.lastTipHwnd) {   ; new control — show tip
                this.lastTipHwnd := ctrlHwnd
                this.dismissedTipHwnd := 0
                Notify.CloseAll()                  ; clear any prior notice
                tip := this.tipMap[ctrlHwnd]
                Notify.Show({HDText: tip.HD, BDText: tip.BD})
                SetTimer(this._tipHideFn, -3000)  ; mark dismissed in sync with notify auto-close
            }
        } else if this.lastTipHwnd != 0 {
            this.lastTipHwnd := 0
            this.dismissedTipHwnd := 0
            SetTimer(this._tipHideFn, 0)          ; cancel pending dismissal mark
            Notify.CloseAll()                      ; hide immediately
        }
    }

    /** Fires 3s after a tip appears — Notify already self-closed, just record HWND so the same tip stays hidden until the cursor leaves. */
    _hideTip() {
        Notify.CloseAll()
        this.dismissedTipHwnd := this.lastTipHwnd
    }

    /**
     * Mirror tip text from a control onto its preceding Static label, so hovering
     * the label shows the same tip as hovering the control. Walks all child HWNDs of
     * the main GUI in z-order and pairs each Static with the next non-Static control.
     */
    _mapLabelHwnds() {
        prevHwnd := 0
        prevIsStatic := false
        childHwnd := DllCall("GetWindow", "Ptr", this.gui.Hwnd, "UInt", 5, "Ptr")  ; GW_CHILD=5
        while (childHwnd) {
            className := ""
            try className := WinGetClass("ahk_id " childHwnd)
            isStatic := InStr(className, "Static") ? true : false

            if (prevIsStatic && prevHwnd && this.tipMap.Has(childHwnd) && !this.tipMap.Has(prevHwnd))
                this.tipMap[prevHwnd] := this.tipMap[childHwnd]

            prevHwnd     := childHwnd
            prevIsStatic := isStatic
            childHwnd    := DllCall("GetWindow", "Ptr", childHwnd, "UInt", 2, "Ptr")  ; GW_HWNDNEXT=2
        }
    }

    /**
     * Build the GUI window title — includes the live capture + track hotkeys so the
     * user always sees what to press, even after rebinding via Preferences.
     */
    _BuildWindowTitle() {
        capHk := triggers.gettrigger(CaptureHotkeyFired)
        trkHk := triggers.gettrigger(TrackHotkeyFired)
        admin := A_IsAdmin ? " (Admin)" : ""
        return "UIA Inspector" admin "  —  " capHk " = Capture element under mouse  ·  " trkHk " = Toggle tracking"
    }

    /** Build the status-bar hotkey hint shown at idle. */
    _BuildHotkeyHint() {
        capHk := triggers.gettrigger(CaptureHotkeyFired)
        trkHk := triggers.gettrigger(TrackHotkeyFired)
        return "  " capHk " = Capture element under mouse   ·   " trkHk " = Toggle live tracking"
    }

    /**
     * Re-apply the hotkey labels after the user rebinds keys in Preferences.
     * Updates the window title and resets the status-bar hint to reflect the new
     * bindings. Called from PrefUI._OnSave().
     */
    RefreshHotkeyLabels() {
        try this.gui.Title := this._BuildWindowTitle()
        try this.sbMain.SetText(this._BuildHotkeyHint())
    }

    /** Tray menu toggle — flip tipsDisabled and immediately hide any visible tip. */
    _ToggleTips(*) {
        this.tipsDisabled := !this.tipsDisabled
        if this.tipsDisabled {
            A_TrayMenu.Uncheck("Mouse Tips")
            Notify.CloseAll()
            this.lastTipHwnd := 0
            this.dismissedTipHwnd := 0
            SetTimer(this._tipHideFn, 0)
        } else
            A_TrayMenu.Check("Mouse Tips")
    }

    /**
     * Show or hide the floating Key Legend panel — a non-modal cheat sheet of
     * the inspector's hotkeys. Auto-hides after 5s. Positions itself directly
     * below the "Hotkeys" button using GetWindowRect for screen-accurate placement.
     */
    _ToggleKeyLegend(*) {
        if !this._keyLegendGui
            this._BuildKeyLegend()
        hwnd := this._keyLegendGui.Hwnd
        if WinExist("ahk_id " hwnd) && (WinGetStyle("ahk_id " hwnd) & 0x10000000) {
            this._hideLegend()
            return
        }
        ; Position it below the ⌨ button (GetWindowRect gives exact screen coords)
        rc := Buffer(16, 0)
        DllCall("GetWindowRect", "ptr", this.btnKeys.Hwnd, "ptr", rc)
        btnLeft   := NumGet(rc,  0, "int")
        btnBottom := NumGet(rc, 12, "int")
        this._keyLegendGui.Show("x" btnLeft " y" btnBottom " NoActivate")
        SetTimer(this._legendTimerFn, -5000)   ; auto-hide after 5 s
    }

    /** Hide the key legend panel (cancels any pending auto-hide timer). */
    _hideLegend() {
        SetTimer(this._legendTimerFn, 0)       ; cancel any pending timeout
        if this._keyLegendGui
            this._keyLegendGui.Hide()
    }

    /**
     * Lazy-build the floating Key Legend panel on first show. Hand-styled dark theme
     * with three columns per row: emoji icon, key combo (in monospace), description.
     * Uses gettrigger() so the displayed F1/F2 keys reflect any user remapping.
     */
    _BuildKeyLegend() {
        lg := Gui("+Owner" this.gui.Hwnd " +ToolWindow -Caption +AlwaysOnTop", "Key Legend")
        lg.SetFont("s9", "Segoe UI")
        lg.MarginX := 10
        lg.MarginY := 8
        lg.BackColor := 0x1E1E2E

        addRow(icon, key, desc) {
            lg.SetFont("s9 bold", "Consolas")
            lg.AddText("xm w24 cSilver", icon)
            lg.SetFont("s9 bold", "Consolas")
            lg.AddText("x+4 w120 c0xA8D8FF", key)
            lg.SetFont("s9", "Segoe UI")
            lg.AddText("x+8 w200 cWhite", desc)
        }

        lg.SetFont("s9 bold", "Segoe UI")
        lg.AddText("xm cWhite", "Tree navigation (when inspector is active)")
        lg.SetFont("s9", "Segoe UI")
        lg.AddText("xm w360 h1 0x10 c0x444466")   ; separator

        addRow("🎯", triggers.gettrigger(CaptureHotkeyFired), "Capture element under mouse")
        addRow("⌖", triggers.gettrigger(TrackHotkeyFired),   "Toggle live tracking")
        addRow("⤵", "NumpadAdd",  "Expand / first child / next")
        addRow("⤴", "NumpadSub",  "Collapse / parent")
        addRow("🔍", "Ctrl + I",   "Jump to nearest AutomationId")
        addRow("↩", "Ctrl + Z",   "Undo last macro step")

        lg.OnEvent("Escape", (*) => this._hideLegend())
        lg.OnEvent("Close",  (*) => this._hideLegend())

        this._keyLegendGui := lg
    }
}

; ══════════════════════════════════════════════════
;  IsProcessElevated — check if a process has admin rights
;  Credit: jNizM (2017-01-10, modified 2023-01-16)
; ══════════════════════════════════════════════════
/**
 * Detect whether a process is running with elevated (admin) privileges.
 * Uses OpenProcessToken + GetTokenInformation(TokenElevation).
 * @returns 1 if elevated, 0 if normal, !A_IsAdmin on token query failure
 *          (defensive fallback — assume elevated if WE'RE not admin and the query failed).
 */
IsProcessElevated(processId) {
    static PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
    static TOKEN_QUERY                      := 0x0008
    static TokenElevation                   := 20

    hProcess := DllCall("OpenProcess", "UInt", PROCESS_QUERY_LIMITED_INFORMATION, "Int", false, "UInt", processId, "Ptr")
    if !hProcess
        return false  ; can't open — don't assume elevated

    hToken := 0
    if !DllCall("advapi32\OpenProcessToken", "Ptr", hProcess, "UInt", TOKEN_QUERY, "Ptr*", &hToken)
    {
        DllCall("CloseHandle", "Ptr", hProcess)
        return false  ; token denied — don't assume elevated
    }

    isElevated := 0
    size := 0
    result := DllCall("advapi32\GetTokenInformation", "Ptr", hToken, "Int", TokenElevation, "UInt*", &isElevated, "UInt", 4, "UInt*", &size)
    DllCall("CloseHandle", "Ptr", hToken)
    DllCall("CloseHandle", "Ptr", hProcess)

    if !result
        return !A_IsAdmin  ; query failed → assume elevated if we're not admin

    return isElevated
}

/**
 * Populate the seven Scintilla keyword groups with the AHK v2 vocabulary.
 * Group meanings:
 *   kw1 — flow control (If/Else/Loop/Try/Catch/...)
 *   kw2 — built-in functions (Send, Click, FileRead, ...)
 *   kw3 — built-in methods (Add, Choose, Modify, ...)
 *   kw4 — built-in properties (Hwnd, Text, Length, ...)
 *   kw5 — A_* built-in variables
 *   kw6 — directives (#Include, #Requires, #If, ...)
 *   kw7 — variable declaration keywords (Global, Local, Static)
 * Called once during __New to seed the syntax highlighter.
 */
load_AHKV2_KeyWords(&kw1, &kw2, &kw3, &kw4, &kw5, &kw6, &kw7)
{
    kw1 := "Else If Continue Critical Break Goto Return Loop Read Reg Parse Files Switch Try Catch Finally Throw Until While For Exit ExitApp OnError OnExit Reload Suspend Thread"
    kw2 := "Abs ASin ACos ATan BlockInput Buffer CallbackCreate CallbackFree CaretGetPos Ceil Chr Click ClipboardAll ClipWait ComCall ComObjActive ComObjArray ComObjConnect ComObject ComObjFlags ComObjFromPtr ComObjGet ComObjQuery ComObjType ComObjValue ComValue ControlAddItem ControlChooseIndex ControlChooseString ControlClick ControlDeleteItem ControlFindItem ControlFocus ControlGetChecked ControlGetChoice ControlGetClassNN ControlGetEnabled ControlGetFocus ControlGetHwnd ControlGetIndex ControlGetItems ControlGetPos ControlGetStyle ControlGetExStyle ControlGetText ControlGetVisible ControlHide ControlHideDropDown ControlMove ControlSend ControlSendText ControlSetChecked ControlSetEnabled ControlSetStyle ControlSetExStyle ControlSetText ControlShow ControlShowDropDown CoordMode Cos DateAdd DateDiff DetectHiddenText DetectHiddenWindows DirCopy DirCreate DirDelete DirExist DirMove DirSelect DllCall Download DriveEject DriveGetCapacity DriveGetFileSystem DriveGetLabel DriveGetList DriveGetSerial DriveGetSpaceFree DriveGetStatus DriveGetStatusCD DriveGetType DriveLock DriveRetract DriveSetLabel DriveUnlock Edit EditGetCurrentCol EditGetCurrentLine EditGetLine EditGetLineCount EditGetSelectedText EditPaste EnvGet EnvSet Exp FileAppend FileCopy FileCreateShortcut FileDelete FileEncoding FileExist FileInstall FileGetAttrib FileGetShortcut FileGetSize FileGetTime FileGetVersion FileMove FileOpen FileRead FileRecycle FileRecycleEmpty FileSelect FileSetAttrib FileSetTime Float Floor Format FormatTime GetKeyName GetKeyVK GetKeySC GetKeyState GetMethod GroupAdd GroupClose GroupDeactivate Gui GuiCtrlFromHwnd GuiFromHwnd HasBase HasMethod HasProp HotIf HotIfWinActive HotIfWinExist HotIfWinNotActive HotIfWinNotExist Hotkey Hotstring IL_Create IL_Add IL_Destroy ImageSearch IniDelete IniRead IniWrite InputBox InputHook InstallKeybdHook InstallMouseHook InStr Integer IsLabel IsObject IsSet IsSetRef KeyHistory KeyWait ListHotkeys ListLines ListVars ListViewGetContent LoadPicture Log Ln Map Max MenuBar Menu MenuFromHandle MenuSelect Min Mod MonitorGet MonitorGetCount MonitorGetName MonitorGetPrimary MonitorGetWorkArea MouseClick MouseClickDrag MouseGetPos MouseMove MsgBox Number NumGet NumPut ObjAddRef ObjRelease ObjBindMethod ObjHasOwnProp ObjOwnProps ObjGetBase ObjGetCapacity ObjOwnPropCount ObjSetBase ObjSetCapacity OnClipboardChange OnMessage Ord OutputDebug Pause Persistent PixelGetColor PixelSearch PostMessage ProcessClose ProcessExist ProcessSetPriority ProcessWait ProcessWaitClose Random RegExMatch RegExReplace RegDelete RegDeleteKey RegRead RegWrite Round Run RunAs RunWait Send SendText SendInput SendPlay SendEvent SendLevel SendMessage SendMode SetCapsLockState SetControlDelay SetDefaultMouseSpeed SetKeyDelay SetMouseDelay SetNumLockState SetScrollLockState SetRegView SetStoreCapsLockMode SetTimer SetTitleMatchMode SetWinDelay SetWorkingDir Shutdown Sin Sleep Sort SoundBeep SoundGetInterface SoundGetMute SoundGetName SoundGetVolume SoundPlay SoundSetMute SoundSetVolume SplitPath Sqrt StatusBarGetText StatusBarWait StrCompare StrGet String StrLen StrLower StrPut StrReplace StrSplit StrUpper SubStr SysGet SysGetIPAddresses Tan ToolTip TraySetIcon TrayTip Trim LTrim RTrim Type VarSetStrCapacity VerCompare WinActivate WinActivateBottom WinActive WinClose WinExist WinGetClass WinGetClientPos WinGetControls WinGetControlsHwnd WinGetCount WinGetID WinGetIDLast WinGetList WinGetMinMax WinGetPID WinGetPos WinGetProcessName WinGetProcessPath WinGetStyle WinGetExStyle WinGetText WinGetTitle WinGetTransColor WinGetTransparent WinHide WinKill WinMaximize WinMinimize WinMinimizeAll WinMinimizeAllUndo WinMove WinMoveBottom WinMoveTop WinRedraw WinRestore WinSetAlwaysOnTop WinSetEnabled WinSetRegion WinSetStyle WinSetExStyle WinSetTitle WinSetTransColor WinSetTransparent WinShow WinWait WinWaitActive WinWaitNotActive WinWaitClose"
    kw3 := "Add AddActiveX AddButton AddCheckbox AddComboBox AddCustom AddDateTime AddDropDownList AddEdit AddGroupBox AddHotkey AddLink AddListBox AddListView AddMonthCal AddPicture AddProgress AddRadio AddSlider AddStandard AddStatusBar AddTab AddText AddTreeView AddUpDown Bind Check Choose Clear Clone Close Count DefineMethod DefineProp Delete DeleteCol DeleteMethod DeleteProp Destroy Disable Enable Flash Focus Get GetAddress GetCapacity GetChild GetClientPos GetCount GetNext GetOwnPropDesc GetParent GetPos GetPrev GetSelection GetText Has HasKey HasOwnMethod HasOwnProp Hide Insert InsertAt InsertCol Len Mark Maximize MaxIndex Minimize MinIndex Modify ModifyCol Move Name OnCommand OnEvent OnNotify Opt OwnMethods OwnProps Pop Pos Push RawRead RawWrite Read ReadLine ReadUInt ReadInt ReadInt64 ReadShort ReadUShort ReadChar ReadUChar ReadDouble ReadFloat Redraw RemoveAt Rename Restore Seek Set SetCapacity SetColor SetFont SetIcon SetImageList SetParts SetText Show Submit Tell ToggleCheck ToggleEnable Uncheck UseTab Write WriteLine WriteUInt WriteInt WriteInt64 WriteShort WriteUShort WriteChar WriteUChar WriteDouble WriteFloat"
    kw4 := "AtEOF BackColor Base Capacity CaseSense ClassNN ClickCount Count Default Enabled Encoding Focused FocusedCtrl Gui Handle Hwnd Length MarginX MarginY MenuBar Name Pos Position Ptr Size Text Title Value Visible __Handle"
    kw5 := "A_Space A_Tab A_Args A_WorkingDir A_InitialWorkingDir A_ScriptDir A_ScriptName A_ScriptFullPath A_ScriptHwnd A_LineNumber A_LineFile A_ThisFunc A_AhkVersion A_AhkPath A_IsCompiled A_YYYY A_MM A_DD A_MMMM A_MMM A_DDDD A_DDD A_WDay A_YDay A_YWeek A_Hour A_Min A_Sec A_MSec A_Now A_NowUTC A_TickCount A_IsSuspended A_IsPaused A_IsCritical A_ListLines A_TitleMatchMode A_TitleMatchModeSpeed A_DetectHiddenWindows A_DetectHiddenText A_FileEncoding A_SendMode A_SendLevel A_StoreCapsLockMode A_KeyDelay A_KeyDuration A_KeyDelayPlay A_KeyDurationPlay A_WinDelay A_ControlDelay A_MouseDelay A_MouseDelayPlay A_DefaultMouseSpeed A_CoordModeToolTip A_CoordModePixel A_CoordModeMouse A_CoordModeCaret A_CoordModeMenu A_RegView A_TrayMenu A_AllowMainWindow A_AllowMainWindow A_IconHidden A_IconTip A_IconFile A_IconNumber A_TimeIdle A_TimeIdlePhysical A_TimeIdleKeyboard A_TimeIdleMouse A_ThisHotkey A_PriorHotkey A_PriorKey A_TimeSinceThisHotkey A_TimeSincePriorHotkey A_EndChar A_EndChar A_MaxHotkeysPerInterval A_HotkeyInterval A_HotkeyModifierTimeout A_ComSpec A_Temp A_OSVersion A_Is64bitOS A_PtrSize A_Language A_ComputerName A_UserName A_WinDir A_ProgramFiles A_AppData A_AppDataCommon A_Desktop A_DesktopCommon A_StartMenu A_StartMenuCommon A_Programs A_ProgramsCommon A_Startup A_StartupCommon A_MyDocuments A_IsAdmin A_ScreenWidth A_ScreenHeight A_ScreenDPI A_Clipboard A_Cursor A_EventInfo A_LastError True False A_Index A_LoopFileName A_LoopRegName A_LoopReadLine A_LoopField this"
    kw6 := "#ClipboardTimeout #DllLoad #ErrorStdOut #Hotstring #HotIf #HotIfTimeout #Include #IncludeAgain #InputLevel #MaxThreads #MaxThreadsBuffer #MaxThreadsPerHotkey #NoTrayIcon #Requires #SingleInstance #SuspendExempt #UseHook #Warn #WinActivateForce #If"
    kw7 := "Global Local Static"
}

/**
 * Match common Chromium/Gecko/WebKit browser executables by name.
 * Used to short-circuit DeepChildFromPoint (browsers share one render HWND for all
 * page elements) and to display a "Browser" badge in the status bar.
 */
IsBrowserProcess(pid)
{
    try
    {
        procName := ProcessGetName(pid)
    }
    catch
        return false
    return procName ~= "i)chrome\.exe|firefox\.exe|msedge\.exe|iexplore\.exe|safari\.exe|opera\.exe|brave\.exe|vivaldi\.exe"
}

/**
 * Read the PE header of an .exe to determine its architecture.
 * Reads the e_lfanew offset at 0x3C, jumps to the PE signature, then reads the
 * Machine field. @returns "32-bit" (IMAGE_FILE_MACHINE_I386=0x014C),
 * "64-bit" (AMD64=0x8664), or "?" on any failure (locked file, ARM64, corrupt PE).
 */
CheckExeBitness(exePath)
{
    try
    {
        logFile := FileOpen(exePath, "r")
        if !logFile
            return "?"
        logFile.Seek(0x3C, 0)
        peOffset := logFile.ReadUInt()
        logFile.Seek(peOffset, 0)
        if logFile.ReadUInt() != 0x4550
        {
            logFile.Close()
            return "?"
        }
        logFile.Seek(peOffset + 4, 0)
        machine := logFile.ReadUShort()
        logFile.Close()
        switch machine
        {
            case 0x014C: return "32-bit"
            case 0x8664: return "64-bit"
            default:     return "?"
        }
    }
    catch
        return "?"
}

/**
 * Wrap Scintilla's WM_NOTIFY handler so it only fires for messages from OUR
 * Scintilla control. The library's stock callback responds to every WM_NOTIFY in
 * the process — which means triggers/PrefUI's own controls would have their
 * notifications silently re-routed and crash. Reads NMHDR.hwndFrom (first ptr-sized
 * field at offset 0) and bails when it doesn't match our editor's HWND.
 */
_SciFilteredWmNotify(sciHwnd, origCb, wParam, lParam, msg, hwnd) {
    ; NMHDR: first ptr-sized member is hwndFrom
    hwndFrom := NumGet(lParam, 0, "UPtr")
    if hwndFrom != sciHwnd
        return
    return origCb(wParam, lParam, msg, hwnd)
}

; ════════════════════════════════════════════════════════
;  PrefUI — extends triggers.ui with application settings
; ════════════════════════════════════════════════════════
/**
 * Adds an "Application Settings" group box to the Triggers preferences GUI and persists
 * its checkboxes to settings.ini. Settings:
 *   - AlwaysOnTop  : keep the inspector window above other apps
 *   - DeepScan     : default state of the Deep Scan checkbox on startup
 *   - TipsDisabled : suppress the mouse-over tooltips
 *   - RememberPos  : save/restore window x,y across sessions
 *   - GuideMode    : enable the blue "next step" highlight overlay
 *
 * The lifecycle is split across three calls because Triggers' preferences GUI builds
 * itself in stages — Build adds our controls, HookSave attaches our save handler,
 * Load reads at startup, SavePosition writes on exit.
 */
class PrefUI
{
    static ini      := A_ScriptDir "\UIA_Inspector_settings.ini"
    static chkAOT   := ""
    static chkDeep  := ""
    static chkTips  := ""
    static chkPos   := ""
    static chkGuide := ""
    static edtApiKey := ""
    static chkShowKey := ""
    static cbModel := ""
    static edtMaxTokens := ""

    ; Curated model list grouped loosely by provider. The control is an editable
    ; ComboBox so users can type any DeepSeek model ID not in this list.
    static ModelList := [
        "anthropic/claude-sonnet-4.5",
        "anthropic/claude-opus-4.1",
        "anthropic/claude-3.5-sonnet",
        "anthropic/claude-3.5-haiku",
        "openai/gpt-4o",
        "openai/gpt-4o-mini",
        "openai/o3-mini",
        "openai/gpt-4.1",
        "openai/gpt-4.1-mini",
        "google/gemini-2.5-pro",
        "google/gemini-2.5-flash",
        "google/gemini-2.0-flash",
        "meta-llama/llama-3.3-70b-instruct",
        "deepseek-v4-flash",
        "deepseek/deepseek-r1",
        "x-ai/grok-2",
        "mistralai/mistral-large"
    ]

    /**
     * Append the Application Settings groupbox + 5 checkboxes to triggers.ui.
     * Must be called AFTER triggers.AddHotkey and BEFORE triggers.FinishMenu —
     * Triggers expects all custom additions in that window.
     */
    static Build()
    {
        g := triggers.ui
        g.SetFont("s12", "Verdana")

        aot   := IniRead(PrefUI.ini, "Settings", "AlwaysOnTop",  1) + 0
        deep  := IniRead(PrefUI.ini, "Settings", "DeepScan",     0) + 0
        tips  := IniRead(PrefUI.ini, "Settings", "TipsDisabled", 0) + 0
        pos   := IniRead(PrefUI.ini, "Settings", "RememberPos",  1) + 0
        guide := IniRead(PrefUI.ini, "Settings", "GuideMode",    1) + 0

        grp := g.AddGroupBox("xm w600 h110", "Application Settings")
        PrefUI.chkAOT   := g.AddCheckbox("xp+20 yp+35 "  (aot   ? "+Checked" : "-Checked"), "Always on Top")
        PrefUI.chkDeep  := g.AddCheckbox("x+30 "          (deep  ? "+Checked" : "-Checked"), "Deep Scan by default")
        PrefUI.chkTips  := g.AddCheckbox("x+30 "          (!tips ? "+Checked" : "-Checked"), "Mouse Tips")
        PrefUI.chkPos   := g.AddCheckbox("x30 y+10 "     (pos   ? "+Checked" : "-Checked"), "Remember position")
        PrefUI.chkGuide := g.AddCheckbox("x+30 yp "      (guide ? "+Checked" : "-Checked"), "Guide Mode")

        ; DeepSeek API key + model — stored in settings.ini under [DeepSeek]
        apiKey := IniRead(PrefUI.ini, "DeepSeek", "api_key", "")
        model  := IniRead(PrefUI.ini, "AI", "Model", "deepseek-v4-flash")
        maxTok := IniRead(PrefUI.ini, "AI", "MaxTokens", 2048)
        g.AddGroupBox("xm w600 h150", "AI (DeepSeek)")
        g.AddText("xp+20 yp+30 w80 right section", "Model:")
        PrefUI.cbModel := g.AddComboBox("x+6 yp-3 w320", PrefUI.ModelList)
        PrefUI.cbModel.Text := model
        g.AddLink("xs w80 right", '<a href="https://platform.deepseek.com/api_keys">API Key:</a>')
        PrefUI.edtApiKey  := g.AddEdit("x+6 yp-3 h30 w400 -multi Password", apiKey)
        PrefUI.chkShowKey := g.AddCheckbox("x+m yp+4", "Show")
        PrefUI.chkShowKey.OnEvent("Click", (*) => PrefUI._ToggleShowKey())
        g.AddText("xs w80 right", "MaxTokens:")
        PrefUI.edtMaxTokens := g.AddEdit("x+6 yp-3 w80 Number", maxTok)
        g.AddText("x+8 yp+4 ", "Caps reply len. Lower=fits smaller credits.")
    }

    /**
     * Flip the API-key Edit control between password-masked and plain text.
     * AHK v2 Edit supports +Password/-Password at runtime via .Opt(); combined
     * with a Redraw the mask/unmask takes effect immediately.
     */
    static _ToggleShowKey()
    {
        PrefUI.edtApiKey.Opt(PrefUI.chkShowKey.Value ? "-Password" : "+Password")
        PrefUI.edtApiKey.Redraw()
    }

    /**
     * Piggyback on the Triggers Save button so our checkboxes get persisted whenever
     * the user saves hotkey changes. Must be called AFTER triggers.FinishMenu —
     * triggers.save doesn't exist until then.
     */
    static HookSave()
    {
        triggers.save.OnEvent("Click", (*) => PrefUI._OnSave())
    }

    /**
     * Save handler — write all 5 settings to settings.ini AND apply them live to the
     * running inspector (toggle AlwaysOnTop, sync the Deep Scan checkbox, flip
     * Mouse Tips, refresh guide highlight). Live application means the user sees the
     * effect of "Apply" immediately, no restart needed.
     */
    static _OnSave()
    {
        IniWrite(PrefUI.chkAOT.Value,          PrefUI.ini, "Settings", "AlwaysOnTop")
        IniWrite(PrefUI.chkDeep.Value,         PrefUI.ini, "Settings", "DeepScan")
        IniWrite(!PrefUI.chkTips.Value,        PrefUI.ini, "Settings", "TipsDisabled")
        IniWrite(PrefUI.chkPos.Value,          PrefUI.ini, "Settings", "RememberPos")
        IniWrite(PrefUI.chkGuide.Value,        PrefUI.ini, "Settings", "GuideMode")

        ; Persist the DeepSeek API key and refresh authorization so the next
        ; Chat.Completions call picks up the new key without a restart.
        if PrefUI.edtApiKey {
            key := Trim(PrefUI.edtApiKey.Value)
            IniWrite(key = "" ? " " : key, PrefUI.ini, "DeepSeek", "api_key")
            if key != "" {
                try OpenRouter.Authenticate(key)
            } else {
                try OpenRouter.headers["Authorization"] := ""
            }
        }

        if PrefUI.cbModel {
            model := Trim(PrefUI.cbModel.Text)
            if model != "" {
                IniWrite(model, PrefUI.ini, "AI", "Model")
                _inspector._aiModel := model
                if _inspector.HasProp("_askAIChat") && _inspector._askAIChat
                    _inspector._askAIChat.model := model
            }
        }

        if PrefUI.edtMaxTokens {
            mt := Trim(PrefUI.edtMaxTokens.Value) + 0
            if mt > 0
                IniWrite(mt, PrefUI.ini, "AI", "MaxTokens")
        }

        if !IsSet(_inspector) || !_inspector
            return

        ; Apply AOT immediately to both windows
        aotOpt := PrefUI.chkAOT.Value ? "+AlwaysOnTop" : "-AlwaysOnTop"
        _inspector.gui.Opt(aotOpt)
        triggers.ui.Opt(aotOpt)

        ; Sync Deep Scan checkbox in the live inspector
        _inspector.chkDeepScan.Value := PrefUI.chkDeep.Value

        ; Sync Mouse Tips
        _inspector.tipsDisabled := !PrefUI.chkTips.Value
        if _inspector.tipsDisabled
            A_TrayMenu.Uncheck("Mouse Tips")
        else
            A_TrayMenu.Check("Mouse Tips")

        ; Sync Guide Mode (and re-render the highlight immediately)
        _inspector.guideMode := PrefUI.chkGuide.Value
        _inspector._UpdateGuide()

        ; Refresh window title + status-bar hint so any rebound hotkeys show live.
        _inspector.RefreshHotkeyLabels()
    }

    /**
     * Snapshot every persisted setting into a plain object — called once at startup
     * and stored in the global APP_SETTINGS so other code can read defaults without
     * touching the INI file every time.
     * @returns Object with alwaysOnTop / deepScan / tipsDisabled / showAllProps /
     *          rememberPos / guideMode / winX / winY fields.
     */
    static Load()
    {
        ini := PrefUI.ini
        s := {}
        s.alwaysOnTop  := IniRead(ini, "Settings", "AlwaysOnTop",  1) + 0
        s.deepScan     := IniRead(ini, "Settings", "DeepScan",     0) + 0
        s.tipsDisabled := IniRead(ini, "Settings", "TipsDisabled", 0) + 0
        s.showAllProps := IniRead(ini, "Settings", "ShowAllProps", 0) + 0
        s.rememberPos  := IniRead(ini, "Settings", "RememberPos",  1) + 0
        s.guideMode    := IniRead(ini, "Settings", "GuideMode",    1) + 0
        s.winX         := IniRead(ini, "Settings", "WinX",        "")
        s.winY         := IniRead(ini, "Settings", "WinY",        "")
        return s
    }

    /**
     * Persist the current window x,y to settings.ini. Called from _OnExit. No-op
     * when RememberPos is unchecked — we don't want to save a position the user
     * didn't ask us to restore.
     */
    static SavePosition(hwnd)
    {
        if !PrefUI.chkPos || !PrefUI.chkPos.Value
            return
        WinGetPos(&x, &y, , , "ahk_id " hwnd)
        IniWrite(x, PrefUI.ini, "Settings", "WinX")
        IniWrite(y, PrefUI.ini, "Settings", "WinY")
    }
}
