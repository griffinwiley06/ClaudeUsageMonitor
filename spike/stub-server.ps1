# Phase 0 stub server for the Ping Spike.
# Serves http://127.0.0.1:8787/ping with permissive CORS. 127.0.0.1 ONLY.
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -File .\stub-server.ps1
# Stop: Ctrl+C

$prefix = 'http://127.0.0.1:8787/'
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-Host "Could not bind $prefix" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "If port 8787 is in use, close the other process or change the port in both this file and the widget." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Ping stub listening on $prefix" -ForegroundColor Green
Write-Host "Test it in a browser:  ${prefix}ping" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray
Write-Host ""

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response

        $res.Headers.Add('Access-Control-Allow-Origin', '*')
        $res.Headers.Add('Access-Control-Allow-Methods', 'GET, OPTIONS')
        $res.Headers.Add('Access-Control-Allow-Headers', '*')
        $res.Headers.Add('Cache-Control', 'no-store')

        $stamp = (Get-Date -Format 'HH:mm:ss')
        $origin = $req.Headers['Origin']
        if ([string]::IsNullOrEmpty($origin)) { $origin = '(none)' }

        if ($req.HttpMethod -eq 'OPTIONS') {
            $res.StatusCode = 204
            $res.Close()
            Write-Host ("{0}  OPTIONS {1}   origin={2}" -f $stamp, $req.Url.AbsolutePath, $origin) -ForegroundColor DarkGray
            continue
        }

        $payload = @{
            pong = $true
            msg  = 'spike-ok'
            ts   = (Get-Date).ToString('o')
            path = $req.Url.AbsolutePath
        } | ConvertTo-Json -Compress

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $res.ContentType = 'application/json'
        $res.StatusCode = 200
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
        $res.Close()

        # The 'origin' printed here is the WIDGET's origin when the request comes
        # from the keyboard LCD -- that tells us the webview's scheme.
        Write-Host ("{0}  {1} {2} -> 200   origin={3}" -f $stamp, $req.HttpMethod, $req.Url.AbsolutePath, $origin) -ForegroundColor Green
    }
} finally {
    $listener.Stop()
    $listener.Close()
    Write-Host "Stub stopped." -ForegroundColor DarkGray
}
