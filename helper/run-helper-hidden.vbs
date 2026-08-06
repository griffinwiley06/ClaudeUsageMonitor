' Launches the Claude usage helper with NO visible window.
' Self-locating: runs usage-helper.ps1 sitting in the SAME folder as this file,
' so the repo works from any path (used by install-at-login.ps1 for run-at-login).
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
scriptDir  = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(scriptDir, "usage-helper.ps1")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptPath & """", 0, False
