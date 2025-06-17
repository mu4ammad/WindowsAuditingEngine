# Security Dashboard with Auto Port Detection
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

# Enhanced HTML with better styling
# Enhanced Dashboard with better event handling
function Get-DashboardHTML {
    $status = Get-SystemStatus
    
    # DEBUGGING: Check what we're getting
    Write-Host "Dashboard status object:" -ForegroundColor Cyan
    Write-Host "Status: $($status.Status)" -ForegroundColor White
    Write-Host "EventCount: $($status.EventCount)" -ForegroundColor White
    
    # Get recent events with better error handling and LIMITS
    $recentEvents = @()
    $totalEventsInSystem = 0
    
    if ($status.RecentEvents -and $status.RecentEvents.Count -gt 0) {
        $totalEventsInSystem = $status.RecentEvents.Count
        
        # LIMIT: Only take the most recent 25 events for display to prevent browser overload
        $recentEvents = $status.RecentEvents | Select-Object -First 25
        
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
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            color: white;
            min-height: 100vh;
            overflow-x: hidden;
        }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .header { 
            text-align: center; 
            margin-bottom: 30px; 
            background: rgba(255,255,255,0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 30px;
            border: 1px solid rgba(255,255,255,0.2);
        }
        .debug-info {
            background: rgba(255,255,0,0.1);
            padding: 10px;
            border-radius: 10px;
            margin-bottom: 20px;
            font-family: monospace;
            font-size: 0.9em;
        }
        .limit-warning {
            background: rgba(255,165,0,0.2);
            padding: 10px;
            border-radius: 10px;
            margin-bottom: 20px;
            text-align: center;
            border: 1px solid rgba(255,165,0,0.3);
        }
        .header h1 {
            font-size: 2.5rem;
            margin: 0 0 10px 0;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.5);
        }
        .port-info {
            background: rgba(0,255,136,0.2);
            padding: 10px 20px;
            border-radius: 25px;
            display: inline-block;
            margin-top: 10px;
            border: 1px solid rgba(0,255,136,0.3);
        }
        .status-grid { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
            gap: 20px; 
            margin-bottom: 30px; 
        }
        .status-card { 
            background: rgba(255,255,255,0.15); 
            backdrop-filter: blur(10px); 
            border-radius: 15px; 
            padding: 20px; 
            text-align: center;
            border: 1px solid rgba(255,255,255,0.2);
            transition: all 0.3s ease;
        }
        .status-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 20px rgba(0,0,0,0.2);
        }
        .status-value { 
            font-size: 2em; 
            font-weight: bold; 
            margin: 15px 0; 
            text-shadow: 1px 1px 2px rgba(0,0,0,0.5);
        }
        .status-label { 
            font-size: 0.9em; 
            opacity: 0.9; 
            text-transform: uppercase; 
            letter-spacing: 1px; 
        }
        .status-running { color: #00ff88; text-shadow: 0 0 10px #00ff88; }
        .status-error { color: #ff4757; text-shadow: 0 0 10px #ff4757; }
        .status-unknown { color: #ffa502; text-shadow: 0 0 10px #ffa502; }
        
        .events-panel { 
            background: rgba(255,255,255,0.15); 
            backdrop-filter: blur(10px); 
            border-radius: 15px; 
            padding: 25px;
            border: 1px solid rgba(255,255,255,0.2);
            margin-bottom: 20px;
        }
        
        .events-table {
            width: 100%;
            border-collapse: collapse;
            margin: 15px 0;
        }
        .events-table th {
            background: rgba(255,255,255,0.2);
            padding: 12px 8px;
            text-align: left;
            border-bottom: 2px solid rgba(255,255,255,0.3);
            font-weight: bold;
        }
        .events-table td {
            padding: 10px 8px;
            border-bottom: 1px solid rgba(255,255,255,0.1);
            vertical-align: middle;
        }
        .events-table tr:hover {
            background: rgba(255,255,255,0.1);
        }
        .event-icon {
            font-size: 1.2em;
            margin-right: 8px;
        }
        .event-time {
            font-family: 'Consolas', monospace;
            font-size: 0.9em;
            opacity: 0.8;
        }
        .event-user {
            font-weight: bold;
        }
        .event-success { color: #00ff88; }
        .event-danger { color: #ff4757; }
        .event-warning { color: #ffa502; }
        .event-info { color: #74b9ff; }
        
        .no-events {
            text-align: center;
            padding: 40px;
            opacity: 0.7;
            font-style: italic;
        }
        
        .btn {
            background: rgba(255,255,255,0.2);
            border: 1px solid rgba(255,255,255,0.3);
            color: white;
            padding: 10px 20px;
            border-radius: 25px;
            text-decoration: none;
            margin: 0 5px;
            transition: all 0.3s ease;
            display: inline-block;
            cursor: pointer;
            font-size: 0.9em;
        }
        .btn:hover {
            background: rgba(255,255,255,0.3);
            transform: translateY(-2px);
        }
        
        .footer { 
            text-align: center; 
            margin-top: 30px; 
            opacity: 0.7; 
            font-size: 0.9em;
        }
        
        .error-message {
            background: rgba(255,0,0,0.2);
            padding: 10px;
            border-radius: 10px;
            margin: 10px 0;
            border: 1px solid rgba(255,0,0,0.3);
        }
    </style>
    <script>
        // Event data from PowerShell - ROBUST ERROR HANDLING
        let eventData = [];
        let loadErrors = [];
        
        try {
"@

    # ROBUST: Better JavaScript event generation with limits and error handling
    if ($displayedEventCount -gt 0) {
        $html += "console.log('Loading $displayedEventCount events...');"
        $html += "eventData = [`n"
        
        $validEvents = 0
        for ($i = 0; $i -lt $displayedEventCount; $i++) {
            try {
                $eventItem = $recentEvents[$i]
                
                # ROBUST: Validate event has required properties
                if (-not $eventItem.Time -or -not $eventItem.Name -or -not $eventItem.User) {
                    Write-Host "Skipping invalid event at index $i" -ForegroundColor Red
                    continue
                }
                
                # ROBUST: Sanitize all strings to prevent JavaScript breaks
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
                Write-Host "Error processing event $i : $($_.Exception.Message)" -ForegroundColor Red
                continue
            }
        }
        $html += "`n            ];"
        $html += "`nconsole.log('Successfully loaded ' + eventData.length + ' events');"
    } else {
        $html += "eventData = []; // No events available"
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
            const errorDiv = document.getElementById('error-messages');
            
            // Clear previous errors
            errorDiv.innerHTML = '';
            
            // Show any load errors
            if (loadErrors.length > 0) {
                errorDiv.innerHTML = '<div class="error-message">Errors loading events: ' + loadErrors.join(', ') + '</div>';
            }
            
            if (eventData.length === 0) {
                tbody.innerHTML = '<tr><td colspan="4" class="no-events">No security events to display. Try locking your screen or logging in/out to generate test events.</td></tr>';
                return;
            }
            
            try {
                tbody.innerHTML = eventData.map(eventItem => 
                    '<tr class="event-' + (eventItem.color || 'info') + '">' +
                    '<td class="event-time">' + (eventItem.time || 'Unknown') + '</td>' +
                    '<td><span class="event-icon">' + (eventItem.icon || '❓') + '</span>' + (eventItem.name || 'Unknown Event') + '</td>' +
                    '<td class="event-user">' + (eventItem.user || 'Unknown') + '</td>' +
                    '<td>' + (eventItem.eventId || 'N/A') + '</td>' +
                    '</tr>'
                ).join('');
                
                console.log('Successfully displayed ' + eventData.length + ' events in table');
            } catch (e) {
                console.error('Error displaying events:', e);
                tbody.innerHTML = '<tr><td colspan="4" class="error-message">Error displaying events: ' + e.message + '</td></tr>';
            }
        }
        
        // Initialize when page loads
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
            <div class="port-info">Running on Port $Port</div>
            <p>Real-time security monitoring for <strong>$($status.ComputerName)</strong></p>
            <p>Last updated: $($status.LastUpdate)</p>
        </div>
        
        <!-- DEBUG INFO -->
        <div class="debug-info">
            <strong>Debug Info:</strong><br>
            Total Events in System: $totalEventsInSystem<br>
            Events Being Displayed: $displayedEventCount<br>
            JavaScript Events: <span id="js-event-count">Loading...</span><br>
            Status: $($status.Status)
        </div>
        
        <!-- LIMIT WARNING -->
"@

    # Add warning if we're limiting events
    if ($totalEventsInSystem -gt 25) {
        $html += @"
        <div class="limit-warning">
            <strong>Displaying Events</strong>
        </div>
"@
    }

    $html += @"
        
        <!-- ERROR MESSAGES -->
        <div id="error-messages"></div>
        
        <div class="status-grid">
            <div class="status-card">
                <div class="status-value status-$(if($status.Status -like '*Monitoring*'){'running'}elseif($status.Status -like '*Not Running*'){'error'}else{'unknown'})">
                    $($status.Status)
                </div>
                <div class="status-label">Service Status</div>
            </div>
            <div class="status-card">
                <div class="status-value">DesktopComputer</div>
                <div class="status-label">Device</div>
            </div>
            <div class="status-card">
                <div class="status-value">$totalEventsInSystem</div>
                <div class="status-label">Total Events</div>
            </div>
            <div class="status-card">
                <div class="status-value status-$(if($status.AlertCount -gt 0){'error'}else{'running'})">
                    $($status.AlertCount)
                </div>
                <div class="status-label">Security Alerts</div>
            </div>
        </div>
        
        <div class="events-panel">
            <h3>📊 Security Events (showing $displayedEventCount of $totalEventsInSystem)</h3>
            
            <table class="events-table">
                <thead>
                    <tr>
                        <th>Time</th>
                        <th>Event</th>
                        <th>User</th>
                        <th>ID</th>
                    </tr>
                </thead>
                <tbody id="events-tbody">
                    <tr><td colspan="4" class="no-events">Loading events...</td></tr>
                </tbody>
            </table>
            
            <button class="btn" onclick="location.reload()">🔄 Refresh Now</button>
        </div>
        
        <div class="footer">
            <p>🚨 Security Alert Engine v3.0 | Dashboard on localhost:$Port</p>
            <p>Displaying most recent events to ensure optimal performance</p>
        </div>
    </div>
    
    <script>
        // Update debug info after page loads
        document.getElementById('js-event-count').textContent = eventData.length;
    </script>
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
