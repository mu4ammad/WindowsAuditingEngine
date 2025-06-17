# Complete Security Alert Engine Installation

Write-Host "🚨 Installing Security Alert Engine..." -ForegroundColor Green

# Check admin privileges
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Restarting as administrator..." -ForegroundColor Yellow
    Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    exit
}

$ServicePath = "C:\SecurityLogs"

# Step 1: Install the main service
Write-Host "Step 1: Installing main service..." -ForegroundColor Yellow
& "$ServicePath\SecurityAlertService.ps1" -Install

# Step 2: Create all shortcuts
Write-Host "Step 2: Creating desktop shortcuts..." -ForegroundColor Yellow
& "$ServicePath\CreateShortcuts.ps1"

# Step 3: Setup auto-startup
Write-Host "Step 3: Setting up auto-startup..." -ForegroundColor Yellow
& "$ServicePath\SetupAutoStartup.ps1"

# Step 4: Start tray manager
Write-Host "Step 4: Starting system tray manager..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ServicePath\SecurityTrayManager.ps1`"" -WindowStyle Hidden

Write-Host "`n✅ Installation Complete!" -ForegroundColor Green
Write-Host "`nWhat's installed:" -ForegroundColor Cyan
Write-Host "• System tray manager (running now)" -ForegroundColor White
Write-Host "• Desktop shortcuts for easy access" -ForegroundColor White
Write-Host "• Auto-startup with Windows" -ForegroundColor White
Write-Host "• Background monitoring service" -ForegroundColor White

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Look for the shield icon in your system tray" -ForegroundColor White
Write-Host "2. Right-click it for options" -ForegroundColor White
Write-Host "3. Click 'Auto-Start Everything' to begin monitoring" -ForegroundColor White

Write-Host "`nPress any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")