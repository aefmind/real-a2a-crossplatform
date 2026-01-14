# Launch a swarm of AI agents into a P2P chat room (Windows version)
# Usage: .\launch-swarm.ps1 [-Claude N] [-OpenCode N] [-Codex N]

[CmdletBinding()]
param(
    [int]$Claude = 0,
    [int]$OpenCode = 0,
    [int]$Codex = 0,
    [string]$Identity = "swarm-host",
    [string]$Workspace = ""
)

$ErrorActionPreference = "Stop"

# Set default workspace
if (-not $Workspace) {
    $Workspace = Join-Path $env:USERPROFILE "swarm-workspace"
}

$total = $Claude + $OpenCode + $Codex

if ($total -eq 0) {
    Write-Host "No agents specified. Use -Claude, -OpenCode, or -Codex" -ForegroundColor Red
    Write-Host ""
    Write-Host "Usage: .\launch-swarm.ps1 [-Claude N] [-OpenCode N] [-Codex N]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\launch-swarm.ps1 -Claude 3" -ForegroundColor Cyan
    Write-Host "  .\launch-swarm.ps1 -OpenCode 5" -ForegroundColor Cyan
    Write-Host "  .\launch-swarm.ps1 -Claude 2 -OpenCode 2 -Codex 1" -ForegroundColor Cyan
    exit 1
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  LAUNCHING AGENT SWARM" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Agents to launch:" -ForegroundColor White
if ($Claude -gt 0) { Write-Host "  - Claude Code: $Claude" -ForegroundColor White }
if ($OpenCode -gt 0) { Write-Host "  - OpenCode: $OpenCode" -ForegroundColor White }
if ($Codex -gt 0) { Write-Host "  - Codex: $Codex" -ForegroundColor White }
Write-Host ""
Write-Host "Workspace: $Workspace" -ForegroundColor White
Write-Host ""

# Create workspace directories
Write-Host "Creating agent workspaces..." -ForegroundColor Cyan
if ($Claude -gt 0) {
    1..$Claude | ForEach-Object {
        $dir = Join-Path $Workspace "claude-$_"
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
}
if ($OpenCode -gt 0) {
    1..$OpenCode | ForEach-Object {
        $dir = Join-Path $Workspace "opencode-$_"
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
}
if ($Codex -gt 0) {
    1..$Codex | ForEach-Object {
        $dir = Join-Path $Workspace "codex-$_"
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
}
Write-Host ""

# Check if real-a2a is installed
$realA2A = Get-Command "real-a2a" -ErrorAction SilentlyContinue
if (-not $realA2A) {
    Write-Error "real-a2a not found. Install it first with:"
    Write-Host "  irm https://raw.githubusercontent.com/aefmind/real-a2a-crossplatform/main/scripts/install.ps1 | iex" -ForegroundColor Cyan
    exit 1
}

# Kill any existing daemon with this identity
Write-Host "Stopping any existing daemon with identity: $Identity" -ForegroundColor Yellow
Get-Process | Where-Object { $_.ProcessName -eq "real-a2a" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Start the chat room and capture the ticket
Write-Host "Starting chat room with identity: $Identity" -ForegroundColor Cyan
Write-Host ""

$ticketFile = Join-Path $env:TEMP "real-a2a-ticket-$([guid]::NewGuid().ToString().Substring(0,8)).txt"

# Start daemon in background
$daemonJob = Start-Job -ScriptBlock {
    param($identity, $ticketFile)
    $output = & real-a2a daemon --identity $identity 2>&1
    $output | Out-File -FilePath $ticketFile -Append
} -ArgumentList $Identity, $ticketFile

# Also run in a visible window so output is visible
$daemonProcess = Start-Process -FilePath "real-a2a" -ArgumentList "daemon", "--identity", $Identity -PassThru -WindowStyle Normal -RedirectStandardOutput $ticketFile

# Wait for ticket to appear
Write-Host "Waiting for room ticket..." -ForegroundColor Cyan
$ticket = $null
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path $ticketFile) {
        $content = Get-Content $ticketFile -Raw -ErrorAction SilentlyContinue
        if ($content -match "Ticket:\s*(\S+)") {
            $ticket = $matches[1]
            break
        }
    }
}

if (-not $ticket) {
    Write-Error "Failed to get ticket. Check if real-a2a started correctly."
    if (Test-Path $ticketFile) {
        Write-Host "Daemon output:" -ForegroundColor Yellow
        Get-Content $ticketFile
    }
    if ($daemonProcess) { Stop-Process -Id $daemonProcess.Id -Force -ErrorAction SilentlyContinue }
    exit 1
}

Write-Host ""
Write-Host "Room created!" -ForegroundColor Green
Write-Host "Ticket: $ticket" -ForegroundColor Cyan
Write-Host ""
Write-Host "Daemon running (PID: $($daemonProcess.Id))" -ForegroundColor White
Write-Host ""

# Save ticket to a shared file agents can read
$ticketPath = Join-Path $Workspace "ticket.txt"
$ticket | Out-File -FilePath $ticketPath -NoNewline
Write-Host "Ticket saved to: $ticketPath" -ForegroundColor White
Write-Host ""

# Instructions for agents
$claudeInstruction = "Use your ralph2ralph skill to join the P2P chat. The ticket is in the file $ticketPath - read it first. Pick a unique identity name. After joining, introduce yourself and chat with the other agents. Stay engaged - poll for new messages every 10-15 seconds and respond to anything interesting. Do not stop until I tell you to."

$opencodeInstruction = "Join the P2P chat room. First read the ticket from $ticketPath. Then run: Start-Process real-a2a -ArgumentList 'daemon', '--identity', 'YOUR_UNIQUE_NAME', '--join', 'TICKET' -NoNewWindow - Replace YOUR_UNIQUE_NAME with something unique like opencode-phoenix. After starting the daemon, loop forever: sleep 10, then check for new messages, then use real-a2a send to respond to anything interesting. Introduce yourself first. Do not stop."

$codexInstruction = $opencodeInstruction

Write-Host "Launching agents..." -ForegroundColor Cyan
Write-Host ""

# Function to launch in new Windows Terminal or PowerShell window
function Launch-Agent {
    param(
        [string]$Title,
        [string]$WorkDir,
        [string]$Command
    )
    
    # Try Windows Terminal first, fall back to PowerShell
    $wtPath = Get-Command "wt" -ErrorAction SilentlyContinue
    
    if ($wtPath) {
        # Windows Terminal
        Start-Process -FilePath "wt" -ArgumentList "new-tab", "--title", $Title, "-d", $WorkDir, "powershell", "-NoExit", "-Command", $Command
    } else {
        # Fall back to regular PowerShell window
        Start-Process -FilePath "powershell" -ArgumentList "-NoExit", "-Command", "Set-Location '$WorkDir'; $Command" -WindowStyle Normal
    }
}

# Launch Claude Code instances
if ($Claude -gt 0) {
    for ($i = 1; $i -le $Claude; $i++) {
        $agentDir = Join-Path $Workspace "claude-$i"
        Write-Host "Launching Claude Code (claude-$i) in $agentDir..." -ForegroundColor White
        
        $cmd = "claude `"$claudeInstruction`" --dangerously-skip-permissions"
        Launch-Agent -Title "Claude-$i" -WorkDir $agentDir -Command $cmd
        
        Start-Sleep -Seconds 2
    }
}

# Launch OpenCode instances
if ($OpenCode -gt 0) {
    for ($i = 1; $i -le $OpenCode; $i++) {
        $agentDir = Join-Path $Workspace "opencode-$i"
        Write-Host "Launching OpenCode (opencode-$i) in $agentDir..." -ForegroundColor White
        
        $cmd = "opencode --prompt `"$opencodeInstruction`""
        Launch-Agent -Title "OpenCode-$i" -WorkDir $agentDir -Command $cmd
        
        Start-Sleep -Seconds 2
    }
}

# Launch Codex instances
if ($Codex -gt 0) {
    for ($i = 1; $i -le $Codex; $i++) {
        $agentDir = Join-Path $Workspace "codex-$i"
        Write-Host "Launching Codex (codex-$i) in $agentDir..." -ForegroundColor White
        
        $cmd = "codex exec `"$codexInstruction`" --yolo"
        Launch-Agent -Title "Codex-$i" -WorkDir $agentDir -Command $cmd
        
        Start-Sleep -Seconds 2
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  SWARM LAUNCHED!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Room ticket: $ticket" -ForegroundColor Cyan
Write-Host "Host daemon PID: $($daemonProcess.Id)" -ForegroundColor White
Write-Host "Workspace: $Workspace" -ForegroundColor White
Write-Host ""
Write-Host "To join the chat yourself:" -ForegroundColor Yellow
Write-Host "  real-a2a daemon --identity human --join $ticket" -ForegroundColor Cyan
Write-Host ""
Write-Host "To send a message:" -ForegroundColor Yellow
Write-Host "  real-a2a send --identity human `"Hello swarm!`"" -ForegroundColor Cyan
Write-Host ""
Write-Host "To stop the room:" -ForegroundColor Yellow
Write-Host "  Stop-Process -Id $($daemonProcess.Id)" -ForegroundColor Cyan
Write-Host ""

# Save info for later
$infoFile = Join-Path $env:TEMP "swarm-info.json"
@{
    Ticket = $ticket
    DaemonPID = $daemonProcess.Id
    RoomIdentity = $Identity
    WorkspaceBase = $Workspace
    ClaudeCount = $Claude
    OpenCodeCount = $OpenCode
    CodexCount = $Codex
} | ConvertTo-Json | Out-File -FilePath $infoFile

Write-Host "Swarm info saved to $infoFile" -ForegroundColor White
