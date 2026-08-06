# Installs the Claude usage helper to start HIDDEN at every login.
# Creates a Startup shortcut pointing at run-helper-hidden.vbs IN PLACE, so the
# repo folder can live anywhere (and be moved with the shortcut re-created).
#
# Run once:   powershell -NoProfile -ExecutionPolicy Bypass -File .\install-at-login.ps1
# Uninstall:  powershell -NoProfile -ExecutionPolicy Bypass -File .\install-at-login.ps1 -Uninstall

param([switch]$Uninstall)

$vbs     = Join-Path $PSScriptRoot 'run-helper-hidden.vbs'
$startup = [Environment]::GetFolderPath('Startup')
$lnk     = Join-Path $startup 'ClaudeUsageHelper.lnk'

if ($Uninstall) {
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force; Write-Host "Removed $lnk" -ForegroundColor Yellow }
    else { Write-Host "Nothing to remove ($lnk not present)." }
    Write-Host "Note: this does not stop an already-running helper. End it via Task Manager or reboot."
    return
}

if (-not (Test-Path -LiteralPath $vbs)) { Write-Host "Cannot find $vbs" -ForegroundColor Red; return }

$sh = New-Object -ComObject WScript.Shell
$s  = $sh.CreateShortcut($lnk)
$s.TargetPath       = 'wscript.exe'
$s.Arguments        = '"' + $vbs + '"'
$s.WorkingDirectory = $PSScriptRoot
$s.WindowStyle      = 7
$s.Description      = 'Claude Usage helper (starts hidden at login)'
$s.Save()

Write-Host "Installed login shortcut: $lnk" -ForegroundColor Green
Write-Host "The helper will start hidden at each login."
Write-Host ""
Write-Host "Start it right now (no logout needed):" -ForegroundColor Cyan
Write-Host "  wscript `"$vbs`""
Write-Host "Verify:  open http://127.0.0.1:8787/usage in a browser."
