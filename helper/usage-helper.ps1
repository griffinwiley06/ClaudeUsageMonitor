# Claude Usage Helper  (Phase 1)
# Serves your Claude 5-hour / 7-day usage as JSON on http://127.0.0.1:<port>/usage
# for the iCUE keyboard-LCD widget to poll.
#
# Data source: the Claude desktop app already polls the authenticated usage
# endpoint and caches the result to %APPDATA%\Claude\plan-usage-history.json
# every ~5 minutes. We read THAT file. No token is ever read, stored, or logged.
#
# Binds to 127.0.0.1 only. Serves last-known-good with a stale flag on failure.

# ===================== CONFIG =====================
$Port              = 8787   # must match the widget's endpoint
$CacheTtlSeconds   = 60     # re-read the source file at most once per this window
$StaleAfterSeconds = 660    # a sample older than this (~2 missed 5-min polls) => stale
# =================================================


# =====================================================================
#  DATA-SOURCE ADAPTER  --  THE ONLY PLACE THAT KNOWS THE FILE'S SHAPE
# ---------------------------------------------------------------------
#  This endpoint/format is undocumented and unsupported by Anthropic and
#  MAY CHANGE OR DISAPPEAR. If the numbers stop updating, everything you
#  need to fix is in THIS function -- nowhere else in this file.
#
#  Current format of %APPDATA%\Claude\plan-usage-history.json (version 2):
#    { "version":2, "samples":[ {"t":<epochMs>,"org":"<uuid>",
#                                "u":{"fh":<5h %>,"sd":<7d %>}}, ... ] }
#    fh = five-hour used percentage,  sd = seven-day used percentage.
#  We take the newest sample by timestamp.
#
#  Returns a hashtable:
#    @{ ok=$true;  fh=<int>; sd=<int>; sampleTimeMs=<int64>; org=<string>;
#       fhReset=<string|null>; sdReset=<string|null> }
#    @{ ok=$false; reason=<string> }   on any problem
# =====================================================================
function Read-UsageSource {
    # Resolve the cache file across possible install layouts (newest wins):
    #  1) MSIX / Microsoft Store packaged Claude app -- the REAL path a normal
    #     (non-packaged) shell can read. This is the one that matters when the
    #     helper runs from your own console or at login.
    #  2) Classic / non-packaged install, or the virtualized %APPDATA% view.
    $patterns = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Claude*\LocalCache\Roaming\Claude\plan-usage-history.json'),
        (Join-Path $env:APPDATA      'Claude\plan-usage-history.json')
    )
    $file = $patterns |
        ForEach-Object { Get-ChildItem -Path $_ -ErrorAction SilentlyContinue } |
        Sort-Object LastWriteTime | Select-Object -Last 1
    if (-not $file) { return @{ ok = $false; reason = 'source-missing' } }
    $path = $file.FullName

    # Retry a few times: the desktop app rewrites this file periodically, so a
    # read can momentarily catch it mid-write (a transient parse error).
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $json    = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $samples = $json.samples
            if (-not $samples -or @($samples).Count -eq 0) { return @{ ok = $false; reason = 'no-samples' } }

            $latest = @($samples) | Sort-Object -Property { [int64]$_.t } | Select-Object -Last 1
            if ($null -eq $latest.u -or $null -eq $latest.u.fh -or $null -eq $latest.u.sd) {
                return @{ ok = $false; reason = 'schema-changed' }
            }

            return @{
                ok           = $true
                fh           = [int]$latest.u.fh
                sd           = [int]$latest.u.sd
                sampleTimeMs = [int64]$latest.t
                org          = [string]$latest.org
                fhReset      = $null   # reset times are not present in this local source
                sdReset      = $null
                srcPath      = $path
            }
        } catch {
            Start-Sleep -Milliseconds 150   # likely mid-write; try again
        }
    }
    return @{ ok = $false; reason = 'parse-error' }
}
# =====================================================================


# ------------------- cache + payload builder -------------------
$script:lastGood     = $null   # last successful Read-UsageSource result
$script:cache        = $null   # last built payload (served for up to CacheTtlSeconds)
$script:cacheAtTicks = 0

function Build-Payload {
    $src   = Read-UsageSource
    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if ($src.ok) { $script:lastGood = $src }

    $use = if ($src.ok) { $src } else { $script:lastGood }

    if ($null -eq $use) {
        # We have never had a good sample (source missing/corrupt from the start).
        return [ordered]@{
            five_hour   = [ordered]@{ used_percentage = $null; resets_at = $null }
            seven_day   = [ordered]@{ used_percentage = $null; resets_at = $null }
            status        = 'no_data'
            source_reason = $src.reason
            stale       = $true
            as_of       = $null
            age_seconds = $null
            source      = 'desktop-cache'
            served_at   = (Get-Date).ToString('o')
        }
    }

    $ageSec  = [int][math]::Round(($nowMs - $use.sampleTimeMs) / 1000.0)
    $isStale = (-not $src.ok) -or ($ageSec -gt $StaleAfterSeconds)
    $status  = if ($isStale) { 'stale' } else { 'ok' }
    $asOf    = [DateTimeOffset]::FromUnixTimeMilliseconds($use.sampleTimeMs).ToLocalTime().ToString('o')

    return [ordered]@{
        five_hour   = [ordered]@{ used_percentage = $use.fh; resets_at = $use.fhReset }
        seven_day   = [ordered]@{ used_percentage = $use.sd; resets_at = $use.sdReset }
        status        = $status
        source_reason = $(if ($src.ok) { 'ok' } else { $src.reason })
        stale       = [bool]$isStale
        as_of       = $asOf
        age_seconds = $ageSec
        source      = 'desktop-cache'
        source_path = $use.srcPath
        org         = $use.org
        served_at   = (Get-Date).ToString('o')
    }
}

function Get-CachedPayload {
    $nowTicks = [DateTime]::UtcNow.Ticks
    if ($script:cache -and ((($nowTicks - $script:cacheAtTicks) / 1e7) -lt $CacheTtlSeconds)) {
        return $script:cache
    }
    $payload = Build-Payload
    # Never cache a "no_data" result -- otherwise one transient read failure at
    # startup would be served for a whole 60s window. Retry on the next request.
    if ($payload.status -ne 'no_data') {
        $script:cache        = $payload
        $script:cacheAtTicks = $nowTicks
    }
    return $payload
}


# ------------------- HTTP server (127.0.0.1 only) -------------------
$prefix   = "http://127.0.0.1:$Port/"
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-Host "FATAL: could not bind $prefix" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Port $Port may be in use (leftover spike stub?). Close it or change `$Port." -ForegroundColor Yellow
    exit 1
}

Write-Host "Claude usage helper listening on ${prefix}usage  (Ctrl+C to stop)" -ForegroundColor Green

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $res = $ctx.Response
        try {
            $payload = Get-CachedPayload
            $body    = $payload | ConvertTo-Json -Depth 6 -Compress
            $bytes   = [System.Text.Encoding]::UTF8.GetBytes($body)

            $res.Headers.Add('Access-Control-Allow-Origin', '*')
            $res.Headers.Add('Access-Control-Allow-Methods', 'GET, OPTIONS')
            $res.Headers.Add('Access-Control-Allow-Headers', '*')
            $res.Headers.Add('Cache-Control', 'no-store')
            $res.ContentType    = 'application/json'
            $res.StatusCode     = if ($ctx.Request.HttpMethod -eq 'OPTIONS') { 204 } else { 200 }

            if ($res.StatusCode -eq 200) {
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            }
        } catch {
            try { $res.StatusCode = 500 } catch {}
        } finally {
            $res.Close()
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
