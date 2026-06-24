$tcp = New-Object System.Net.Sockets.TcpClient
$tcp.Connect("127.0.0.1", 9876)
$stream = $tcp.GetStream()
$w = New-Object System.IO.StreamWriter($stream)
$r = New-Object System.IO.StreamReader($stream)
$req = '{"jsonrpc":"2.0","method":"list_windows","params":{"filter":"Notepad"},"id":1}' + "`n"
$w.Write($req)
$w.Flush()
$resp = $r.ReadLine()
$tcp.Close()
Write-Output $resp
