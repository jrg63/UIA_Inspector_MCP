#Requires Autohotkey v2.0-
/**
 * ============================================================================ *
 * Want a clear path for learning AutoHotkey?                                   *
 * Take a look at our AutoHotkey courses here: the-Automator.com/Discover       *
 * They're structured in a way to make learning AHK EASY                        *
 * And come with a 200% moneyback guarantee so you have NOTHING to risk!        *
 * ============================================================================ *
 * @Author   : Xeo786                                                           *
 * @Homepage : the-automator.com                                                *
 * @devPath  : S:\lib\v2\Notify\Notify\NotifyV2.ahk							    *
 * @Version  : v2.4.1                                                           *
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

/*
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;;;;;;;;;;;;;;;Notify AHK V2;;;;;;;;;;;;;;;;;
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	Header, Body, and Background colors supported: Black,Silver,Gray,White,Maroon,Red,Purple,Fuchsia,Green,Lime,Olive,Yellow,Navy,Blue,Teal,Aqua

	'Duration' is how long you want the notice to be displayed before it disappears.
	It should be number, Use 0 to leave it on screen indefintiely until user clicks.

	Be sure to Include this library when using from another script.
	Example:  #Include <Notifyv2>

*/
#Requires Autohotkey v2.0+
For arg in A_ARGS
{
	if A_Index &1
	{
		; msgbox arg "`n" A_ARGS[A_Index + 1]
		switch arg {
		case '-BDText':
			msg := A_ARGS[A_Index + 1]
		Case '-Link':
			;msgbox arg "`n" A_ARGS[A_Index + 1]
			href := A_ARGS[A_Index + 1]

			if !A_IsCompiled
			&& href ~= '"'
				href := RegExReplace(href,'\"+','"')
			else if !A_IsCompiled
			&& href ~= '"' == false
				href := RegExReplace(href,'<a href=(.*?)>','<a href="$1">')

			msg := {link: href}
		case '-GenIcon', '-HDFontSize', '-BDFontSize','-GenDuration','-GenIconSize':
			Notify.Default.%StrReplace(Trim(arg), '-')% := number(A_ARGS[A_Index + 1])
		case '-HDText', '-HDFontColor','-HDFont','-BDText','-BDFontColor', '-BDFont','-GenBGColor','-GenSound':
			Notify.Default.%StrReplace(Trim(arg), '-')% := A_ARGS[A_Index + 1]
		default:
		}
	}
}
if IsSet(msg)
{
	Notify.show(msg)
}

Class Notify
{
	; do not modify this variable directly because
	; it would cause the main script to break
	static _Default := {
		HDText        : "",
		HDFontSize    : 16,
		HDFont        : "Impact",
		HDFontColor   : "0x298939",
		BDText        : "Click to Callback",
		BDFontSize    : 12,
		BDFontColor   : "Black",
		BDFont        : "Book Antiqua",
		GenBGColor    : "0xFFD23E",
		GenDuration   : 3,
		GenSound      : "",
		GenIcon	      : "",
		GenIconSize   : 30,
		GenMonitor    : MonitorGetPrimary(),
		GenLoc        : 'RightBottom',
	}
	Static Default
	{
		set => Notify._default := value
		get {
			static default_props := Map(
			'HDText'        , "",
			'HDFontSize'    , 14,
			'HDFont'        , "Impact",
			'HDFontColor'   , "Black",
			'BDFontSize'    , 10,
			'BDFontColor'   , "0x298939",
			'BDFont'        , "Book Antiqua",
			'GenBGColor'    , "0xFFD23E",
			'GenDuration'   , 3,
			'GenSound'      , "",
			'GenIcon'       , "",
			'GenIconSize'   , 30,
			'GenMonitor'    , MonitorGetPrimary(),
			'GenLoc'        , 'RightBottom',
			)
			for prop in default_props
				if !Notify._Default.HasProp(prop)
					Notify._Default.%prop% := default_props[prop]

			return Notify._default
		}
	}
	Static wavList := "Sound List:`nName" ; `t`t Path"
	Static wav := Notify.GetSoundFiles()

	static Show(Input)
	{
		Switch(Type(Input))
		{
		Case "String":
			this.HDText      := Notify.Default.HDText
			this.HDSize      := Notify.Default.HDFontSize
			this.HDColor     := Notify.Default.HDFontColor
			this.HDFont      := Notify.Default.HDFont
			this.Text        := input
			this.BDSize      := Notify.Default.BDFontSize
			this.BDColor     := Notify.Default.BDFontColor
			this.BDFont      := Notify.Default.BDFont
			this.Duration    := Notify.Default.GenDuration
			this.Color       := Notify.Default.GenBGColor
			this.Sound       := Notify.Default.GenSound
			this.GenIcon     := Notify.Default.GenIcon
			this.GenIconSize := Notify.Default.GenIconSize
			this.GenMonitor  := Notify.Default.GenMonitor
			this.GenLoc      := Notify.Default.GenLoc
			this.Link        := ""
			this.Callback    := 0
		Case "Object":
			this.HDText      := input.HasOwnProp("HDText")      ? input.HDText      : Notify.Default.HDText
			this.HDSize      := input.HasOwnProp("HDFontSize")  ? input.HDFontSize  : Notify.Default.HDFontSize
			this.HDColor     := input.HasOwnProp("HDFontColor") ? input.HDFontColor : Notify.Default.HDFontColor
			this.HDFont      := input.HasOwnProp("HDFont")      ? input.HDFont      : Notify.Default.HDFont
			this.BDSize      := input.HasOwnProp("BDFontSize")  ? input.BDFontSize  : Notify.Default.BDFontSize
			this.BDColor     := input.HasOwnProp("BDFontColor") ? input.BDFontColor : Notify.Default.BDFontColor
			this.BDFont      := input.HasOwnProp("BDFont")      ? input.BDFont      : Notify.Default.BDFont
			this.Color       := input.HasOwnProp("GenBGColor")  ? input.GenBGColor  : Notify.Default.GenBGColor
			this.Duration    := input.HasOwnProp("GenDuration") ? input.GenDuration : Notify.Default.GenDuration
			this.Sound       := input.HasOwnProp("GenSound")    ? input.GenSound    : Notify.Default.GenSound
			this.GenIcon     := input.HasOwnProp("GenIcon")     ? input.GenIcon     : Notify.Default.GenIcon
			this.GenIconSize := input.HasOwnProp("GenIconSize") ? input.GenIconSize : Notify.Default.GenIconSize
			this.GenMonitor  := input.HasOwnProp("GenMonitor")  ? input.GenMonitor  : Notify.Default.GenMonitor
			this.GenLoc      := input.HasOwnProp("GenLoc")      ? input.GenLoc      : Notify.Default.GenLoc
			this.Link        := input.HasOwnProp("Link")        ? input.Link        : ""
			this.Callback    := input.HasOwnProp("GenCallback") ? input.GenCallback : 0
			this.Text        := input.HasOwnProp("BDText")      ? input.BDText      : ""
		}
		Notify.Play(this.Sound)
		this.Notice := MultiGui(this)
		if this.Duration != 0
			this.Close()
		return this
	}

	static CloseAll()
	{
		guiclone := MultiGui.Guis.Clone()
		MultiGui.Guis := []
		for i, Gui in guiclone
			try Gui.Destroy()
	}

	Static CloseLast()
	{
		try Notify.Notice.Close()
	}

	Static Close()
	{
		fn := ObjBindMethod(this, "animation", this.Notice)
		Settimer fn, -(this.Duration * 1000)
	}

	static animation(Notice) => Notice.close()

	static Play(Sound)
	{
		if RegExMatch(Sound,'^\*\-?\d+')
		|| FileExist(Sound)
			return Soundplay(Sound)
		try SoundFile := Notify.wav[Sound]
		catch
			return
		if FileExist(SoundFile)
			Soundplay(SoundFile)
		return
	}

	Static GetSoundFiles()
	{
		wav := map()
		loop files, "C:\Windows\Media\*.wav"
		{
			name := RegExReplace(A_LoopFileName,"Windows |notify |Hardware |.wav")
			if InStr(name," ")
				continue
			this.wavList .= "`n"  name  ;(InStr(name,"Alarm") ? "`t" : StrLen(name) < 8 ? "`t`t":"`t" ) ": " A_LoopFileName
			wav[name] := A_LoopFileFullPath
		}

		loop files, A_ScriptDir "\res\*.wav"
		{
			name := StrReplace(A_LoopFileName,".wav")
			this.wavList .= "`n"  name ;(StrLen(name) < 8 ? "`t`t":"`t" ) ": " A_LoopFileName
			wav[name] := A_LoopFileFullPath
		}
		return wav
	}


	; method to list all supported Alert Sounds
	Static SoundList() => this.Show({HDText:"GenSound list`nSupported by Notify",BDText:'Copied to clipboard`n' A_Clipboard := this.wavList,GenDuration:0,GenSound:"Insert"})
	; method to List all Color
	Static ColorList()
	{
		Colors :="
		(
			Black
			Silver
			Gray
			White
			Maroon
			Red
			Purple
			Fuchsia
			Green
			Lime
			Olive
			Yellow
			Navy
			Blue
			Teal
			Aqua
		)"
		this.Show({HDText:"HD BD and Gen Colors`nSupported by Notify",BDText:'Copied to clipboard`n' A_Clipboard := Colors,GenDuration:0,GenSound:"Remove"})
	}
	; method to list all GenIcons
	Static GenIconList()
	{
		GenIconHelp :=
		(
			'GenIcon can be:
			• Integer from Shell32.dll
			• Image/Icon Path
			• Any of the following strings:
				o Critical
				o Question
				o Exclamation
				o Information
				o Security

			GenIconSize: is number where the hight and width are the same'
		)
		Notify.Show({
			HDText:"GenIcon List`nGenIcons number or address should be passed",
			BDFontSize:16,
			GenDuration:10,
			GenIcon:96,
			GenIconSize:50,
			BDText: GenIconHelp
		})
	}


	static IconPicker()
	{
		Count := 329, Shell := 1, Image := 0, icoFile := "shell32.dll", Height := A_ScreenHeight - 170 ;Define constants
		iGui := Gui('-MinimizeBox -MaximizeBox','Notify Icon Picker')
		iGui.OnEvent('Close',exit)
		LV := iGui.AddListView('h' Height ' w400 +Icon',['Number'])
		LV.OnEvent('click',ListClick)
		ImageListID := IL_Create(Count,10,true)
		LV.SetImageList(ImageListID)
		loop Count
		{
			pos := IL_Add(ImageListID,icoFile,A_Index)
			LV.Add("Icon" pos,A_index)
		}
		LV.ModifyCol(1,'autohdr')  ; Auto-adjust the column widths.
		LV.ModifyCol(2,'autohdr integer Center')  ; Auto-adjust the column widths.
		iGui.Show()
		return

		ListClick(obj,info){
			n := LV.getText(info )
			a_Clipboard := n ; "Menu, Tray, Icon, %A_WinDir%\system32\" IcoFile "," info " `;Set custom Script icon`n"
			tooltip 'Copied Icon Number ' n
			SetTimer( ToolTip, -800  )
		}

		exit(*)
		{
			iGui.Destroy()
		}
	}

	Static DisplayCheck()
	{
		MonitorCount := MonitorGetCount()
		MonitorPrimary := MonitorGetPrimary()
		Notify.show(
			{
				HDText:'Monitor Info',
				BDText: 'Monitor Count: ' MonitorCount '`nPrimary Monitor: ' MonitorPrimary '`nClick to close',
				GenDuration:0
			}
		)
		Loop MonitorCount
		{
			MonitorGet A_Index, &L, &T, &R, &B
			MonitorGetWorkArea A_Index, &WL, &WT, &WR, &WB
			Notify.show(
			{
				HDText:'Monitor:`t#' A_Index ,
				BDText: 
				(
				'Name:`t' MonitorGetName(A_Index) '
				Left:`t' L ' (' WL ' work)
				Top:`t' T ' (' WT ' work)
				Right:`t' R ' (' WR ' work)
				Bottom:`t' B ' (' WB ' work)
				`t`tClick to close'
				)
				,
				GenLoc: 'C',
				GenMonitor:a_index,
				GenDuration:0
			}
			)
		} 
	}

	static RemindClose(minutes:=1,timeoutSec:=3,sound:=true,repeat:=true)
	{
		reminderMinutes := (!repeat ? '-' : '') minutes * (60 * 1000)

		timeout := -(timeoutSec * 1000)
		; Change this to set how often you want reminders (in minutes)
		SetTimer(ShowScriptReminder, reminderMinutes)  ; Start timer checking if it is running, 		SetTimer(CloseLastNotification, timeout)  ;    ; Manually close the notification after 3 seconds -3000 = run once after 3 seconds

		;===== Reminder Function =====
		ShowScriptReminder() { ; Show notification that script is running.   Click the notification to exit the script    
			Notify.Show({
				HDText: A_ScriptName " is Still Running",  ; Header text
				BDText: "Click to exit",                   ; Body text
				GenBGColor: "Yellow",                      ; Background color
				GenIcon: "Information",                    ; Icon type
				GenCallback: ExitScript,                    ; Function to call when clicked
				GenSound:sound ? 'ding' : ''
			})
		

			;===== Exit when notification is clicked =====
			ExitScript(*) {
				ExitApp  ; Close the script
			}
		}
			;===== Close the notification after timeout =====
		CloseLastNotification() {
			Notify.CloseLast()  ; Close the most recent notification
		}
	}	
}

Class MultiGui
{
	static Guis := array()
	; Static Taskbar := MultiGui.GetTaskBarPos()
	Static Monitors := MultiGui.CalcMonitor()
	Static LastPOs := map() ;{x:0,y:0,w:0,h:0}
	Static ShellDll := A_WinDir "\System32\shell32.dll"
	Static user32Dll := A_WinDir "\system32\user32.dll"
	Static Warning := Map(
		"Exclamation",2,
		"Question",3,
		"Critical",4,
		"Information",5,
		"Security",7
	)
	__new(info)
	{
		if info.GenMonitor > MultiGui.Monitors.length 
			info.GenMonitor := MonitorGetPrimary()

		MyGui := Gui("-Caption +AlwaysOnTop +Owner +LastFound")
		MyGui.MarginX := 5
		MyGui.MarginY := 5
		MyGui.BackColor := info.Color
		if (Type(Info.GenIcon) = "Integer")
			MyGui.AddPicture("w" Info.GenIconSize " h" Info.GenIconSize " Icon" Info.GenIcon + 0, MultiGui.ShellDll)
		else if FileExist(Info.GenIcon)
			MyGui.AddPicture("w" Info.GenIconSize " h" Info.GenIconSize,Info.GenIcon )
		else if Info.GenIcon && InStr("Critical,Question,Exclamation,Information,Security",Info.GenIcon)
			MyGui.AddPicture("w" Info.GenIconSize " h" Info.GenIconSize " Icon" MultiGui.Warning[Info.GenIcon], MultiGui.user32Dll)

		MyGui.SetFont("c" info.HDColor " s" info.HDSize , info.HDFont )
		if info.HDText
			MyGui.Add("Text","x+m", info.HDText)
		MyGui.SetFont(opts := "c" info.BDColor " s" info.BDSize , info.BDFont )
		if info.Link
			MyGui.AddLink(, info.Link)
		else if info.Text
		{
			;MyGui.AddText("y+m",info.Text ) ;"xp yp+" this.Header.Font.Size +9.5, this.Body.Text)
			w := ''
			if StrLen(info.Text) > 300
				w := ' W400'
			MyGui.AddText("y+m" w,info.Text ) ;"xp yp+" this.Header.Font.Size +9.5, this.Body.Text)
		}
		MyGui.Show("Hide")
		This.MyGui := MyGui
		WinGetPos(&x,&y,&w,&h,MyGui)

		clickArea := MyGui.Add("Text", "x0 y0 w" . W . " h" . H . " BackgroundTrans")
		if info.Callback
		{
			clickArea.OnEvent("Click", info.Callback )
		    Info.Duration := 0
		}

		if Info.Duration = 0
			clickArea.OnEvent("Click", ObjBindMethod(this,"Close",MyGui) )
		MyGui.Monitors := info.GenMonitor
		MultiGui.Guis.Push(MyGui)

		; Allow an explicit "x123 y456" override (negatives too, for multi-monitor
		; setups where secondary monitors sit above/left of the primary).
		if RegExMatch(info.GenLoc,'(?=.*?(?<x>x-?\d+))(?=.*?(?<y>y-?\d+))',&Out)
			POS := Out.x ' ' Out.y, LOC := 'xy'
		else
			POs := MultiGui.GeneratePOS(info,x,y,w,h,&Loc)
		
		MyGui.Show(POS " NoActivate")
		WinGetPos(&x,&y,&w,&h,MyGui)
		MultiGui.LastPOs[info.GenMonitor LOC] := {x:x,y:y,w:w,h:h}
	}

	static GeneratePOS(info,x,y,w,h,&Loc)
	{
		n := info.GenMonitor
		Switch info.GenLoc, 0
		{
			; Position the toast near the mouse cursor. Offsets it down-right
			; by a small amount so it doesn't sit directly under the pointer,
			; then clamps to the current monitor's work area so the toast
			; never gets cut off at a screen edge.
			Case 'Mouse', 'M':
				Loc := 'MS'
				CoordMode('Mouse', 'Screen')                 ; screen-absolute mouse coords
				MouseGetPos(&mx, &my)
				offX := 20, offY := 20                       ; cursor-to-toast nudge
				; Figure out which monitor the mouse is on (library stores
				; 'x'=Left 'y'=Top 'w'=Right 'h'=Bottom, despite the names).
				monIdx := 0
				Loop MultiGui.Monitors.Length
				{
					m := MultiGui.Monitors[A_Index]
					if (mx >= m['x'] && mx <= m['w'] && my >= m['y'] && my <= m['h'])
					{
						monIdx := A_Index
						break
					}
				}
				if (!monIdx)
					monIdx := MonitorGetPrimary()
				m := MultiGui.Monitors[monIdx]
				nx := mx + offX
				ny := my + offY
				; If placing to the right/below would clip, flip to the other side of the cursor.
				if (nx + w > m['w'])
					nx := mx - w - offX
				if (ny + h > m['h'])
					ny := my - h - offY
				; Final clamp — keep the toast fully inside the monitor work area.
				if (nx < m['x'])
					nx := m['x']
				if (ny < m['y'])
					ny := m['y']
				POS := 'x' nx ' y' ny
			Case 'Center', 'C':
				Loc := 'C'
				
				; We are clculating the center position
				; to make sure that it displays correctly in all monitors
				; not only the primary monitor
				POS := "x" (MultiGui.Monitors[n]['x'] + MultiGui.Monitors[n]['w'])/2 - (w/2)  " y" (MultiGui.Monitors[n]['y'] + MultiGui.Monitors[n]['h'])/2 - (h/2)
			Case 'TopLeft','TL', 'LeftTop','LT':
				Loc := 'LT'
				if MultiGui.LastPOs.Has(n Loc)
					POS := "x" MultiGui.Monitors[n]['x'] " y" MultiGui.LastPOs[n Loc].y + MultiGui.LastPOs[n Loc].h +  1
				else
					POS := "x" MultiGui.Monitors[n]['x'] " y" MultiGui.Monitors[n]['y']
			Case 'TopRight','TR','RightTop','RT':
				Loc := 'RT'
				if MultiGui.LastPOs.Has(n Loc)
					POS := "x" MultiGui.Monitors[n]['w'] - w " y" MultiGui.LastPOs[n Loc].y + MultiGui.LastPOs[n Loc].h + 1
				else
					POS := "x" MultiGui.Monitors[n]['w'] - w " y" MultiGui.Monitors[n]['y'] 
			Case 'LeftBottom','LB','BottomLeft','BL':
				Loc := 'LB'
				if MultiGui.LastPOs.Has(n Loc)
					POS := "x" MultiGui.Monitors[n]['x'] " y" MultiGui.LastPOs[n Loc].y - h - 1
				else
					POS := "x" MultiGui.Monitors[n]['x'] " y" MultiGui.Monitors[n]['h'] - h
			Case 'RightBottom','RB','BottomRight','BR':
				Loc := 'BR'
				if MultiGui.LastPOs.Has(n Loc)
					POS := "x" MultiGui.Monitors[n]['w'] - w " y" MultiGui.LastPOs[n Loc].y - h - 1
				else
					POS := "x" MultiGui.Monitors[n]['w'] - w " y" MultiGui.Monitors[n]['h'] - h
			Default: ; default is right bottom
				Loc := 'BR'
				if MultiGui.LastPOs.Has(n Loc)
					POS := "x" MultiGui.Monitors[n]['w'] - w " y" MultiGui.LastPOs[n Loc].y - h - 1
				else
					POS := "x" MultiGui.Monitors[n]['w'] - w " y" MultiGui.Monitors[n]['h'] - h
		}
		return POS
	}


	Close(*)
	{
		delete := 0
		for i, Gui in MultiGui.Guis
		{
			try WinExist(this.MyGui)
			catch
				continue
			
			if this.MyGui.Hwnd = Gui.Hwnd
			{
				MultiGui.Guis.RemoveAt(i)
				MyGui := Gui
				; MyMonitor := Gui.Monitor
				try WinGetPos(&x,&y,&w,&h,MultiGui.Guis[i-1])
				catch
					try WinGetPos(&x,&y,&w,&h,MultiGui.Guis[i])
				delete := 1
			}
		}
		if Delete = 0
			return
		WinGetPos(&ix,&iy,&w,&h,MyGui)
		loop 50
		{
			If (!Mod(A_index, 18))
			{
				WinSetTransColor("Blue " 255 - A_index * 5,MyGui)
				MyGui.Move(iX += 10, iY)
				sleep 50
			}
		}

		this.MyGui.Destroy()
		;ahk; ORIGINAL (causes error):
		; if MultiGui.Guis.length = 0
		; 	for key, pos in MultiGui.LastPOs
		; 		MultiGui.LastPOs.Delete(key)

		; FIXED (collect keys first, then delete):
		If MultiGui.Guis.length = 0 
		{
			keysToDelete := []
			For key, pos in MultiGui.LastPOs
				keysToDelete.Push(key)
			For index, key in keysToDelete
				MultiGui.LastPOs.Delete(key)
		}

	}

	; Static GetTaskBarPos()
	; {
	; 	WinWait("ahk_class Shell_TrayWnd") ; incase windows starting and script load before taskbar exist then wait
	; 	WinGetPos(&x,&y,&w,&h, "ahk_class Shell_TrayWnd")
	; 	if x = 0 && y = 0 && w = A_ScreenWidth
	; 		Docked := "T"
	; 	else if x = 0 && y = 0 && h = A_ScreenHeight
	; 		Docked := "L"
	; 	else if x = 0 &&  y > 0 && w = A_ScreenWidth
	; 		Docked := "B"
	; 	else if x > 0 && y = 0 && h = A_ScreenHeight
	; 		Docked := "R"
	; 	return {x:x,y:y,w:w,h:h,Docked:Docked}
	; }

	Static CalcMonitor()
	{
		Monitors := []
		Loop  MonitorGetCount()
		{
			MonitorGetWorkArea A_Index, &L, &T, &R, &B
			Monitors.Push(Map('x',L,'y',T,'w',R,'h',B))
		}
		return Monitors
	}
	Static LastNotifyDisplay(notifyGui)
	{
		;CoordMode("Mouse","Screen")
		;MouseGetPos(&mx,&my,)
		WinGetPos(&mx,&my,,,notifyGui)
		Loop MonitorGetCount()
		{
			MonitorGet(a_index, &Left, &Top, &Right, &Bottom)
			if (Left <= mx && mx <= Right && Top <= my && my <= Bottom)
				Return MonitorGetName(a_index) ; DisplayPath[MonitorGetName(a_index)]
		}
		Return 1
	}
}
