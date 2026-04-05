$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "ChatGPTWebV15 Helper.lnk"

if (Test-Path $shortcutPath) {
    Remove-Item $shortcutPath -Force
    Write-Output "Removed $shortcutPath"
} else {
    Write-Output "No startup shortcut found."
}
