# Starts the OLED display now and adds it to Windows startup (current user only).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$vbs = Join-Path $here 'start-hidden.vbs'

$startup = [Environment]::GetFolderPath('Startup')
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $startup 'YouTube Music OLED.lnk'))
$lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
$lnk.Arguments = '"' + $vbs + '"'
$lnk.WorkingDirectory = $here
$lnk.Description = 'Shows the current media track on the SteelSeries GameDAC OLED'
$lnk.Save()
Write-Host "Added to startup: $startup\YouTube Music OLED.lnk"

& (Join-Path $here 'stop.ps1')
Start-Process wscript.exe ('"' + $vbs + '"')
Write-Host 'Started. Play something and check the GameDAC screen.'
