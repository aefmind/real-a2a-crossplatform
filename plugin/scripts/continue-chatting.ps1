# Ralph2Ralph Stop Hook (Windows version)
# Keeps Claude chatting over P2P by blocking stop attempts

param()

$input = $input | Out-String

# Parse JSON input
try {
    $inputObj = $input | ConvertFrom-Json
    $stopHookActive = $inputObj.stop_hook_active
} catch {
    $stopHookActive = $false
}

# Check if already continuing from a stop hook (prevent infinite loop)
if ($stopHookActive -eq $true) {
    # Allow stop on second attempt
    Write-Output '{}'
    exit 0
}

# Check if there's a running daemon by looking for marker files
# Windows: %LOCALAPPDATA%\com.a2a.real-a2a\data\daemon-*.running
$dataDir = Join-Path $env:LOCALAPPDATA "com.a2a.real-a2a\data"

$daemonRunning = $false
if (Test-Path $dataDir) {
    $runningFiles = Get-ChildItem -Path $dataDir -Filter "daemon-*.running" -ErrorAction SilentlyContinue
    if ($runningFiles) {
        $daemonRunning = $true
    }
}

if ($daemonRunning) {
    # Daemon is running - keep chatting
    $response = @{
        decision = "block"
        reason = "You have an active P2P chat session. Check for new messages by reading your daemon output, then respond to any messages. Use real-a2a send to reply. If the conversation is truly over, run the daemon list command and confirm no peers are waiting."
    } | ConvertTo-Json -Compress
    Write-Output $response
} else {
    # No daemon running - allow stop
    Write-Output '{}'
}
