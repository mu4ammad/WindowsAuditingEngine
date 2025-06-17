# Security Alert Background Service - ENHANCED VERSION
# Added persistent logging and expanded event monitoring

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
$LogFile = "$ServicePath\SecurityEvents.log"

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

# ENHANCED: Write events to persistent log file
function Write-EventToLog {
    param($EventRecord, $LogLevel = "INFO")
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "$timestamp | $LogLevel | $($EventRecord.EventId) | $($EventRecord.Name) | $($EventRecord.User) | $($EventRecord.Computer)"
        
        # Append to log file
        Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8
        
        # Optional: Rotate log file if it gets too large (>10MB)
        if ((Get-Item $LogFile -ErrorAction SilentlyContinue).Length -gt 10MB) {
            $backupLog = "$ServicePath\SecurityEvents_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            Move-Item $LogFile $backupLog
            Write-Host "Rotated log file to: $backupLog" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "Error writing to log file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to load existing events from JSON file
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

# Function to check if event already exists
function Test-EventExists {
    param($ExistingEvents, $NewRecordId)
    
    foreach ($existingEvent in $ExistingEvents) {
        if ($existingEvent.RecordId -eq $NewRecordId) {
            return $true
        }
    }
    return $false
}

# Status update with file locking protection
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
            }
        } catch {
            $needsUpdate = $true
        }
    } else {
        $needsUpdate = $true
    }
    
    if (-not $needsUpdate) {
        return
    }
    
    # Try to write with retry logic
    $attempts = 0
    $maxAttempts = 3
    $success = $false
    
    while ($attempts -lt $maxAttempts -and -not $success) {
        try {
            $attempts++
            $jsonData = $statusData | ConvertTo-Json -Depth 3
            $tempFile = "$StatusFile.tmp"
            $jsonData | Out-File $tempFile -Encoding UTF8 -Force
            Move-Item $tempFile $StatusFile -Force
            $success = $true
            
        } catch {
            if (Test-Path "$StatusFile.tmp") {
                Remove-Item "$StatusFile.tmp" -Force -ErrorAction SilentlyContinue
            }
            
            if ($attempts -lt $maxAttempts) {
                Start-Sleep -Milliseconds 200
            }
        }
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

# ENHANCED: Expanded event monitoring with more event types
function Start-BackgroundMonitoring {
    $config = Get-ServiceConfig
    $EventCount = 0
    $AlertCount = 0
    $LastEventId = 0
    
    # Load existing events from file
    $RecentEvents = Get-ExistingEvents -StatusFile $StatusFile
    $EventCount = $RecentEvents.Count
    
    if ($RecentEvents.Count -gt 0) {
        $LastEventId = ($RecentEvents | ForEach-Object { [int]$_.RecordId } | Measure-Object -Maximum).Maximum
        Write-Host "Resuming monitoring from RecordId: $LastEventId" -ForegroundColor Cyan
        $AlertCount = ($RecentEvents | Where-Object { $_.Color -eq "danger" -or $_.Color -eq "warning" }).Count
    }
    
    # Send startup email
    if ($config.EmailEnabled) {
        Send-AlertEmail -Subject "Security Service Started" -Body "Security Alert Service started on $env:COMPUTERNAME at $(Get-Date). Loaded $($RecentEvents.Count) existing events."
    }
    
    # ENHANCED: Extended event type definitions
    $EventTypes = @{
        # Authentication Events
        4624 = @{ Name = "Successful Logon"; Icon = "✅"; Color = "success" }
        4625 = @{ Name = "Failed Logon"; Icon = "❌"; Color = "danger" }
        4634 = @{ Name = "Account Logoff"; Icon = "🚪"; Color = "info" }
        4648 = @{ Name = "Explicit Credential Logon"; Icon = "🔐"; Color = "info" }
        4778 = @{ Name = "Session Reconnected"; Icon = "🔄"; Color = "info" }
        4779 = @{ Name = "Session Disconnected"; Icon = "↩️"; Color = "info" }
        
        # Account Management Events
        4720 = @{ Name = "User Account Created"; Icon = "👤"; Color = "warning" }
        4726 = @{ Name = "User Account Deleted"; Icon = "🗑️"; Color = "warning" }
        4728 = @{ Name = "User Added to Security Group"; Icon = "➕"; Color = "warning" }
        4729 = @{ Name = "User Removed from Security Group"; Icon = "➖"; Color = "warning" }
        4738 = @{ Name = "User Account Changed"; Icon = "✏️"; Color = "warning" }
        4740 = @{ Name = "User Account Locked"; Icon = "🔒"; Color = "danger" }
        4767 = @{ Name = "User Account Unlocked"; Icon = "🔓"; Color = "warning" }
        4781 = @{ Name = "Account Name Changed"; Icon = "📝"; Color = "warning" }
        
        # System/Policy Events
        4672 = @{ Name = "Special Privileges Assigned"; Icon = "🔑"; Color = "warning" }
        4719 = @{ Name = "Audit Policy Changed"; Icon = "⚙️"; Color = "danger" }
        
        # Network Events
        5140 = @{ Name = "Network Share Accessed"; Icon = "📁"; Color = "info" }
        5156 = @{ Name = "Network Connection Allowed"; Icon = "🌐"; Color = "info" }
        5157 = @{ Name = "Network Connection Blocked"; Icon = "🚧"; Color = "warning" }
        
        # Authentication Protocol Events
        4768 = @{ Name = "Kerberos TGT Requested"; Icon = "🎫"; Color = "info" }
        4769 = @{ Name = "Kerberos Service Ticket"; Icon = "🎟️"; Color = "info" }
        4771 = @{ Name = "Kerberos Pre-auth Failed"; Icon = "🚫"; Color = "danger" }
        4776 = @{ Name = "Domain Controller Auth"; Icon = "🏢"; Color = "info" }
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
    Write-Host "Monitoring $(($EventTypes.Keys | Measure-Object).Count) different event types" -ForegroundColor Cyan
    
    while ($true) {
        try {
            # ENHANCED: Monitor all defined event types
            $MonitoredEventIds = $EventTypes.Keys
            $NewEvents = Get-WinEvent -LogName Security -MaxEvents 50 -ErrorAction SilentlyContinue | 
                         Where-Object { $_.RecordId -gt $LastEventId -and $_.Id -in $MonitoredEventIds }
            
            $newEventsAdded = 0
            $lastAlertMessage = ""
            
            foreach ($Event in $NewEvents) {
                # Skip if event already exists
                if (Test-EventExists -ExistingEvents $RecentEvents -NewRecordId $Event.RecordId) {
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
                
                # ENHANCED: Write to persistent log file
                $logLevel = switch ($EventInfo.Color) {
                    "danger" { "DANGER" }
                    "warning" { "WARNING" }
                    "success" { "SUCCESS" }
                    "info" { "INFO" }
                    default { "INFO" }
                }
                Write-EventToLog -EventRecord $EventRecord -LogLevel $logLevel
                
                # Add new event to the beginning (most recent first)
                $RecentEvents = @($EventRecord) + $RecentEvents
                
                # Trim old events if we have too many (keep last 100)
                if ($RecentEvents.Count -gt 100) {
                    $RecentEvents = $RecentEvents | Select-Object -First 100
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
                    
                    4726 {  # User account deleted
                        $AlertTriggered = $true
                        $AlertMessage = "User account deleted: $Username"
                        Send-AlertEmail -Subject "User Account Deleted" -Body $AlertMessage
                    }
                    
                    4740 {  # Account locked
                        $AlertTriggered = $true
                        $AlertMessage = "🔒 Account locked: $Username"
                        Send-AlertEmail -Subject "Account Lockout" -Body $AlertMessage
                    }
                    
                    4719 {  # Audit policy changed
                        $AlertTriggered = $true
                        $AlertMessage = "🚨 CRITICAL: Audit policy changed by: $Username"
                        Send-AlertEmail -Subject "Critical: Policy Changed" -Body $AlertMessage
                    }
                    
                    4728 {  # User added to security group
                        $AlertTriggered = $true
                        $AlertMessage = "User added to security group: $Username"
                    }
                    
                    4738 {  # User account changed
                        $AlertTriggered = $true
                        $AlertMessage = "User account modified: $Username"
                    }
                    
                    4624 {  # Successful logon
                        $AlertMessage = "User logged in: $Username"
                    }
                    
                    4634 {  # Logoff
                        $AlertMessage = "User logged off: $Username"
                    }
                    
                    4672 {  # Special privileges assigned
                        $AlertTriggered = $true
                        $AlertMessage = "Administrative privileges granted: $Username"
                    }
                    
                    5157 {  # Network connection blocked
                        $AlertTriggered = $true
                        $AlertMessage = "Network connection blocked"
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
            
            # Only update file if we added new events
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

# Install as Windows service
function Install-SecurityService {
    Write-Host "Installing Security Alert Service..." -ForegroundColor Green
    
    # Copy current script to service location
    if ($MyInvocation.MyCommand.Path) {
        Copy-Item $MyInvocation.MyCommand.Path $ServiceScript -Force
        Write-Host "Service script copied to: $ServiceScript" -ForegroundColor Green
    }
    
    # Create scheduled tasks
    $ServiceAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ServiceScript`" -Start"
    $ServiceTrigger = New-ScheduledTaskTrigger -AtStartup
    $ServiceSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden
    
    try {
        Register-ScheduledTask -TaskName "SecurityAlertService" -Action $ServiceAction -Trigger $ServiceTrigger -Settings $ServiceSettings -User "SYSTEM" -Force
        Write-Host "✅ Background monitoring service scheduled task created!" -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to create service task: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Initialize config file if it doesn't exist
    if (!(Test-Path $ConfigPath)) {
        Save-ServiceConfig $DefaultConfig
        Write-Host "✅ Created default configuration file" -ForegroundColor Green
    }
    
    # Create initial log file
    if (!(Test-Path $LogFile)) {
        "# Security Events Log - Started $(Get-Date)" | Out-File $LogFile -Encoding UTF8
        Write-Host "✅ Created event log file: $LogFile" -ForegroundColor Green
    }
    
    Write-Host "`n🎯 Installation Summary:" -ForegroundColor Cyan
    Write-Host "Service Script: $ServiceScript" -ForegroundColor White
    Write-Host "Dashboard Script: $DashboardScript" -ForegroundColor White
    Write-Host "Event Log File: $LogFile" -ForegroundColor White
    Write-Host "Config File: $ConfigPath" -ForegroundColor White
    Write-Host "`nMonitoring $(($EventTypes.Keys | Measure-Object).Count) different security event types" -ForegroundColor Green
}

# Command handling
switch ($true) {
    $Install {
        Install-SecurityService
    }
    
    $Start {
        Write-Host "Starting Enhanced Security Alert Monitoring Service..." -ForegroundColor Green
        Write-Host "Now monitoring 20+ security event types with persistent logging" -ForegroundColor Cyan
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
        
        if (Test-Path $LogFile) {
            $logSize = (Get-Item $LogFile).Length
            Write-Host "Log File: $LogFile ($('{0:N2}' -f ($logSize/1KB)) KB)" -ForegroundColor White
        }
    }
    
    $Uninstall {
        Write-Host "Uninstalling Security Alert Service..." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName "SecurityAlertService" -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Service uninstalled" -ForegroundColor Green
    }
    
    default {
        Write-Host @"
🚨 Enhanced Security Alert Service v3.1

New Features:
✅ 20+ Security Event Types Monitored
✅ Persistent Event Logging to SecurityEvents.log  
✅ Enhanced User Account Management Monitoring
✅ Network Security Event Detection
✅ Kerberos Authentication Monitoring

Commands:
  .\SecurityAlertService.ps1 -Install     Install background monitoring service
  .\SecurityAlertService.ps1 -Start       Start monitoring (enhanced event detection)
  .\SecurityAlertService.ps1 -Status      Check service status and log file size
  .\SecurityAlertService.ps1 -Uninstall   Remove service

For Dashboard:
  .\SecurityDashboard.ps1                 Open web dashboard

Log Files:
  SecurityEvents.log                      Persistent event log
  AlertEngineConfig.json                  Configuration settings

"@ -ForegroundColor Green
    }
}