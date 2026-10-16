# Stops the background ytm-oled.ps1 process.
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*ytm-oled.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host "Stopped PID $($_.ProcessId)" }
