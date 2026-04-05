$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "ChatGPTWebV15 Helper.lnk"
$helperVbs = Join-Path $PSScriptRoot "launch-hidden.vbs"
$wscript = Join-Path $env:SystemRoot "System32\wscript.exe"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $wscript
$shortcut.Arguments = "`"$helperVbs`""
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.WindowStyle = 7
$shortcut.Description = "Launch ChatGPTWebV15 Helper in the background"
$shortcut.Save()

Write-Output "Startup shortcut installed at $shortcutPath"
