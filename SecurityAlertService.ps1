# Security Alert Background Service - MONITORING ONLY

param(
    [switch]$Install,
    [switch]$Start,
    [switch]$Stop,
    [switch]$Status,
    [switch]$Uninstall
)

# Configuration
$ServicePath = "C:\SecurityLogs"
$ServiceScript = "$ServicePath\SecurityAlertService.ps1"
$DashboardScript = "$ServicePath\SecurityDashboard.ps1"
$StatusFile = "$ServicePath\ServiceStatus.json"
$ConfigPath = "$ServicePath\AlertEngineConfig.json"

# Ensure admin privileges
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Restarting as administrator..." -ForegroundColor Yellow
    Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" $($args -join ' ')"
    exit
}

# Create directories
if (!(Test-Path $ServicePath)) {
    New-Item -ItemType Directory -Path $ServicePath -Force
}

# Default configuration
$DefaultConfig = @{
    EmailEnabled = $false
    EmailSMTP = "smtp.gmail.com"
    EmailPort = 587
    EmailFrom = ""
    EmailTo = ""
    EmailPassword = ""
    FailedLoginThreshold = 3
    FailedLoginCritical = 5
    LogRetentionDays = 30
}

# Load configuration
function Get-ServiceConfig {
    if (Test-Path $ConfigPath) {
        try {
            return Get-Content $ConfigPath | ConvertFrom-Json
        } catch {}
    }
    return $DefaultConfig
}

# Save configuration
function Save-ServiceConfig {
    param($Config)
    $Config | ConvertTo-Json | Out-File $ConfigPath -Encoding UTF8
}

#function to load existing events from JSON file
function Get-ExistingEvents {
    param($StatusFile)
    
    try {
        if (Test-Path $StatusFile) {
            $status = Get-Content $StatusFile -Raw | ConvertFrom-Json
            if ($status.RecentEvents -and $status.RecentEvents.Count -gt 0) {
                Write-Host "Loaded $($status.RecentEvents.Count) existing events from file" -ForegroundColor Green
                return $status.RecentEvents
            }
        }
    } catch {
        Write-Host "Error loading existing events: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    Write-Host "No existing events found, starting fresh" -ForegroundColor Yellow
    return @()
}

#function to check if event already exists
function Test-EventExists {
    param($ExistingEvents, $NewRecordId)
    
    foreach ($existingEvent in $ExistingEvents) {
        if ($existingEvent.RecordId -eq $NewRecordId) {
            return $true
        }
    }
    return $false
}

#status update with file locking protection
function Update-ServiceStatus {
    param(
        $Status = "Running",
        $LastEvent = "",
        $EventCount = 0,
        $AlertCount = 0,
        $RecentEvents = @(),
        [switch]$ForceUpdate = $false
    )
    
    $statusData = @{
        Status = $Status
        LastUpdate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ComputerName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        IPAddress = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Wi-Fi*", "Ethernet*" | Where-Object IPAddress -notlike "169.*" | Select-Object -First 1).IPAddress
        LastEvent = $LastEvent
        EventCount = $EventCount
        AlertCount = $AlertCount
        UpTime = (Get-Date) - (Get-Process -Id $PID).StartTime
        RecentEvents = $RecentEvents
    }
    
    # CHECK: Do we need to update the file?
    $needsUpdate = $ForceUpdate
    
    if (-not $needsUpdate -and (Test-Path $StatusFile)) {
        try {
            $existingStatus = Get-Content $StatusFile -Raw | ConvertFrom-Json
            
            # Update if key values changed
            if ($existingStatus.EventCount -ne $EventCount -or 
                $existingStatus.AlertCount -ne $AlertCount -or 
                $existingStatus.Status -ne $Status -or
                $existingStatus.RecentEvents.Count -ne $RecentEvents.Count) {
                $needsUpdate = $true
                Write-Host "Status file needs update: EventCount($($existingStatus.EventCount)->$EventCount) AlertCount($($existingStatus.AlertCount)->$AlertCount)" -ForegroundColor Yellow
            }
        } catch {
            $needsUpdate = $true
            Write-Host "Error reading existing status, forcing update" -ForegroundColor Yellow
        }
    } else {
        $needsUpdate = $true
    }
    
    if (-not $needsUpdate) {
        Write-Host "No changes detected, skipping file update" -ForegroundColor Gray
        return
    }
    
    # Try to write with retry logic
    $attempts = 0
    $maxAttempts = 3
    $success = $false
    
    while ($attempts -lt $maxAttempts -and -not $success) {
        try {
            $attempts++
            
            # Convert to JSON first
            $jsonData = $statusData | ConvertTo-Json -Depth 3
            
            # Write to temporary file first, then rename (atomic operation)
            $tempFile = "$StatusFile.tmp"
            $jsonData | Out-File $tempFile -Encoding UTF8 -Force
            
            # Rename temp file to actual file (atomic on Windows)
            Move-Item $tempFile $StatusFile -Force
            
            $success = $true
            Write-Host "Status updated successfully with $($RecentEvents.Count) events (attempt $attempts)" -ForegroundColor Green
            
        } catch {
            Write-Host "Status update attempt $attempts failed: $($_.Exception.Message)" -ForegroundColor Red
            
            # Clean up temp file if it exists
            if (Test-Path "$StatusFile.tmp") {
                Remove-Item "$StatusFile.tmp" -Force -ErrorAction SilentlyContinue
            }
            
            if ($attempts -lt $maxAttempts) {
                Start-Sleep -Milliseconds 200
            }
        }
    }
    
    if (-not $success) {
        Write-Host "Failed to update status after $maxAttempts attempts" -ForegroundColor Red
    }
}

# Email function
function Send-AlertEmail {
    param($Subject, $Body)
    
    $config = Get-ServiceConfig
    if (-not $config.EmailEnabled) { return }
    
    try {
        $SecurePassword = ConvertTo-SecureString $config.EmailPassword -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential($config.EmailFrom, $SecurePassword)
        
        Send-MailMessage -SmtpServer $config.EmailSMTP -Port $config.EmailPort -UseSsl -Credential $Credential -From $config.EmailFrom -To $config.EmailTo -Subject "🚨 $Subject" -Body $Body
        return $true
    } catch {
        return $false
    }
}

# MAIN MONITORING FUNCTION - FIXED
function Start-BackgroundMonitoring {
    $config = Get-ServiceConfig
    $EventCount = 0
    $AlertCount = 0
    $LastEventId = 0
    
    # LOAD EXISTING EVENTS FROM FILE (don't start fresh!)
    $RecentEvents = Get-ExistingEvents -StatusFile $StatusFile
    $EventCount = $RecentEvents.Count
    
    # Find the highest RecordId to continue from where we left off
    if ($RecentEvents.Count -gt 0) {
        $LastEventId = ($RecentEvents | ForEach-Object { [int]$_.RecordId } | Measure-Object -Maximum).Maximum
        Write-Host "Resuming monitoring from RecordId: $LastEventId" -ForegroundColor Cyan
        
        # Count existing alerts
        $AlertCount = ($RecentEvents | Where-Object { $_.Color -eq "danger" -or $_.Color -eq "warning" }).Count
    }
    
    # Send startup email
    if ($config.EmailEnabled) {
        Send-AlertEmail -Subject "Security Service Started" -Body "Security Alert Service started on $env:COMPUTERNAME at $(Get-Date). Loaded $($RecentEvents.Count) existing events."
    }
    
    # Event type descriptions
    $EventTypes = @{
        4624 = @{ Name = "Successful Logon"; Icon = "✅"; Color = "success" }
        4625 = @{ Name = "Failed Logon"; Icon = "❌"; Color = "danger" }
        4720 = @{ Name = "User Account Created"; Icon = "👤"; Color = "warning" }
        4719 = @{ Name = "Audit Policy Changed"; Icon = "⚙️"; Color = "danger" }
        4672 = @{ Name = "Special Privileges Assigned"; Icon = "🔑"; Color = "warning" }
        4648 = @{ Name = "Explicit Credential Logon"; Icon = "🔐"; Color = "info" }
        4634 = @{ Name = "Account Logged Off"; Icon = "🚪"; Color = "info" }
    }
    
    # Function to get username from SID
    function Get-UserFromSID {
        param($SID)
        try {
            if ($SID -like "S-1-5-18") { return "SYSTEM" }
            if ($SID -like "S-1-5-19") { return "LOCAL SERVICE" }
            if ($SID -like "S-1-5-20") { return "NETWORK SERVICE" }
            
            $objSID = New-Object System.Security.Principal.SecurityIdentifier($SID)
            $objUser = $objSID.Translate([System.Security.Principal.NTAccount])
            return $objUser.Value.Split('\')[-1]
        } catch {
            return $SID.Substring(0, [Math]::Min(20, $SID.Length)) + "..."
        }
    }
    
    Update-ServiceStatus -Status "Monitoring" -EventCount $EventCount -AlertCount $AlertCount -RecentEvents $RecentEvents
    
    Write-Host "🛡️ Security monitoring started..." -ForegroundColor Green
    Write-Host "Loaded $($RecentEvents.Count) existing events, starting from RecordId $LastEventId" -ForegroundColor Cyan
    Write-Host "Monitoring Event IDs: 4624, 4625, 4720, 4719, 4672, 4648, 4634" -ForegroundColor Cyan
    
    while ($true) {
        try {
            # Get new security events (only newer than our last recorded event)
            $NewEvents = Get-WinEvent -LogName Security -MaxEvents 50 -ErrorAction SilentlyContinue | 
                         Where-Object { $_.RecordId -gt $LastEventId -and $_.Id -in @(4625, 4624, 4720, 4719, 4672, 4648, 4634) }
            
            $newEventsAdded = 0
            $lastAlertMessage = ""
            
            foreach ($Event in $NewEvents) {
                # DOUBLE-CHECK: Make sure this event doesn't already exist
                if (Test-EventExists -ExistingEvents $RecentEvents -NewRecordId $Event.RecordId) {
                    Write-Host "Skipping duplicate event RecordId: $($Event.RecordId)" -ForegroundColor Yellow
                    continue
                }
                
                $EventCount++
                $newEventsAdded++
                $LastEventId = $Event.RecordId
                
                # Get event details
                $EventInfo = $EventTypes[$Event.Id]
                $UserSID = "Unknown"
                try {
                    if ($Event.Properties.Count -gt 0) {
                        $UserSID = $Event.Properties[0].Value
                    }
                } catch {}
                $Username = Get-UserFromSID $UserSID
                
                # Create detailed event record
                $EventRecord = @{
                    Time = $Event.TimeCreated.ToString('MM/dd/yy HH:mm:ss')
                    EventId = $Event.Id
                    Name = $EventInfo.Name
                    Icon = $EventInfo.Icon
                    Color = $EventInfo.Color
                    User = $Username
                    Computer = $env:COMPUTERNAME
                    RecordId = $Event.RecordId
                }
                
                # ADD NEW EVENT TO THE BEGINNING (most recent first)
                $RecentEvents = @($EventRecord) + $RecentEvents
                
                # OPTIONAL: Trim old events if we have too many (keep last 100)
                if ($RecentEvents.Count -gt 100) {
                    $RecentEvents = $RecentEvents | Select-Object -First 100
                    Write-Host "Trimmed old events, keeping most recent 100" -ForegroundColor Yellow
                }
                
                # Analyze event for alerts
                $AlertTriggered = $false
                $AlertMessage = ""
                
                switch ($Event.Id) {
                    4625 {  # Failed logon
                        $AlertTriggered = $true
                        $AlertMessage = "Failed login attempt: $Username"
                        
                        # Check for multiple failures
                        $RecentFailures = Get-WinEvent -FilterHashtable @{
                            LogName = 'Security'
                            ID = 4625
                            StartTime = (Get-Date).AddMinutes(-10)
                        } -ErrorAction SilentlyContinue
                        
                        if ($RecentFailures.Count -ge $config.FailedLoginCritical) {
                            $AlertMessage = "🚨 CRITICAL: $($RecentFailures.Count) failed login attempts!"
                            Send-AlertEmail -Subject "Critical Security Alert" -Body $AlertMessage
                        }
                    }
                    
                    4720 {  # User account created
                        $AlertTriggered = $true
                        $AlertMessage = "New user account created: $Username"
                        Send-AlertEmail -Subject "New User Account" -Body $AlertMessage
                    }
                    
                    4719 {  # Audit policy changed
                        $AlertTriggered = $true
                        $AlertMessage = "🚨 CRITICAL: Audit policy changed by: $Username"
                        Send-AlertEmail -Subject "Critical: Policy Changed" -Body $AlertMessage
                    }
                    
                    4624 {  # Successful logon
                        $AlertMessage = "User logged in: $Username"
                    }
                    
                    4634 {  # Logoff
                        $AlertMessage = "User logged off: $Username"
                    }
                }
                
                if ($AlertTriggered) {
                    $AlertCount++
                }
                
                $lastAlertMessage = $AlertMessage
                
                # Console output for debugging
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - NEW EVENT: $($EventInfo.Icon) $($EventInfo.Name): $Username (RecordId: $($Event.RecordId))" -ForegroundColor $(
                    switch ($EventInfo.Color) {
                        "success" { "Green" }
                        "danger" { "Red" }
                        "warning" { "Yellow" }
                        "info" { "Cyan" }
                        default { "White" }
                    }
                )
            }
            
            # ONLY UPDATE FILE IF WE ADDED NEW EVENTS
            if ($newEventsAdded -gt 0) {
                Write-Host "Added $newEventsAdded new events. Total events: $($RecentEvents.Count)" -ForegroundColor Green
                Update-ServiceStatus -Status "Monitoring" -LastEvent $lastAlertMessage -EventCount $EventCount -AlertCount $AlertCount -RecentEvents $RecentEvents
            } else {
                # Just update the timestamp without rewriting events
                Update-ServiceStatus -Status "Monitoring" -LastEvent "Monitoring..." -EventCount $EventCount -AlertCount $AlertCount -RecentEvents $RecentEvents
            }
            
            Start-Sleep -Seconds 15
            
        } catch {
            Write-Host "Error in monitoring loop: $($_.Exception.Message)" -ForegroundColor Red
            Update-ServiceStatus -Status "Error: $($_.Exception.Message)" -EventCount $EventCount -AlertCount $AlertCount -RecentEvents $RecentEvents
            Start-Sleep -Seconds 60
        }
    }
}

# Create dashboard script (separate file)
function New-DashboardScript {
    # This function is handled by SecurityDashboard.ps1 - no longer needed here
    Write-Host "Dashboard functionality moved to SecurityDashboard.ps1" -ForegroundColor Green
}

# Install as Windows service
function Install-SecurityService {
    Write-Host "Installing Security Alert Service..." -ForegroundColor Green
    
    # Copy current script to service location
    if ($MyInvocation.MyCommand.Path) {
        Copy-Item $MyInvocation.MyCommand.Path $ServiceScript -Force
        Write-Host "Service script copied to: $ServiceScript" -ForegroundColor Green
    }
    
    # Create scheduled tasks
    
    # Background monitoring service (hidden)
    $ServiceAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ServiceScript`" -Start"
    $ServiceTrigger = New-ScheduledTaskTrigger -AtStartup
    $ServiceSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden
    
    try {
        Register-ScheduledTask -TaskName "SecurityAlertService" -Action $ServiceAction -Trigger $ServiceTrigger -Settings $ServiceSettings -User "SYSTEM" -Force
        Write-Host "✅ Background monitoring service scheduled task created!" -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to create service task: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host "`n🎯 Installation Summary:" -ForegroundColor Cyan
    Write-Host "Service Script: $ServiceScript" -ForegroundColor White
    Write-Host "Dashboard Script: $DashboardScript" -ForegroundColor White
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "1. .\SecurityAlertService.ps1 -Start    (start monitoring)" -ForegroundColor White
    Write-Host "2. .\SecurityDashboard.ps1             (open dashboard)" -ForegroundColor White
}

# Command handling
switch ($true) {
    $Install {
        Install-SecurityService
    }
    
    $Start {
        Write-Host "Starting Security Alert Monitoring Service..." -ForegroundColor Green
        Start-BackgroundMonitoring
    }
    
    $Status {
        if (Test-Path $StatusFile) {
            $status = Get-Content $StatusFile | ConvertFrom-Json
            Write-Host "Status: $($status.Status)" -ForegroundColor Green
            Write-Host "Last Update: $($status.LastUpdate)" -ForegroundColor White
            Write-Host "Events: $($status.EventCount)" -ForegroundColor White
            Write-Host "Alerts: $($status.AlertCount)" -ForegroundColor White
            Write-Host "Recent Events: $($status.RecentEvents.Count)" -ForegroundColor White
        } else {
            Write-Host "Service not running" -ForegroundColor Red
        }
    }
    
    $Uninstall {
        Write-Host "Uninstalling Security Alert Service..." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName "SecurityAlertService" -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Service uninstalled" -ForegroundColor Green
    }
    
    default {
        Write-Host @"
🚨 Security Alert Service v3.0 - MONITORING ONLY

Commands:
  .\SecurityAlertService.ps1 -Install     Install background monitoring service
  .\SecurityAlertService.ps1 -Start       Start monitoring (run once to test)
  .\SecurityAlertService.ps1 -Status      Check service status
  .\SecurityAlertService.ps1 -Uninstall   Remove service

For Dashboard:
  .\SecurityDashboard.ps1                 Open web dashboard

"@ -ForegroundColor Green
    }
}