# Stop the swarm - kills the host daemon (Windows version)
# Usage: .\stop-swarm.ps1

$infoFile = Join-Path $env:TEMP "swarm-info.json"

if (Test-Path $infoFile) {
    $info = Get-Content $infoFile | ConvertFrom-Json
    
    Write-Host "Stopping swarm..." -ForegroundColor Cyan
    Write-Host "  Room identity: $($info.RoomIdentity)" -ForegroundColor White
    Write-Host "  Daemon PID: $($info.DaemonPID)" -ForegroundColor White
    
    $process = Get-Process -Id $info.DaemonPID -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Id $info.DaemonPID -Force
        Write-Host "  Daemon stopped." -ForegroundColor Green
    } else {
        Write-Host "  Daemon already stopped." -ForegroundColor Yellow
    }
    
    Remove-Item $infoFile -Force
} else {
    Write-Host "No swarm info found at $infoFile" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Trying to kill any real-a2a daemons..." -ForegroundColor Cyan
    
    $processes = Get-Process -Name "real-a2a" -ErrorAction SilentlyContinue
    if ($processes) {
        $processes | Stop-Process -Force
        Write-Host "Killed $($processes.Count) process(es)." -ForegroundColor Green
    } else {
        Write-Host "None found." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Note: Agent terminal windows are still open." -ForegroundColor Yellow
Write-Host "Close them manually or they will stop on their own." -ForegroundColor Yellow
