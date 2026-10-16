# Stops the OLED display and removes it from Windows startup.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $here 'stop.ps1')
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'YouTube Music OLED.lnk'
if (Test-Path $lnk) { Remove-Item $lnk; Write-Host 'Removed from startup.' }
