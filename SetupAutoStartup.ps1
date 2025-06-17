# Add Security Alert Engine to Windows Startup

$ServicePath = "C:\SecurityLogs"
$StartupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

# Create startup shortcut for tray manager
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$StartupPath\Security Alert Engine.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ServicePath\SecurityTrayManager.ps1`""
$Shortcut.Description = "Security Alert Engine System Tray Manager"
$Shortcut.IconLocation = "shell32.dll,77"
$Shortcut.Save()

Write-Host "✅ Security Alert Engine added to Windows startup!" -ForegroundColor Green
Write-Host "The system tray manager will start automatically when Windows boots." -ForegroundColor White
Write-Host "You can disable this by removing the shortcut from:" -ForegroundColor Yellow
Write-Host "$StartupPath" -ForegroundColor Cyan