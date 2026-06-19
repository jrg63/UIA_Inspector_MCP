# Apply AHKUtils code style to an AHK file
param($TargetFile)

if (-not $TargetFile) {
    Write-Host "Usage: _style_fix.ps1 <file.ahk>"
    exit 1
}

$lines = Get-Content $TargetFile -Encoding UTF8
$result = [System.Collections.ArrayList]@()
$i = 0

while ($i -lt $lines.Count) {
    $line = $lines[$i]
    
    # Function definition: _Name(...) { -> _Name(...) then { on next line
    if (($line -match '^(\s*)(_[A-Z]\w*\(.*\))\s*\{$') -or 
        ($line -match '^(\s*)([A-Z]\w*\(.*\))\s*\{$' -and $line -notmatch '^\s*(if|else|for|while|loop|try|catch|switch|static)\b')) {
        [void]$result.Add(($matches[1] + $matches[2]))
        [void]$result.Add(($matches[1] + "{"))
        $i++
        continue
    }
    
    # try { -> try then { on next line
    if ($line -match '^(\s*)try \{$') {
        [void]$result.Add(($matches[1] + "try"))
        [void]$result.Add(($matches[1] + "{"))
        $i++
        continue
    }
    
    # } catch as varname { -> } then catch as varname then {
    if ($line -match '^(\s*)\} catch as (\w+) \{$') {
        [void]$result.Add(($matches[1] + "}"))
        [void]$result.Add(($matches[1] + "catch as " + $matches[2]))
        [void]$result.Add(($matches[1] + "{"))
        $i++
        continue
    }
    
    # } catch { -> } then catch then {
    if ($line -match '^(\s*)\} catch \{$') {
        [void]$result.Add(($matches[1] + "}"))
        [void]$result.Add(($matches[1] + "catch"))
        [void]$result.Add(($matches[1] + "{"))
        $i++
        continue
    }
    
    # } catch STMT -> } then catch then STMT
    if ($line -match '^(\s*)\} catch (.+)$') {
        [void]$result.Add(($matches[1] + "}"))
        [void]$result.Add(($matches[1] + "catch"))
        [void]$result.Add(($matches[1] + "    " + $matches[2]))
        $i++
        continue
    }
    
    # } else { -> } then else then {
    if ($line -match '^(\s*)\} else \{$') {
        [void]$result.Add(($matches[1] + "}"))
        [void]$result.Add(($matches[1] + "else"))
        [void]$result.Add(($matches[1] + "{"))
        $i++
        continue
    }
    
    # for var in expr { -> for ... then {
    if ($line -match '^(\s*)(for \w+(?:, \w+)? in .+?) \{$') {
        [void]$result.Add(($matches[1] + $matches[2]))
        [void]$result.Add(($matches[1] + "{"))
        $i++
        continue
    }
    
    # loop { -> loop then {
    if ($line -match '^(\s*)loop \{$') {
        [void]$result.Add(($matches[1] + "loop"))
        [void]$result.Add(($matches[1] + "{"))
        $i++
        continue
    }
    
    # while expr { -> while (expr) then {
    if ($line -match '^(\s*)while (.+?) \{$') {
        $cond = $matches[2]
        if ($cond -notmatch '^\(') { $cond = "($cond)" }
        [void]$result.Add(($matches[1] + "while " + $cond))
        [void]$result.Add(($matches[1] + "{"))
        $i++
        continue
    }
    
    # if expr { -> if (expr) { (keep inline comment outside parens)
    if ($line -match '^(\s*)if (?!\()(.+?) \{($|\s*;.*$)') {
        $cond = $matches[2]
        $trailer = $matches[3]
        $comment = ""
        if ($cond -match '^(.+?)  ;(.+)$') {
            $cond = $matches[1]
            $comment = "  ;" + $matches[2]
        } elseif ($cond -match '^(.+?) ;(.+)$') {
            $cond = $matches[1]
            $comment = " ;" + $matches[2]
        }
        [void]$result.Add(($matches[1] + "if (" + $cond.TrimEnd() + ") {" + $comment))
        $i++
        continue
    }
    
    # if expr (no brace) -> if (expr) (keep comment outside)
    if ($line -match '^(\s*)if (?!\()(.+?)$' -and $line -notmatch '\{$') {
        $cond = $matches[2]
        $comment = ""
        if ($cond -match '^(.+?)  ;(.+)$') {
            $cond = $matches[1]
            $comment = "  ;" + $matches[2]
        } elseif ($cond -match '^(.+?) ;(.+)$') {
            $cond = $matches[1]
            $comment = " ;" + $matches[2]
        }
        [void]$result.Add(($matches[1] + "if (" + $cond.TrimEnd() + ")" + $comment))
        $i++
        continue
    }
    
    # else if expr -> else if (expr) (keep comment outside)
    if ($line -match '^(\s*)else if (?!\()(.+?)$') {
        $cond = $matches[2]
        $comment = ""
        if ($cond -match '^(.+?)  ;(.+)$') {
            $cond = $matches[1]
            $comment = "  ;" + $matches[2]
        } elseif ($cond -match '^(.+?) ;(.+)$') {
            $cond = $matches[1]
            $comment = " ;" + $matches[2]
        }
        [void]$result.Add(($matches[1] + "else if (" + $cond.TrimEnd() + ")" + $comment))
        $i++
        continue
    }
    
    # return expr -> return(expr) for simple single-value returns
    if ($line -match '^(\s*)return (?!\()(.+)$' -and $line -notmatch '^\s*return\s*$') {
        $expr = $matches[2]
        if ($expr -notmatch '^\s*(\{|\[|Map\(|JSON\.|UIA\.|DllCall|EnumChildWindows|ProcessGetName|Format|Integer|String|WinGetTitle|WinGetClass|WinGetPID|WinExist|_BuildFullElementResult|_MakeCacheRequest|_HandleInspectAtCursor)') {
            if ($expr -notmatch ';') {
                [void]$result.Add(($matches[1] + "return(" + $expr + ")"))
                $i++
                continue
            }
        }
    }
    
    [void]$result.Add($line)
    $i++
}

$result -join [Environment]::NewLine | Set-Content -Path $TargetFile -NoNewline -Encoding UTF8
Write-Host "Style transformation complete: $($result.Count) lines"
