#Requires AutoHotkey v2.0.2+
#Include UIA.ahk

winEl := UIA.ElementFromHandle("Signal ahk_exe Signal.exe")

winEl.FindAll({Type: "Button", AutomationId: "radix-_r_k_"}, "Exact")[1].Highlight()
