# Security Dashboard with Sleek Matte Design
Add-Type -AssemblyName System.Web

$StatusFile = "C:\SecurityLogs\ServiceStatus.json"
$StartPort = 8080
$MaxPort = 8090

Write-Host "Starting Security Dashboard..." -ForegroundColor Green

# Function to test if port is available
function Test-Port {
    param($Port)
    try {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://localhost:$Port/")
        $listener.Start()
        $listener.Stop()
        return $true
    } catch {
        return $false
    }
}

# Find available port
$Port = $StartPort
while ($Port -le $MaxPort) {
    if (Test-Port $Port) {
        Write-Host "✅ Found available port: $Port" -ForegroundColor Green
        break
    } else {
        Write-Host "Port $Port is busy, trying next..." -ForegroundColor Yellow
        $Port++
    }
}

if ($Port -gt $MaxPort) {
    Write-Host "❌ No available ports found between $StartPort and $MaxPort" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

# Start the HTTP listener
try {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$Port/")
    $listener.Start()
    Write-Host "🌐 Dashboard running at: http://localhost:$Port" -ForegroundColor Green
    Write-Host "Press Ctrl+C to stop the dashboard" -ForegroundColor Yellow
    
    # Auto-open browser
    Start-Sleep 2
    Start-Process "http://localhost:$Port"
    
} catch {
    Write-Host "❌ Failed to start dashboard: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

# Function to get system status
function Get-SystemStatus {
    $defaultStatus = @{
        Status = "Service Not Running"
        LastUpdate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ComputerName = $env:COMPUTERNAME
        IPAddress = "Detecting..."
        EventCount = 0
        AlertCount = 0
        LastEvent = "No recent events"
    }
    
    if (Test-Path $StatusFile) {
        try {
            $status = Get-Content $StatusFile -Raw | ConvertFrom-Json
            if (-not $status.IPAddress -or $status.IPAddress -eq "Unknown") {
                try {
                    $ip = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
                        $_.InterfaceAlias -notlike "*Loopback*" -and 
                        $_.IPAddress -notlike "169.*" -and 
                        $_.IPAddress -notlike "127.*"
                    } | Select-Object -First 1
                    $status.IPAddress = if ($ip) { $ip.IPAddress } else { "192.168.1.100" }
                } catch {
                    $status.IPAddress = "IP Detection Failed"
                }
            }
            return $status
        } catch {
            Write-Host "Status file corrupted, using defaults" -ForegroundColor Yellow
            return $defaultStatus
        }
    }
    return $defaultStatus
}

# ENHANCED: Sleek Matte Dashboard Design
function Get-DashboardHTML {
    $status = Get-SystemStatus
    
    # Get recent events with better error handling and limits
    $recentEvents = @()
    $totalEventsInSystem = 0
    
    if ($status.RecentEvents -and $status.RecentEvents.Count -gt 0) {
        $totalEventsInSystem = $status.RecentEvents.Count
        # Display most recent 30 events for better performance
        $recentEvents = $status.RecentEvents | Select-Object -First 30
        Write-Host "Total events in system: $totalEventsInSystem" -ForegroundColor Yellow
        Write-Host "Displaying most recent: $($recentEvents.Count) events" -ForegroundColor Green
    } else {
        Write-Host "No RecentEvents found in status object" -ForegroundColor Yellow
    }
    
    $displayedEventCount = $recentEvents.Count
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Alert Dashboard - Port $Port</title>
    <meta http-equiv="refresh" content="30">
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { 
            margin: 0; 
            padding: 0; 
            box-sizing: border-box; 
        }
        
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica Neue', Arial, sans-serif;
            background: #0f0f0f;
            color: #e4e4e7;
            min-height: 100vh;
            line-height: 1.6;
        }
        
        .container { 
            max-width: 1400px; 
            margin: 0 auto; 
            padding: 24px; 
        }
        
        .header { 
            text-align: center; 
            margin-bottom: 32px; 
            background: #18181b;
            border-radius: 12px;
            padding: 32px 24px;
            border: 1px solid #27272a;
        }
        
        .header h1 {
            font-size: 2.25rem;
            font-weight: 700;
            margin-bottom: 8px;
            color: #fafafa;
            letter-spacing: -0.025em;
        }
        
        .header .subtitle {
            font-size: 1rem;
            color: #a1a1aa;
            margin-bottom: 16px;
        }
        
        .port-info {
            background: #0ea5e9;
            color: white;
            padding: 8px 16px;
            border-radius: 6px;
            display: inline-block;
            font-size: 0.875rem;
            font-weight: 500;
        }
        
        .status-grid { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); 
            gap: 20px; 
            margin-bottom: 32px; 
        }
        
        .status-card { 
            background: #18181b;
            border: 1px solid #27272a;
            border-radius: 12px; 
            padding: 24px; 
            transition: all 0.2s ease;
        }
        
        .status-card:hover {
            border-color: #3f3f46;
            transform: translateY(-2px);
        }
        
        .status-card-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 16px;
        }
        
        .status-label { 
            font-size: 0.875rem; 
            color: #a1a1aa;
            font-weight: 500;
            text-transform: uppercase; 
            letter-spacing: 0.05em; 
        }
        
        .status-value { 
            font-size: 2rem; 
            font-weight: 700; 
            color: #fafafa;
            margin-top: 8px;
        }
        
        .status-running { color: #22c55e; }
        .status-error { color: #ef4444; }
        .status-warning { color: #f59e0b; }
        .status-info { color: #3b82f6; }
        
        .events-panel { 
            background: #18181b;
            border: 1px solid #27272a;
            border-radius: 12px; 
            padding: 24px;
            margin-bottom: 24px;
        }
        
        .events-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 24px;
            flex-wrap: wrap;
            gap: 16px;
        }
        
        .events-header h3 {
            font-size: 1.25rem;
            font-weight: 600;
            color: #fafafa;
        }
        
        .event-count-badge {
            background: #3f3f46;
            color: #e4e4e7;
            padding: 4px 12px;
            border-radius: 6px;
            font-size: 0.875rem;
            font-weight: 500;
        }
        
        .events-table {
            width: 100%;
            border-collapse: collapse;
            background: #0f0f0f;
            border-radius: 8px;
            overflow: hidden;
        }
        
        .events-table th {
            background: #27272a;
            padding: 16px 12px;
            text-align: left;
            font-weight: 600;
            font-size: 0.875rem;
            color: #fafafa;
            border-bottom: 1px solid #3f3f46;
        }
        
        .events-table td {
            padding: 14px 12px;
            border-bottom: 1px solid #27272a;
            vertical-align: middle;
        }
        
        .events-table tr:hover {
            background: #18181b;
        }
        
        .events-table tr:last-child td {
            border-bottom: none;
        }
        
        .event-icon {
            font-size: 1.1rem;
            margin-right: 8px;
        }
        
        .event-name {
            font-weight: 500;
            color: #fafafa;
        }
        
        .event-time {
            font-family: 'SF Mono', 'Monaco', 'Cascadia Code', 'Roboto Mono', monospace;
            font-size: 0.875rem;
            color: #a1a1aa;
        }
        
        .event-user {
            font-weight: 500;
            color: #e4e4e7;
        }
        
        .event-id {
            font-family: 'SF Mono', 'Monaco', 'Cascadia Code', 'Roboto Mono', monospace;
            font-size: 0.875rem;
            color: #a1a1aa;
            background: #27272a;
            padding: 2px 6px;
            border-radius: 4px;
        }
        
        .event-success { color: #22c55e; }
        .event-danger { color: #ef4444; }
        .event-warning { color: #f59e0b; }
        .event-info { color: #3b82f6; }
        
        .no-events {
            text-align: center;
            padding: 48px 24px;
            color: #71717a;
            font-style: italic;
        }
        
        .btn {
            background: #3f3f46;
            border: 1px solid #52525b;
            color: #fafafa;
            padding: 10px 16px;
            border-radius: 8px;
            text-decoration: none;
            font-size: 0.875rem;
            font-weight: 500;
            transition: all 0.2s ease;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 8px;
        }
        
        .btn:hover {
            background: #52525b;
            border-color: #71717a;
            transform: translateY(-1px);
        }
        
        .btn-primary {
            background: #0ea5e9;
            border-color: #0284c7;
        }
        
        .btn-primary:hover {
            background: #0284c7;
            border-color: #0369a1;
        }
        
        .footer { 
            text-align: center; 
            margin-top: 32px; 
            color: #71717a; 
            font-size: 0.875rem;
        }
        
        .footer a {
            color: #a1a1aa;
            text-decoration: none;
        }
        
        .footer a:hover {
            color: #e4e4e7;
        }
        
        .alert {
            padding: 16px;
            border-radius: 8px;
            margin-bottom: 20px;
            border: 1px solid;
        }
        
        .alert-info {
            background: #1e3a8a1a;
            border-color: #3b82f6;
            color: #93c5fd;
        }
        
        .alert-warning {
            background: #92400e1a;
            border-color: #f59e0b;
            color: #fbbf24;
        }
        
        @media (max-width: 768px) {
            .container { padding: 16px; }
            .status-grid { grid-template-columns: 1fr; }
            .events-header { flex-direction: column; align-items: flex-start; }
            .events-table { font-size: 0.875rem; }
            .events-table th, .events-table td { padding: 12px 8px; }
        }
    </style>
    <script>
        let eventData = [];
        let loadErrors = [];
        
        try {
"@

    # Better JavaScript event generation with limits and error handling
    if ($displayedEventCount -gt 0) {
        $html += "console.log('Loading $displayedEventCount events...');"
        $html += "eventData = [`n"
        
        $validEvents = 0
        for ($i = 0; $i -lt $displayedEventCount; $i++) {
            try {
                $eventItem = $recentEvents[$i]
                
                # Validate event has required properties
                if (-not $eventItem.Time -or -not $eventItem.Name -or -not $eventItem.User) {
                    continue
                }
                
                # Sanitize all strings to prevent JavaScript breaks
                $time = ($eventItem.Time -replace "'", "\'") -replace '"', '\"' -replace "`n", ' ' -replace "`r", ''
                $name = ($eventItem.Name -replace "'", "\'") -replace '"', '\"' -replace "`n", ' ' -replace "`r", ''
                $user = ($eventItem.User -replace "'", "\'") -replace '"', '\"' -replace "`n", ' ' -replace "`r", ''
                $icon = ($eventItem.Icon -replace "'", "\'") -replace '"', '\"' -replace "`n", ' ' -replace "`r", ''
                
                # Ensure we have valid values
                if ([string]::IsNullOrWhiteSpace($time)) { $time = "Unknown Time" }
                if ([string]::IsNullOrWhiteSpace($name)) { $name = "Unknown Event" }
                if ([string]::IsNullOrWhiteSpace($user)) { $user = "Unknown User" }
                if ([string]::IsNullOrWhiteSpace($icon)) { $icon = "❓" }
                
                $html += @"
                {
                    time: '$time',
                    icon: '$icon',
                    name: '$name',
                    user: '$user',
                    eventId: '$($eventItem.EventId)',
                    color: '$($eventItem.Color)',
                    recordId: '$($eventItem.RecordId)'
                }
"@
                if ($validEvents -lt ($displayedEventCount - 1) -and $i -lt ($displayedEventCount - 1)) {
                    $html += ",`n"
                }
                $validEvents++
                
            } catch {
                continue
            }
        }
        $html += "`n            ];"
        $html += "`nconsole.log('Successfully loaded ' + eventData.length + ' events');"
    } else {
        $html += "eventData = [];"
        $html += "`nconsole.log('No events to display');"
    }

    $html += @"
        } catch (e) {
            console.error('Error loading event data:', e);
            eventData = [];
            loadErrors.push('JavaScript loading error: ' + e.message);
        }
        
        function displayEvents() {
            const tbody = document.getElementById('events-tbody');
            
            if (eventData.length === 0) {
                tbody.innerHTML = '<tr><td colspan="4" class="no-events">No security events to display.<br>Try locking your screen or logging in/out to generate test events.</td></tr>';
                return;
            }
            
            try {
                tbody.innerHTML = eventData.map(eventItem => 
                    '<tr class="event-' + (eventItem.color || 'info') + '">' +
                    '<td class="event-time">' + (eventItem.time || 'Unknown') + '</td>' +
                    '<td><span class="event-icon">' + (eventItem.icon || '❓') + '</span><span class="event-name">' + (eventItem.name || 'Unknown Event') + '</span></td>' +
                    '<td class="event-user">' + (eventItem.user || 'Unknown') + '</td>' +
                    '<td><span class="event-id">' + (eventItem.eventId || 'N/A') + '</span></td>' +
                    '</tr>'
                ).join('');
                
                console.log('Successfully displayed ' + eventData.length + ' events in table');
            } catch (e) {
                console.error('Error displaying events:', e);
                tbody.innerHTML = '<tr><td colspan="4" class="no-events">Error displaying events: ' + e.message + '</td></tr>';
            }
        }
        
        window.onload = function() {
            displayEvents();
            console.log('Dashboard loaded. Events array length: ' + eventData.length);
        };
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛡️ Security Alert Dashboard</h1>
            <div class="subtitle">Real-time security monitoring for <strong>$($status.ComputerName)</strong></div>
            <div class="port-info">Running on Port $Port</div>
        </div>
        
"@

    # Add info alert if we're limiting events
    if ($totalEventsInSystem -gt 30) {
        $html += @"
        <div class="alert alert-info">
            <strong>Performance Optimization:</strong> Displaying most recent 30 of $totalEventsInSystem total events for optimal performance.
        </div>
"@
    }

    $html += @"
        
        <div class="status-grid">
            <div class="status-card">
                <div class="status-card-header">
                    <div class="status-label">Service Status</div>
                </div>
                <div class="status-value status-$(if($status.Status -like '*Monitoring*'){'running'}elseif($status.Status -like '*Not Running*'){'error'}else{'warning'})">
                    $($status.Status)
                </div>
            </div>
            <div class="status-card">
                <div class="status-card-header">
                    <div class="status-label">Computer Name</div>
                </div>
                <div class="status-value">$($status.ComputerName)</div>
            </div>
            <div class="status-card">
                <div class="status-card-header">
                    <div class="status-label">Total Events</div>
                </div>
                <div class="status-value status-info">$totalEventsInSystem</div>
            </div>
            <div class="status-card">
                <div class="status-card-header">
                    <div class="status-label">Security Alerts</div>
                </div>
                <div class="status-value status-$(if($status.AlertCount -gt 0){'error'}else{'running'})">
                    $($status.AlertCount)
                </div>
            </div>
        </div>
        
        <div class="events-panel">
            <div class="events-header">
                <h3>Security Events</h3>
                <div class="event-count-badge">Showing $displayedEventCount of $totalEventsInSystem events</div>
            </div>
            
            <table class="events-table">
                <thead>
                    <tr>
                        <th width="15%">Time</th>
                        <th width="40%">Event</th>
                        <th width="25%">User</th>
                        <th width="20%">Event ID</th>
                    </tr>
                </thead>
                <tbody id="events-tbody">
                    <tr><td colspan="4" class="no-events">Loading events...</td></tr>
                </tbody>
            </table>
            
            <div style="margin-top: 20px; display: flex; gap: 12px; flex-wrap: wrap;">
                <button class="btn btn-primary" onclick="location.reload()">
                    🔄 Refresh Dashboard
                </button>
                <button class="btn" onclick="window.open('http://localhost:$Port', '_blank')">
                    🆕 New Window
                </button>
            </div>
        </div>
        
        <div class="footer">
            <p><strong>Security Alert Engine v3.1</strong> | Enhanced monitoring with persistent logging</p>
            <p>Last updated: $($status.LastUpdate) | Dashboard: localhost:$Port</p>
        </div>
    </div>
</body>
</html>
"@
    return $html
}

# Main server loop
while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $response = $context.Response
        
        $response.ContentType = "text/html; charset=utf-8"
        $response.StatusCode = 200
        
        $html = Get-DashboardHTML
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
        
        try {
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        } catch {
            # Client disconnected, continue
        } finally {
            try { $response.OutputStream.Close() } catch { }
        }
        
    } catch {
        # Request error, continue
    }
}

try {
    $listener.Stop()
    $listener.Dispose()
} catch { }

Write-Host "Dashboard stopped" -ForegroundColor Yellow