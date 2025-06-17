# Security Alert System Tray Manager - FIXED VERSION
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Hide the PowerShell console window
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0) # 0 = hide

# Configuration
$ServicePath = "C:\SecurityLogs"
$ServiceScript = "$ServicePath\SecurityAlertService.ps1"      # MONITORING ONLY
$DashboardScript = "$ServicePath\SecurityDashboard.ps1"      # DASHBOARD ONLY
$DashboardURL = "http://localhost:8080"

# Declare script-level variables
$script:serviceProcess = $null
$script:dashboardProcess = $null

# Create directories if needed
if (!(Test-Path $ServicePath)) {
    New-Item -ItemType Directory -Path $ServicePath -Force
}

# Function to run PowerShell commands hidden
function Invoke-HiddenPowerShell {
    param($ScriptPath, $Arguments = "")
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`" $Arguments"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    
    $process = [System.Diagnostics.Process]::Start($psi)
    return $process
}

# Function to check if service is running
function Test-ServiceRunning {
    try {
        $statusFile = "$ServicePath\ServiceStatus.json"
        if (Test-Path $statusFile) {
            $status = Get-Content $statusFile | ConvertFrom-Json
            $lastUpdate = [DateTime]$status.LastUpdate
            $timeDiff = (Get-Date) - $lastUpdate
            return $timeDiff.TotalMinutes -lt 5
        }
    } catch {}
    return $false
}

# Function to check if dashboard is accessible
function Test-DashboardRunning {
    try {
        $response = Invoke-WebRequest -Uri $DashboardURL -UseBasicParsing -TimeoutSec 3
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

# Function to cleanup processes
function Stop-AllProcesses {
    if ($script:serviceProcess -and !$script:serviceProcess.HasExited) {
        $script:serviceProcess.Kill()
        $script:serviceProcess = $null
    }
    if ($script:dashboardProcess -and !$script:dashboardProcess.HasExited) {
        $script:dashboardProcess.Kill()
        $script:dashboardProcess = $null
    }
    
    # Also kill any PowerShell processes running our scripts
    Get-Process powershell -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like "*SecurityAlertService*" -or $_.CommandLine -like "*SecurityDashboard*"
    } | Stop-Process -Force
}

# Create the system tray icon
$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Text = "Security Alert Engine"
$icon.Visible = $true
$icon.Icon = [System.Drawing.SystemIcons]::Shield

# Create context menu
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

# FIXED: Open Dashboard - Uses SecurityDashboard.ps1 ONLY
$openDashboard = New-Object System.Windows.Forms.ToolStripMenuItem
$openDashboard.Text = "Open Dashboard"
$openDashboard.Add_Click({
    try {
        if (Test-DashboardRunning) {
            Start-Process $DashboardURL
        } else {
            Write-Host "Starting dashboard from SecurityDashboard.ps1..." -ForegroundColor Green
            $script:dashboardProcess = Invoke-HiddenPowerShell $DashboardScript  # NO ARGUMENTS!
            Start-Sleep 3
            Start-Process $DashboardURL
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not open dashboard. Error: $($_.Exception.Message)", "Dashboard Error")
    }
})

$separator1 = New-Object System.Windows.Forms.ToolStripSeparator

# FIXED: Start Service - Uses SecurityAlertService.ps1 with -Start
$startService = New-Object System.Windows.Forms.ToolStripMenuItem
$startService.Text = "Start Monitoring"
$startService.Add_Click({
    try {
        Write-Host "Starting monitoring from SecurityAlertService.ps1..." -ForegroundColor Green
        $script:serviceProcess = Invoke-HiddenPowerShell $ServiceScript "-Start"
        $icon.BalloonTipTitle = "Security Alert Engine"
        $icon.BalloonTipText = "Monitoring service started"
        $icon.ShowBalloonTip(3000)
        Update-MenuItems
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not start monitoring service. Error: $($_.Exception.Message)", "Service Error")
    }
})

$stopService = New-Object System.Windows.Forms.ToolStripMenuItem
$stopService.Text = "Stop Monitoring"
$stopService.Add_Click({
    try {
        Stop-AllProcesses
        
        $icon.BalloonTipTitle = "Security Alert Engine"
        $icon.BalloonTipText = "Monitoring service stopped"
        $icon.ShowBalloonTip(3000)
        Update-MenuItems
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not stop monitoring service. Error: $($_.Exception.Message)", "Service Error")
    }
})

$separator2 = New-Object System.Windows.Forms.ToolStripSeparator

$installService = New-Object System.Windows.Forms.ToolStripMenuItem
$installService.Text = "Install Service"
$installService.Add_Click({
    try {
        $installProcess = Invoke-HiddenPowerShell $ServiceScript "-Install"
        $installProcess.WaitForExit()
        $icon.BalloonTipTitle = "Security Alert Engine"
        $icon.BalloonTipText = "Service installed successfully"
        $icon.ShowBalloonTip(3000)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not install service. Run as administrator. Error: $($_.Exception.Message)", "Installation Error")
    }
})

$serviceStatus = New-Object System.Windows.Forms.ToolStripMenuItem
$serviceStatus.Text = "Service Status"
$serviceStatus.Add_Click({
    $isServiceRunning = Test-ServiceRunning
    $isDashboardRunning = Test-DashboardRunning
    $serviceProcessStatus = if ($script:serviceProcess -and !$script:serviceProcess.HasExited) { "Running" } else { "Not Running" }
    $dashboardProcessStatus = if ($script:dashboardProcess -and !$script:dashboardProcess.HasExited) { "Running" } else { "Not Running" }
    
    $statusMessage = @"
Security Alert Engine Status:

Monitoring Service: $(if($isServiceRunning){"Running"}else{"Not Running"})
Dashboard: $(if($isDashboardRunning){"Available"}else{"Not Available"})
Dashboard URL: $DashboardURL

Process Status:
Service Process: $serviceProcessStatus
Dashboard Process: $dashboardProcessStatus

Scripts:
Monitoring: $ServiceScript
Dashboard: $DashboardScript
"@
    
    [System.Windows.Forms.MessageBox]::Show($statusMessage, "Service Status")
})

$separator3 = New-Object System.Windows.Forms.ToolStripSeparator

# FIXED: Auto-Start Everything - Uses correct scripts
$autoStart = New-Object System.Windows.Forms.ToolStripMenuItem
$autoStart.Text = "Auto-Start Everything"
$autoStart.Add_Click({
    try {
        Write-Host "Auto-starting everything..." -ForegroundColor Green
        
        # Start monitoring service (SecurityAlertService.ps1 -Start)
        $script:serviceProcess = Invoke-HiddenPowerShell $ServiceScript "-Start"
        Start-Sleep 2
        
        # Start dashboard (SecurityDashboard.ps1 with no arguments)
        $script:dashboardProcess = Invoke-HiddenPowerShell $DashboardScript
        Start-Sleep 3
        
        # Open dashboard in browser
        Start-Process $DashboardURL
        
        $icon.BalloonTipTitle = "Security Alert Engine"
        $icon.BalloonTipText = "All services started and dashboard opened"
        $icon.ShowBalloonTip(3000)
        Update-MenuItems
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not auto-start services. Error: $($_.Exception.Message)", "Auto-Start Error")
    }
})

$separator4 = New-Object System.Windows.Forms.ToolStripSeparator

$exitApp = New-Object System.Windows.Forms.ToolStripMenuItem
$exitApp.Text = "Exit"
$exitApp.Add_Click({
    Stop-AllProcesses
    $icon.Visible = $false
    $icon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

# Add items to context menu
$contextMenu.Items.AddRange(@(
    $openDashboard,
    $separator1,
    $startService,
    $stopService,
    $separator2,
    $installService,
    $serviceStatus,
    $separator3,
    $autoStart,
    $separator4,
    $exitApp
))

$icon.ContextMenuStrip = $contextMenu

# Function to update menu item states
function Update-MenuItems {
    $isRunning = Test-ServiceRunning
    $startService.Enabled = -not $isRunning
    $stopService.Enabled = $isRunning
    
    # Change icon color based on status
    if ($isRunning) {
        $icon.Icon = [System.Drawing.SystemIcons]::Shield
    } else {
        $icon.Icon = [System.Drawing.SystemIcons]::Error
    }
}

# Double-click to open dashboard
$icon.Add_DoubleClick({
    $openDashboard.PerformClick()
})

# Timer to update status periodically
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30000  # 30 seconds
$timer.Add_Tick({
    Update-MenuItems
})
$timer.Start()

# Show startup notification
$icon.BalloonTipTitle = "Security Alert Engine"
$icon.BalloonTipText = "System tray manager started. Right-click for options."
$icon.ShowBalloonTip(3000)

# Initial menu update
Update-MenuItems

Write-Host "Security Alert Engine tray manager started!" -ForegroundColor Green
Write-Host "FIXED: Using separate scripts for monitoring and dashboard" -ForegroundColor Yellow

# Keep the application running
[System.Windows.Forms.Application]::Run()