# Windows Security Alert Engine

A real-time PowerShell-based security monitoring system with web dashboard and system tray management for Windows environments.

## Overview

The Windows Security Alert Engine provides comprehensive real-time monitoring of Windows security events through an intuitive web dashboard and system tray interface. Features automated event detection, alerting, and persistent event logging for security analysis.

## Features

- **Real-time Security Monitoring**: Monitors critical Windows security events as they occur
- **Web Dashboard**: Clean, responsive web interface showing live security events and system status
- **System Tray Integration**: Easy access and control through Windows system tray
- **Persistent Event Logging**: Stores all security events to log files for historical analysis
- **Background Service**: Runs silently in background with minimal system impact
- **Auto-startup**: Automatically starts with Windows
- **Event Categorization**: Color-coded events by severity (success, warning, danger, info)
- **Email Alerts**: Optional email notifications for critical security events

## Requirements

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.0 or higher
- Administrator privileges for installation
- Web browser for dashboard access

## Quick Start

1. **Download and Extract**
   ```
   Extract all files to C:\SecurityLogs
   ```

2. **One-Click Installation**
   ```powershell
   # Run as Administrator
   .\InstallSecurityEngine.ps1
   ```

3. **Start Monitoring**
   - Look for shield icon in system tray
   - Right-click and select "Auto-Start Everything"
   - Dashboard will open automatically at http://localhost:8080

## File Structure

```
SecurityLogs/
├── SecurityAlertService.ps1      # Main monitoring service
├── SecurityDashboard.ps1         # Web dashboard server
├── SecurityTrayManager.ps1       # System tray interface
├── InstallSecurityEngine.ps1     # One-click installer
├── CreateShortcuts.ps1           # Desktop shortcuts creator
├── SetupAutoStartup.ps1          # Windows startup configuration
├── ServiceStatus.json            # Real-time status data
├── AlertEngineConfig.json        # Configuration settings
├── SecurityEvents.log            # Persistent event log file
└── Desktop Shortcuts/            # Auto-generated shortcuts
    ├── Security Alert Manager.lnk
    ├── Security Dashboard.lnk
    ├── Start Security Monitoring.lnk
    └── Auto-Start Security Engine.bat
```

## Monitored Security Events

The engine monitors these Windows security events in real-time:

| Event ID | Event Type | Severity | Description |
|----------|------------|----------|-------------|
| 4624 | Successful Logon | Success | User successfully logged in |
| 4625 | Failed Logon | Danger | Failed login attempt |
| 4634 | Account Logoff | Info | User logged off |
| 4648 | Explicit Credential Logon | Info | Logon using explicit credentials |
| 4672 | Special Privileges Assigned | Warning | Administrative privileges granted |
| 4720 | User Account Created | Warning | New user account created |
| 4726 | User Account Deleted | Warning | User account deleted |
| 4728 | User Added to Security Group | Warning | User added to security group |
| 4729 | User Removed from Security Group | Warning | User removed from security group |
| 4738 | User Account Changed | Warning | User account properties modified |
| 4740 | User Account Locked | Danger | Account locked due to failed attempts |
| 4767 | User Account Unlocked | Warning | Locked account was unlocked |
| 4719 | System Audit Policy Changed | Danger | Critical: Audit settings modified |

## Usage

### System Tray Interface

The system tray manager provides easy access to all functions:

- **Right-click the shield icon** for options menu
- **Auto-Start Everything**: Starts monitoring + opens dashboard
- **Open Dashboard**: Direct access to web interface
- **Start/Stop Monitoring**: Control the background service
- **Service Status**: View current monitoring status

### Web Dashboard

Access at `http://localhost:8080` (auto-detects available port 8080-8090):

- **Real-time Events**: Live feed of security events as they occur
- **System Status**: Current monitoring status and statistics
- **Event Filtering**: Color-coded events by type and severity
- **Auto-refresh**: Updates every 30 seconds automatically

### Manual Commands

```powershell
# Start monitoring service
.\SecurityAlertService.ps1 -Start

# Open web dashboard
.\SecurityDashboard.ps1

# Install as Windows service
.\SecurityAlertService.ps1 -Install

# Check service status
.\SecurityAlertService.ps1 -Status

# Create desktop shortcuts
.\CreateShortcuts.ps1

# Setup auto-startup
.\SetupAutoStartup.ps1
```

## Configuration

### Email Alerts (Optional)

Edit `AlertEngineConfig.json`:

```json
{
    "EmailEnabled": true,
    "EmailSMTP": "smtp.gmail.com",
    "EmailPort": 587,
    "EmailFrom": "alerts@company.com",
    "EmailTo": "admin@company.com",
    "EmailPassword": "app_password",
    "FailedLoginThreshold": 3,
    "FailedLoginCritical": 5,
    "LogRetentionDays": 30
}
```

### Event Thresholds

Customize alert thresholds in the configuration:

- `FailedLoginThreshold`: Failed logins before warning (default: 3)
- `FailedLoginCritical`: Failed logins before critical alert (default: 5)
- `LogRetentionDays`: Days to keep event logs (default: 30)

## Event Logging

All security events are automatically logged to `SecurityEvents.log`:

```
2024-01-15 14:30:22 | SUCCESS | 4624 | Successful Logon | john.smith | DESKTOP-ABC123
2024-01-15 14:35:18 | DANGER  | 4625 | Failed Logon | unknown | DESKTOP-ABC123
2024-01-15 14:40:55 | WARNING | 4720 | User Account Created | admin | DESKTOP-ABC123
```

## Troubleshooting

### Dashboard Won't Open
```
- Check if port 8080-8090 are available
- Try running .\SecurityDashboard.ps1 manually
- Check Windows Firewall settings
```

### No Events Showing
```
- Verify SecurityAlertService.ps1 is running
- Check Windows Event Log service is running
- Run as Administrator
- Test by locking/unlocking your screen
```

### System Tray Icon Missing
```
- Run .\SecurityTrayManager.ps1 manually
- Check if hidden in system tray overflow
- Restart Windows Explorer process
```

### PowerShell Execution Policy
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Auto-Start with Windows

The installer automatically configures the system to start with Windows:

1. **System Tray Manager** starts automatically on boot
2. **Background Monitoring** can be enabled through tray menu
3. **Dashboard** launches on-demand through tray interface

To disable auto-start:
- Remove shortcut from: `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`

## Performance

- **Memory Usage**: ~10-20MB for monitoring service
- **CPU Usage**: <1% during normal operation
- **Disk Usage**: ~50-100KB per day for event logs
- **Network**: Dashboard only (local HTTP server)

## Security Features

- **Real-time Detection**: Events captured within seconds of occurrence
- **Persistent Logging**: All events saved to disk for forensic analysis
- **Failed Login Tracking**: Automatic detection of brute force attempts
- **Privilege Escalation Monitoring**: Alerts on administrative access grants
- **Account Management Tracking**: Monitors user account creation/modification
- **Audit Policy Protection**: Alerts if security auditing is disabled

## License

This project is licensed under the MIT License.

## Support

For issues and support:
1. Check the troubleshooting section above
2. Verify all files are in C:\SecurityLogs
3. Run components manually to test functionality
4. Check PowerShell execution policy

## Version History

### Version 3.0 (Current)
- Enhanced event monitoring with 13 security event types
- Persistent event logging to SecurityEvents.log
- Improved web dashboard with auto port detection
- System tray integration with comprehensive menu
- Automatic Windows startup configuration
- Email alerting for critical events

### Version 2.0
- Added web dashboard with real-time updates
- System tray manager interface
- Desktop shortcuts and auto-installation

### Version 1.0
- Basic security event monitoring
- Background service functionality
