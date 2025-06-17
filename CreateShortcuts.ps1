# Create Desktop Shortcuts for Security Alert Engine

$ServicePath = "C:\SecurityLogs"
$DesktopPath = [Environment]::GetFolderPath("Desktop")

# Create WScript Shell object for shortcuts
$WshShell = New-Object -comObject WScript.Shell

# 1. System Tray Manager Shortcut
$TrayShortcut = $WshShell.CreateShortcut("$DesktopPath\Security Alert Manager.lnk")
$TrayShortcut.TargetPath = "powershell.exe"
$TrayShortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ServicePath\SecurityTrayManager.ps1`""
$TrayShortcut.Description = "Security Alert Engine System Tray Manager"
$TrayShortcut.IconLocation = "shell32.dll,77"  # Shield icon
$TrayShortcut.Save()

# 2. Quick Dashboard Shortcut
$DashboardShortcut = $WshShell.CreateShortcut("$DesktopPath\Security Dashboard.lnk")
$DashboardShortcut.TargetPath = "http://localhost:8080"
$DashboardShortcut.Description = "Open Security Alert Dashboard"
$DashboardShortcut.IconLocation = "shell32.dll,14"  # Computer icon
$DashboardShortcut.Save()

# 3. Quick Start Service Shortcut
$StartShortcut = $WshShell.CreateShortcut("$DesktopPath\Start Security Monitoring.lnk")
$StartShortcut.TargetPath = "powershell.exe"
$StartShortcut.Arguments = "-ExecutionPolicy Bypass -File `"$ServicePath\SecurityAlertService.ps1`" -Start"
$StartShortcut.Description = "Start Security Monitoring Service"
$StartShortcut.IconLocation = "shell32.dll,131"  # Play icon
$StartShortcut.Save()

# 4. Installation Shortcut
$InstallShortcut = $WshShell.CreateShortcut("$DesktopPath\Install Security Service.lnk")
$InstallShortcut.TargetPath = "powershell.exe"
$InstallShortcut.Arguments = "-ExecutionPolicy Bypass -File `"$ServicePath\SecurityAlertService.ps1`" -Install"
$InstallShortcut.Description = "Install Security Alert Service"
$InstallShortcut.IconLocation = "shell32.dll,162"  # Settings icon
$InstallShortcut.Save()

# 5. Auto-Start Everything Batch File
$AutoStartBatch = @'
@echo off
title Security Alert Engine - Auto Start
echo Starting Security Alert Engine...
echo.

echo [1/3] Starting monitoring service...
powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\SecurityLogs\SecurityAlertService.ps1" -Start
timeout /t 3 /nobreak >nul

echo [2/3] Starting dashboard...
powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\SecurityLogs\SecurityAlertService.ps1" -Dashboard
timeout /t 3 /nobreak >nul

echo [3/3] Opening dashboard in browser...
start http://localhost:8080

echo.
echo ✅ Security Alert Engine started successfully!
echo Dashboard: http://localhost:8080
echo.
echo This window will close in 5 seconds...
timeout /t 5 /nobreak >nul
'@

$AutoStartBatch | Out-File "$DesktopPath\Auto-Start Security Engine.bat" -Encoding ASCII

Write-Host "✅ Created desktop shortcuts:" -ForegroundColor Green
Write-Host "• Security Alert Manager.lnk (System Tray)" -ForegroundColor White
Write-Host "• Security Dashboard.lnk (Direct Dashboard)" -ForegroundColor White
Write-Host "• Start Security Monitoring.lnk (Start Service)" -ForegroundColor White
Write-Host "• Install Security Service.lnk (Installation)" -ForegroundColor White
Write-Host "• Auto-Start Security Engine.bat (Everything)" -ForegroundColor White