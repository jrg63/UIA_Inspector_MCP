#Requires AutoHotkey v2.0.2+
#Include <UIA>

WinActivate("Birder's Diary ahk_exe BDV63.exe")
WinWaitActive("Birder's Diary ahk_exe BDV63.exe")

winEl := UIA.ElementFromHandle("Birder's Diary ahk_exe BDV63.exe")

featuresMenu := winEl.FindFirst({Type: "MenuItem", Name: "Features"})
featuresMenu.Expand()
Sleep(200)

; Reports has AccessKey "r" — find it in the popup menu window (#32768)
popup := UIA.ElementFromHandle("ahk_class #32768")
reportsItem := popup.FindFirst({Name: "Reports", Type: "MenuItem"})
reportsItem.Invoke()
