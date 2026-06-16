/**
 * ============================================================================ *
 * @Library  : Triggers                                                         *
 * @Verson   : v 0.4.0                                                          *
 * @DevPath  : S:\lib\v2\Triggers\Triggers.ahk                                  *
 * @Author   : Xeo786                                                           *
 * @Homepage : the-automator.com                                                *
 * @Created  : June 14, 2024                                                    *
 * ============================================================================ *
 * Want a clear path for learning AutoHotkey?                                   *
 * Take a look at our AutoHotkey courses here: the-Automator.com/Discover       *
 * They're structured in a way to make learning AHK EASY                        *
 * And come with a 200% moneyback guarantee so you have NOTHING to risk!        *
 * ============================================================================ *
 */

/*
This work by the-Automator.com is licensed under CC BY 4.0

Attribution — You must give appropriate credit , provide a link to the license,
and indicate if changes were made.
You may do so in any reasonable manner, but not in any way that suggests the licensor
endorses you or your use.
No additional restrictions — You may not apply legal terms or technological measures that
legally restrict others from doing anything the license permits.
*/

/**
 * ============================================================================ *
 *                               Using Trigger Class                            *
 * ============================================================================ *
 * The Trigger Class is designed to simplify the process of creating interactive
 * user interfaces (UI) for AutoHotkey scripts that require user-defined hotkeys,
 * hotstrings, or mouse shortcuts. It abstracts the complexities of GUI and tray
 * menu management, providing an easy-to-use interface for both developers and
 * end-users.
 *
 * Why Use Trigger Class?
 * ----------------------
 * - **Ease of Use**: Developers can easily integrate the Trigger Class into their
 *   projects, allowing for quick assignment of functions to triggers without
 *   delving into the intricacies of GUI or tray menu creation and management.
 *
 * - **Flexibility**: Users are given the freedom to customize their hotkeys,
 *   hotstrings, and mouse shortcuts through a user-friendly interface, making
 *   the application more adaptable to their needs.
 *
 * - **Automatic Updates**: The class handles the GUI, tray menu, and ini togather
 *   automatically update them whenever a user makes changes, ensuring a seamless experience.
 *
 * How to Use Trigger Class?
 * -------------------------
 * Include the Trigger Class in your AutoHotkey script as a library.
 *
 * 1. **Static Class**: Trigger Class is designed as a static class,
 *    there's no need to create an instance of it. Directly use the class methods to interact
 *    with the functionality it provides.
 *
 * 2. **Triggers.AddMouse() Method**: This method allows you to assign a mouse shortcut to a specific function.
 *    - `Callback`: The name of the function to be called when the mouse shortcut is activated.
 *    - `Label`: A unique identifier for the mouse shortcut.
 *    - `DefaultHotkey`: (Optional) The default mouse shortcut. Leave as an empty string for none.
 *    - `Title`: (Optional) A descriptive title for the mouse shortcut, so Trigger  on work when the window with Title is active.
 *    - `trayAction`: (Optional) A boolean indicating whether this shortcut should appear in the tray menu. Default is `false`.
 *
 * 3. **Triggers.addHotkey() Method**: Use this method to assign a keyboard hotkey to trigger a function.
 *    - `Callback`: The function to execute when the hotkey is pressed.
 *    - `Label`: A unique identifier for the hotkey.
 *    - `DefaultHotkey`: (Optional) The default keyboard hotkey. Leave as an empty string if not applicable.
 *    - `Title`: (Optional) A descriptive title for the hotkey, so Trigger  on work when the window with Title is active.
 *    - `trayAction`: (Optional) A boolean value indicating if this hotkey should be included in the tray menu. Default is `false`.
 *
 * 4. **Triggers.AddHotstring() Method**: This method allows you to assign a hotstring (a specific sequence of characters) to a function.
 *    - `Callback`: The function to be called when the hotstring is typed.
 *    - `Label`: A unique identifier for the hotstring.
 *    - `Defaulthotstring`: (Optional) The default sequence of characters for the hotstring. Leave as an empty string if not applicable.
 *    - `Title`: (Optional) A descriptive title for the hotstring, so Trigger  on work when the window with Title is active.
 *    - `trayAction`: (Optional) Indicates whether this Callback should be called using prior tray menu or Open Prefernces. Default is `false`.
 *
 * 5. **Triggers.show() Mains ui Title**: It's mandatory to call `Triggers.show()` at the end after adding all the triggers.
 *    - `opt` : (Optional) A string that specifies options same as ahk GUI options.
 *    - `name`: (Optional) A string that sets the title of the UI window. If not provided, "Preference" is used as a default title.
 *
 * 6. ** Triggers.SetParent() Method**: This function sets a parent for the Triggers preferences GUI, making the specified GUI window the owner.
 *    - `GuiObj`: The GUI object whose window handle (`hwnd`) will be set as the parent for the Triggers preferences GUI. This GUI object becomes the owner of the Triggers preferences GUI.
 *
 * The Trigger Class is a powerful tool for developers looking to enhance their
 * AutoHotkey scripts with dynamic and user-friendly trigger assignment
 * capabilities. By leveraging this class, you can create more versatile and
 * customizable applications with minimal additional coding effort.
 * ============================================================================ *
 */
#SingleInstance
#Requires Autohotkey v2.0+

/*
	todo after discussion
	triggers.AddCheckBoxes('Font',Label,['Bold','Italic','Underline'])

	msgbox triggers.GetCheck('Font').text  ; return Bold
	msgbox triggers.GetCheck('Font').Value  ; return 1

	triggers.AddRadioButtons('Leave',Label,['Day','Week','Month'])

	msgbox triggers.GetRadio('Leave').text  ; return Day
	msgbox triggers.GetRadio('Leave').Value  ; return 1

 */


Class triggers
{
	static Actions   := Map()
	static MouseBtns := ['LButton','RButton','MButton','XButton1','XButton2']
	static finished  := false
	static Snapshot  := Map()
	; Maps INI type (1=Mouse,2=Keyboard,3=Hotstring) to Tab index (1=Keyboard,2=Mouse,3=Hotstring)
	static TypeToTab := Map(1, 2, 2, 1, 3, 3, 0, 1, 4, 1)
	static TabToType := Map(1, 2, 2, 1, 3, 3)

	static __New()
	{
		this.ini := A_ScriptDir "\UIA_Inspector_settings.ini"
		this.tray := A_TrayMenu
		this.tray.delete()
		this.LoadAllHotkeys()
		this.ui := Gui()
		this.ui.SetFont('s12','Verdana')
		this.BuildChildGui()
	}

	static SetOwner(GuiObj)
	{
		this.ui.opt('owner' GuiObj.hwnd)
	}

	; ===================== Public API =====================

	Static     AddMouse(Callback,Label,DefaultHotkey:='',Title:='',trayAction:=false) => this.Add(Callback,Label,DefaultHotkey,Title,1,trayAction)
	Static    AddHotkey(Callback,Label,DefaultHotkey:='',Title:='',trayAction:=false) => this.Add(Callback,Label,DefaultHotkey,Title,2,trayAction)
	Static AddHotstring(Callback,Label,DefaultHotkey:='',Title:='',trayAction:=false) => this.Add(Callback,Label,DefaultHotkey,Title,3,trayAction)

	static gettrigger(callback) => this.HKToString(this.Actions[callback.name].trigger)

	static GetTrayLabel(callback)
	{
		action := this.Actions[callback.name]
		return action.label a_tab this.HKToString(action.trigger)
	}

	static DisableModiers(callback)
	{
		this.Actions[callback.name].disableModifiers := true
	}

	Static SetDefaultTray(Callback)
	{
		this.tray.Default := this.Actions[Callback.name].trayText
	}

	static Show(opt:='')
	{
		this.SuspendAll()
		this.UI.show(opt)
	}

	static FinishMenu(name:='Preferences',setDefault:=false)
	{
		this.UI.Title := name
		if this.finished
			return
		this.UI.OnEvent('close', (*) => this.CancelAndClose())
		this.UI.OnEvent('Escape', (*) => this.CancelAndClose())
		this.tray.Add('open folder',(*)=>Run(A_ScriptDir))
		this.tray.add()
		this.tray.add(name,(*)=>this.Show())
		this.tray.SetIcon(name, "C:\Windows\system32\wmploc.dll", 18)
		this.tray.add()
		this.save := this.UI.AddButton('xm w80','Save')
		this.save.onEvent('click', (*) => this.ApplyAndClose())
		this.UI.AddButton('x+m w80','Cancel').onEvent('click', (*) => this.CancelAndClose())
		if setDefault
			this.tray.Default := name
		this.finished := true
	}

	; ===================== Add (internal) =====================

	Static Add(Callback,Label,DefaultHotkey,Title, type, trayAction)
	{
		if this.finished
			throw Error('Cannot add new triggers after calling triggers.FinishMenu()')
		name := Callback.name
		if !DefaultHotkey := IniRead(this.ini, 'Hotkeys',name,DefaultHotkey)
			type := 0
		if name = ''
			return

		Label := IniRead(this.ini, 'Label',name,Label)
		Title := IniRead(this.ini, 'Title',name,Title)
		triggerType := IniRead(this.ini, 'Dropdown',name,type) + 0

		; Determine actual type when disabled/empty (derive from trigger string)
		actualType := triggerType
		isHotstring := (triggerType = 3)
		if (triggerType = 0 || triggerType = 4)
		{
			if isHotstring
				actualType := 3
			else
			{
				actualType := 2
				for btn in this.MouseBtns
				{
					if InStr(DefaultHotkey, btn)
					{
						actualType := 1
						break
					}
				}
			}
		}

		; Build structured action object
		action := {}
		action.label       := Label
		action.trigger     := DefaultHotkey
		action.callback    := Callback
		action.title       := Title
		action.triggerType := actualType
		action.pendingType := actualType
		action.disabled    := (triggerType = 0 || triggerType = 4)
		action.disableModifiers := false

		; Build tray text
		if isHotstring
			action.trayText := Label '`t::' DefaultHotkey
		else
			action.trayText := Label '`t' this.HKToString(DefaultHotkey)

		; --- Main GUI row: [Change] button + readonly trigger display + [Disable] checkbox ---
		action.groupBox    := this.ui.AddGroupBox('xm w600 h70', Label)
		action.changeBtn   := this.ui.AddButton('xp+20 yp+30 w80 h27 section', 'Change')
		this.UI.SetFont('s12','Arial Narrow')
		action.hkDisplay   := this.ui.AddEdit('x+m w390 h27 readonly -multi', this.HKToString(DefaultHotkey) (Title ? ' - ' Title : ''))
		this.UI.SetFont('s12','Verdana')
		action.disableChk  := this.ui.AddCheckbox('x+m yp+3', 'Off')

		if action.disabled
		{
			action.disableChk.value := 1
			action.changeBtn.Enabled := false
		}

		; Events
		action.changeBtn.onEvent('click', (*) => this.OpenTriggerSelector(name))
		action.disableChk.onEvent('click', (ctrl, *) => this.ToggleDisable(ctrl, name))

		this.Actions[name] := action

		; Tray menu
		if trayAction
			this.tray.add(action.trayText, (*) => %name%())
		else
			this.tray.add(action.trayText, (*) => this.Show())

		; Register the trigger
		HotIfWinActive Title
		if DefaultHotkey && !action.disabled
		{
			if (triggerType = 3)
				Hotstring('::' DefaultHotkey, Callback, 'on')
			else
				Hotkey(DefaultHotkey, Callback, 'on')
		}
		HotIfWinActive
	}

	; ===================== Checkbox (beta) =====================

	static addCheckbox(Callback,Label,list:=Map(),linediv:= 3)
	{
		if this.finished
			throw Error('Cannot add new triggers after calling triggers.FinishMenu()')
		name := Callback.name
		this.Actions[name] := Map('label',Label,'callback',Callback)
		h := 45
		h :=  linediv * h

		for ChkName, chkVal in list
		{
			chked := '-'
			if chk := IniRead(this.ini, 'CheckBoxs',name,chkVal)
				chked := '+'
			if a_index = 1
			{
				this.Actions[name]['group'] 	:= 	this.ui.AddGroupBox('xm w600 h' h, Label)
				opt := 'xp+20 yp+30 ' chked 'checked section'
			}
			else if Mod(a_index, linediv) = 1
				opt := 'xs ' chked 'checked'
			else
				opt := 'x+m ' chked 'checked'

			this.Actions[name][ChkName]     := this.ui.Addcheckbox(opt,ChkName)
		}
	}

	; ===================== Unified Child GUI =====================

	static BuildChildGui()
	{
		Crosshairbg := "compstui.dll"
		this.CH := {h:50,w:50}

		this.TriggerUI := Gui('Owner' this.ui.hwnd, 'Set Trigger')
		this.TriggerUI.SetFont('s12', 'Verdana')

		; Context row (shared across all tabs)
		this.TriggerCR := this.TriggerUI.addpic('y30 border icon52 h' this.CH.h ' w' this.CH.w, Crosshairbg)
		                   this.TriggerUI.AddText('xp+70 yp-10', 'Context (WinTitle):')
		                   this.TriggerUI.SetFont('s12', 'Arial Narrow')
		this.TriggerCX := this.TriggerUI.AddEdit('xm+70 y+m w310')
		                   this.TriggerUI.SetFont('s12', 'Verdana')

		; Tab control: Keyboard | Mouse | Hotstring
		this.TriggerTab := this.TriggerUI.AddTab3('xm y+20 w400 h170', ['Keyboard', 'Mouse', 'Hotstring'])

		; --- Keyboard tab (tab index 1, INI type 2) ---
		this.TriggerTab.UseTab('Keyboard')
		this.HKWin   := this.TriggerUI.AddCheckbox('xm+20 y+20', 'Win')
		this.HKCtrl  := this.TriggerUI.AddCheckbox('x+m', 'Ctrl')
		this.HKShift := this.TriggerUI.AddCheckbox('x+m', 'Shift')
		this.HKAlt   := this.TriggerUI.AddCheckbox('x+m', 'Alt')
		this.HK      := this.TriggerUI.Addhotkey('xm+20 y+10 w360 readonly')

		; --- Mouse tab (tab index 2, INI type 1) ---
		this.TriggerTab.UseTab('Mouse')
		this.MSWin   := this.TriggerUI.AddCheckbox('xm+20 y+20', 'Win')
		this.MSCtrl  := this.TriggerUI.AddCheckbox('x+m', 'Ctrl')
		this.MSShift := this.TriggerUI.AddCheckbox('x+m', 'Shift')
		this.MSAlt   := this.TriggerUI.AddCheckbox('x+m', 'Alt')
		this.MS      := this.TriggerUI.AddDDL('xm+20 y+10 w360', ['Left','Right','Middle','Special Button 1','Special Button 2'])

		; --- Hotstring tab (tab index 3, INI type 3) ---
		this.TriggerTab.UseTab('Hotstring')
		this.TriggerUI.AddText('xm+20 y+20', 'Hotstring:')
		this.HS := this.TriggerUI.AddEdit('xm+20 y+10 w360')

		this.TriggerTab.UseTab() ; end tab association

		; Position buttons below the tab control using absolute Y
		this.TriggerTab.GetPos(, &tabY, , &tabH)
		btnY := tabY + tabH + 10
		this.TriggerApply  := this.TriggerUI.AddButton('xm y' btnY ' w80', 'Apply')
		this.TriggerCancel := this.TriggerUI.AddButton('x+m w80', 'Cancel')

		; Events
		this.TriggerUI.onEvent('close', (*) => this.HideChildGui())
		this.TriggerUI.onEvent('Escape', (*) => this.HideChildGui())
		this.TriggerCancel.onEvent('click', (*) => this.HideChildGui())
		this.TriggerApply.onEvent('click', (*) => this.ChildSubmit())
		this.TriggerCR.onEvent('click', (*) => this.showCrosshairs())

		; Crosshair overlay for WinTitle picker
		this.Crosshair := Gui("-SysMenu +AlwaysOnTop -Border -Caption -DPIScale")
		this.Crosshair.AddPicture('x0 y0 h50 w50 icon52', "compstui.dll")
		this.Crosshair.MarginX := 0
		this.Crosshair.MarginY := 0
		this.Crosshair.Show('hide')
		WinSetTransColor('white ' 100, this.Crosshair)

		; Prevent modifier-only hotkeys
		this.HK.onEvent('change', hkupdate)
		hkupdate(*)
		{
			if triggers.HK.Value ~= '\+|\!|\^'
				triggers.HK.Value := 'None'
		}
	}

	; ===================== Child GUI Interactions =====================

	static OpenTriggerSelector(name)
	{
		this.UI.opt('+disabled')
		this.ResetChildGui()
		this.CurrentLabel := name
		this.ToggleModifierVisibility(name)

		action := this.Actions[name]
		triggerType := action.pendingType

		; Select the appropriate tab
		tabIndex := this.TypeToTab.Has(triggerType) ? this.TypeToTab[triggerType] : 1
		this.TriggerTab.Choose(tabIndex)

		; Populate context
		this.TriggerCX.value := action.title

		; Populate current trigger values
		switch triggerType
		{
			Case 1: this.UpdateMSUI()
			Case 2: this.UpdateHKUI()
			Case 3: this.UpdateHSUI()
		}

		this.TriggerUI.show()
	}

	static ChildSubmit()
	{
		str := ''
		activeTab := this.TriggerTab.Value ; 1=Keyboard, 2=Mouse, 3=Hotstring

		switch activeTab
		{
			Case 1: ; Keyboard
				if !this.HK.value
					return
				if this.HKWin.value
					str .= '#'
				if this.HKCtrl.value
					str .= '^'
				if this.HKShift.value
					str .= '+'
				if this.HKAlt.value
					str .= '!'
				str .= this.HK.value
				pendingType := 2

			Case 2: ; Mouse
				if !this.MS.value
					return
				if this.MSWin.value
					str .= '#'
				if this.MSCtrl.value
					str .= '^'
				if this.MSShift.value
					str .= '+'
				if this.MSAlt.value
					str .= '!'
				str .= this.MouseBtns[this.MS.value]
				pendingType := 1
				if str = 'LButton'
				{
					ToolTip('Left Button is not allowed`nplease combine any modifier key with it.')
					settimer(ToolTip, -2000)
					return
				}

			Case 3: ; Hotstring
				if !this.HS.value
					return
				str := this.HS.value
				pendingType := 3
		}

		titlefilter := this.TriggerCX
		if this.CheckDuplicateHotkey(str, titlefilter.value)
			return

		action := this.Actions[this.CurrentLabel]
		action.pendingTrigger := str
		action.pendingType    := pendingType
		action.pendingTitle   := titlefilter.value ? titlefilter.value : ''
		action.hkDisplay.value := this.HKToString(str) (titlefilter.value ? ' - ' titlefilter.value : '')
		this.HideChildGui()
	}

	static HideChildGui()
	{
		this.TriggerUI.hide()
		this.UI.opt('-disabled')

		; If the child was cancelled and the action still has no trigger, re-disable it
		if this.CurrentLabel != ''
		{
			action := this.Actions[this.CurrentLabel]
			hasPending := action.HasOwnProp('pendingTrigger') && action.pendingTrigger != ''
			if !action.trigger && !hasPending
			{
				action.disabled := true
				action.disableChk.value := 1
				action.changeBtn.Enabled := false
			}
		}

		this.UI.Show()
		this.CurrentLabel := ''
	}

	static CheckDuplicateHotkey(HK,title)
	{
		if !FileExist(this.ini)
			return
		for i, line in StrSplit(IniRead(this.ini,'Hotkeys'),'`n','`r')
		{
			if RegExMatch(line,'(.*)=(.*)',&r)
			&& r[1] != this.CurrentLabel
			&& title = iniread(this.ini,'Title',r[1],'')
			&& hk = r[2]
			{
				tooltip 'Hotkey already in use'
				settimer(tooltip,-2000)
				return true
			}
		}
	}

	static UpdateMSUI()
	{
		trigger := this.Actions[this.CurrentLabel].trigger
		if InStr(trigger, '#')
			this.MSWin.value := 1
		if InStr(trigger, '^')
			this.MSCtrl.value := 1
		if InStr(trigger, '+')
			this.MSShift.value := 1
		if InStr(trigger, '!')
			this.MSAlt.value := 1
		MB := RegExReplace(trigger,'\#|\^|\+|\!')
		for i, mbtn in this.MouseBtns
			if mbtn = MB
				this.MS.value := i
	}

	static UpdateHKUI()
	{
		trigger := this.Actions[this.CurrentLabel].trigger
		if InStr(trigger, '#')
			this.HKWin.value := 1
		if InStr(trigger, '^')
			this.HKCtrl.value := 1
		if InStr(trigger, '+')
			this.HKShift.value := 1
		if InStr(trigger, '!')
			this.HKAlt.value := 1
		this.HK.value := RegExReplace(trigger,'\#|\^|\+|\!')
	}

	static UpdateHSUI()
	{
		this.HS.value := this.Actions[this.CurrentLabel].trigger
	}

	static ResetChildGui()
	{
		this.TriggerCX.value := ''
		this.HKWin.value := 0
		this.HKCtrl.value := 0
		this.HKShift.value := 0
		this.HKAlt.value := 0
		this.HK.value := ''
		this.MSWin.value := 0
		this.MSCtrl.value := 0
		this.MSShift.value := 0
		this.MSAlt.value := 0
		this.MS.value := 0
		this.HS.value := ''
	}

	static showCrosshairs()
	{
		this.Crosshair.opt('owner' this.TriggerUI.hwnd)
		CR := this.TriggerCR
		titlefilter := this.TriggerCX

		CoordMode 'Mouse', 'Screen'
		this.Crosshair.Show()
		WinSetTransColor('white ' 0, CR)
		while GetKeyState("Lbutton","P")
		{
			MouseGetPos &X, &Y
			sleep 5
			this.Crosshair.Move(X- (this.CH.h/2),Y- (this.CH.w/2))
		}
		this.Crosshair.hide()
		WinSetTransColor('white ' 255, CR)
		WinWaitNotActive WinExist(this.Crosshair)
		MouseGetPos &X, &Y, &iHwnd, &Editnn
		MouseGetPos(&x,&y,&hwnd,&ctrlHwnd,1)
		if title := WinGetTitle('ahk_id' hwnd)
			titlefilter.value := title
	}

	static ToggleModifierVisibility(name)
	{
		action := this.Actions[name]
		hidden := action.HasOwnProp('disableModifiers') && action.disableModifiers

		this.MSWin.visible   := !hidden
		this.MSCtrl.visible  := !hidden
		this.MSShift.visible := !hidden
		this.MSAlt.visible   := !hidden
		this.HKWin.visible   := !hidden
		this.HKCtrl.visible  := !hidden
		this.HKShift.visible := !hidden
		this.HKAlt.visible   := !hidden
	}

	; ===================== Trigger Registration =====================

	static RegisterTrigger(name)
	{
		action := this.Actions[name]
		if action.disabled || !action.trigger
			return
		HotIfWinActive action.title
		if action.triggerType = 3
			Hotstring('::' action.trigger, action.callback, 'On')
		else
			Hotkey(action.trigger, action.callback, 'On')
		HotIfWinActive
	}

	static DeactivateTrigger(name)
	{
		action := this.Actions[name]
		if !action.trigger
			return
		HotIfWinActive action.title
		try
		{
			if action.triggerType = 3
				Hotstring('::' action.trigger, , 'Off')
			else
				Hotkey(action.trigger, action.callback, 'Off')
		}
		HotIfWinActive
	}

	static ToggleDisable(ctrl, name)
	{
		action := this.Actions[name]
		if !ctrl.value
		{
			; User is enabling — if no trigger is set, force them to pick one
			hasPending := action.HasOwnProp('pendingTrigger') && action.pendingTrigger != ''
			if !action.trigger && !hasPending
			{
				action.disabled := false
				action.changeBtn.Enabled := true
				this.OpenTriggerSelector(name)
				return
			}
			action.disabled := false
			action.changeBtn.Enabled := true
		}
		else
		{
			action.disabled := true
			action.changeBtn.Enabled := false
		}
	}

	; ===================== Save / Cancel / Suspend Flow =====================

	static SuspendAll()
	{
		this.Snapshot := Map()
		for name, action in this.Actions
		{
			if !action.HasOwnProp('trigger')
				continue

			; Snapshot current state for cancel (including empty triggers)
			this.Snapshot[name] := {trigger: action.trigger, triggerType: action.triggerType, title: action.title, disabled: action.disabled, displayText: action.hkDisplay.value, trayText: action.trayText}

			; Reset pending state
			action.pendingTrigger := ''
			action.pendingType    := action.triggerType
			action.pendingTitle   := action.title

			if !action.disabled && action.trigger
				this.DeactivateTrigger(name)
		}
	}

	static ApplyAndClose()
	{
		; Validate: all enabled actions must have a trigger assigned
		for name, action in this.Actions
		{
			if !action.HasOwnProp('trigger')
				continue
			hasPending := action.HasOwnProp('pendingTrigger') && action.pendingTrigger != ''
			if !action.disabled && !action.trigger && !hasPending
			{
				ToolTip('"' action.label '" is enabled but has no trigger assigned.`nPlease set a trigger or disable it.')
				SetTimer(ToolTip, -3000)
				return
			}
		}

		for name, action in this.Actions
		{
			if !action.HasOwnProp('trigger')
				continue

			oldTrayText := action.trayText

			; Apply pending changes if any
			if action.HasOwnProp('pendingTrigger') && action.pendingTrigger != ''
			{
				action.trigger     := action.pendingTrigger
				action.triggerType := action.pendingType
				action.title       := action.pendingTitle
			}

			; Activate the trigger
			this.RegisterTrigger(name)

			; Save to INI
			this.SaveActionToIni(name)

			; Update tray label
			this.UpdateTrayLabel(name, oldTrayText)
		}
		this.Snapshot := Map()
		this.UI.Hide()
	}

	static CancelAndClose()
	{
		for name, action in this.Actions
		{
			if !action.HasOwnProp('trigger')
				continue

			; Restore from snapshot
			if this.Snapshot.Has(name)
			{
				snap := this.Snapshot[name]
				action.trigger     := snap.trigger
				action.triggerType := snap.triggerType
				action.title       := snap.title
				action.disabled    := snap.disabled
				action.hkDisplay.value  := snap.displayText
				action.disableChk.value := snap.disabled ? 1 : 0
				action.changeBtn.Enabled := !snap.disabled
			}

			; Re-activate with original values
			this.RegisterTrigger(name)
		}
		this.Snapshot := Map()
		this.UI.Hide()
	}

	; ===================== INI Persistence =====================

	static SaveActionToIni(name)
	{
		action := this.Actions[name]
		IniWrite(action.label, this.ini, 'Label', name)
		IniWrite(action.trigger, this.ini, 'Hotkeys', name)
		IniWrite(action.title ? action.title : "", this.ini, 'Title', name)
		IniWrite(action.disabled ? 4 : action.triggerType, this.ini, 'Dropdown', name)
	}

	static LoadAllHotkeys()
	{
		try hotkeyslist := IniRead(this.ini, 'Hotkeys')
		if !isset(hotkeyslist)
			return
		for i, line in StrSplit(hotkeyslist,'`n','`r')
		{
			name := RegExReplace(line,'^([^=]+)=.*','$1')
			key  := IniRead(this.ini, 'Hotkeys', name)
			Title := IniRead(this.ini, 'Title', name, '')
			triggerType := IniRead(this.ini, 'Dropdown', name, 2) + 0

			if !IsSet(%name%)
				continue

			; Skip disabled triggers
			if (triggerType = 0 || triggerType = 4)
				continue

			HotIfWinActive Title
			try
			{
				if triggerType = 3
					Hotstring('::' key, %name%, 'on')
				else
					Hotkey(key, %name%, 'on')
			}
			HotIfWinActive
		}
	}

	; ===================== Tray Management =====================

	static UpdateTrayLabel(name, oldTrayText)
	{
		action := this.Actions[name]
		if action.triggerType = 3
			newTrayText := action.label '`t::' action.trigger
		else
			newTrayText := action.label '`t' this.HKToString(action.trigger)

		if oldTrayText != newTrayText
			try this.tray.Rename(oldTrayText, newTrayText)

		action.trayText := newTrayText

		if action.disabled
		{
			try this.tray.Disable(action.trayText)
		}
		else
		{
			try this.tray.Enable(action.trayText)
		}
	}

	static HotkeyRemove(callback)
	{
		Name := callback.name
		action := this.Actions[name]
		this.DeactivateTrigger(name)
		try this.tray.Disable(action.trayText)
	}

	; ===================== Utility =====================

	static reset()
	{
		this.Actions := Map()
		this.tray.delete()
		try FileDelete this.ini
	}

	static HKToString(hk)
	{
		if !hk
			return

		temphk := []

		if InStr(hk, '#')
			temphk.Push('Win+')
		if InStr(hk, '^')
			temphk.Push('Ctrl+')
		if InStr(hk, '+')
			temphk.Push('Shift+')
		if InStr(hk, '!')
			temphk.Push('Alt+')

		hk := RegExReplace(hk, '[#^+!]')
		for mod in temphk
			fixedMods .= mod

		hk := StrReplace(hk,'Xbutton','Special Button ')

		return (fixedMods ?? '') StrUpper(hk)
	}

}
