; SetCaptionColor — Change window title bar color via DWM (Windows 11 22000+)
; Color format: 0x00BBGGRR   e.g. Red=0x000000FF  Green=0x0000FF00  Default=0xFFFFFFFF
; Source: S:\lib\v2\Change WinTitleColor\WinTitleColor.ahk by Xeo786

SetCaptionColor(hwnd, color) {
    if VerCompare(A_OSVersion, "10.0.22000") >= 0 {
        DllCall("dwmapi\DwmSetWindowAttribute",
                "ptr", hwnd,
                "int", 35,
                "int*", color,
                "int", 4)
    }
}
