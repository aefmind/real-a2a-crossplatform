# real-a2a Windows Installer
# Usage: irm https://raw.githubusercontent.com/aefmind/real-a2a-crossplatform/main/scripts/install.ps1 | iex

$ErrorActionPreference = "Stop"

$REPO = "aefmind/real-a2a-crossplatform"
$BINARY_NAME = "real-a2a"
$SKILL_NAME = "ralph2ralph"

# Determine architecture
$arch = if ([Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
} else {
    Write-Error "32-bit Windows is not supported"
    exit 1
}

$platform = "windows-$arch"
$archiveName = "$BINARY_NAME-$platform.zip"

Write-Host "Fetching latest version..." -ForegroundColor Cyan

try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO/releases/latest"
    $latestTag = $release.tag_name
} catch {
    Write-Error "Failed to fetch latest version: $_"
    exit 1
}

Write-Host "Installing $BINARY_NAME $latestTag for $platform..." -ForegroundColor Green

# Install directory - use local AppData
$installDir = Join-Path $env:LOCALAPPDATA "real-a2a\bin"
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

$archiveUrl = "https://github.com/$REPO/releases/download/$latestTag/$archiveName"
$checksumUrl = "$archiveUrl.sha256"

# Download to temp
$tempDir = Join-Path $env:TEMP "real-a2a-install"
if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$tempFile = Join-Path $tempDir $archiveName

Write-Host "Downloading..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $archiveUrl -OutFile $tempFile -UseBasicParsing
} catch {
    Write-Error "Failed to download: $_"
    exit 1
}

# Verify checksum
Write-Host "Verifying checksum..." -ForegroundColor Cyan
try {
    $expectedChecksum = (Invoke-WebRequest -Uri $checksumUrl -UseBasicParsing).Content.Trim().Split()[0]
    $actualChecksum = (Get-FileHash -Path $tempFile -Algorithm SHA256).Hash.ToLower()
    
    if ($actualChecksum -ne $expectedChecksum.ToLower()) {
        Write-Error "Checksum verification failed!"
        Write-Error "Expected: $expectedChecksum"
        Write-Error "Actual:   $actualChecksum"
        Remove-Item -Recurse -Force $tempDir
        exit 1
    }
} catch {
    Write-Warning "Could not verify checksum: $_"
    Write-Warning "Continuing anyway..."
}

# Extract
Write-Host "Extracting..." -ForegroundColor Cyan
Expand-Archive -Path $tempFile -DestinationPath $tempDir -Force

# Move binary
$binaryPath = Join-Path $installDir "$BINARY_NAME.exe"
$extractedBinary = Join-Path $tempDir "$BINARY_NAME.exe"
if (Test-Path $extractedBinary) {
    Move-Item -Path $extractedBinary -Destination $binaryPath -Force
} else {
    # Maybe it's in a subdirectory
    $found = Get-ChildItem -Path $tempDir -Filter "$BINARY_NAME.exe" -Recurse | Select-Object -First 1
    if ($found) {
        Move-Item -Path $found.FullName -Destination $binaryPath -Force
    } else {
        Write-Error "Could not find $BINARY_NAME.exe in archive"
        exit 1
    }
}

Remove-Item -Recurse -Force $tempDir

Write-Host "$BINARY_NAME $latestTag installed to $binaryPath" -ForegroundColor Green

# Install skill for Claude Code
$claudeSkillDir = Join-Path $env:USERPROFILE ".claude\skills\$SKILL_NAME"
if (-not (Test-Path $claudeSkillDir)) {
    New-Item -ItemType Directory -Path $claudeSkillDir -Force | Out-Null
}
$skillUrl = "https://raw.githubusercontent.com/$REPO/main/plugin/skills/$SKILL_NAME/SKILL.md"
try {
    Invoke-WebRequest -Uri $skillUrl -OutFile (Join-Path $claudeSkillDir "SKILL.md") -UseBasicParsing
    Write-Host "Skill installed to $claudeSkillDir\SKILL.md" -ForegroundColor Green
} catch {
    Write-Warning "Could not install Claude Code skill: $_"
}

# Install skill for OpenCode
$opencodeSkillDir = Join-Path $env:APPDATA "opencode\skill\$SKILL_NAME"
if (-not (Test-Path $opencodeSkillDir)) {
    New-Item -ItemType Directory -Path $opencodeSkillDir -Force | Out-Null
}
$skillUrl = "https://raw.githubusercontent.com/$REPO/main/.opencode/skill/$SKILL_NAME/SKILL.md"
try {
    Invoke-WebRequest -Uri $skillUrl -OutFile (Join-Path $opencodeSkillDir "SKILL.md") -UseBasicParsing
    Write-Host "Skill installed to $opencodeSkillDir\SKILL.md" -ForegroundColor Green
} catch {
    Write-Warning "Could not install OpenCode skill: $_"
}

# Install skill for Codex
$codexSkillDir = Join-Path $env:USERPROFILE ".codex\skills\$SKILL_NAME"
if (-not (Test-Path $codexSkillDir)) {
    New-Item -ItemType Directory -Path $codexSkillDir -Force | Out-Null
}
$skillUrl = "https://raw.githubusercontent.com/$REPO/main/.codex/skills/$SKILL_NAME/SKILL.md"
try {
    Invoke-WebRequest -Uri $skillUrl -OutFile (Join-Path $codexSkillDir "SKILL.md") -UseBasicParsing
    Write-Host "Skill installed to $codexSkillDir\SKILL.md" -ForegroundColor Green
} catch {
    Write-Warning "Could not install Codex skill: $_"
}

# Add to PATH if not already there
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$installDir*") {
    Write-Host ""
    Write-Host "Adding $installDir to your PATH..." -ForegroundColor Yellow
    
    $newPath = "$installDir;$currentPath"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    
    # Also update current session
    $env:Path = "$installDir;$env:Path"
    
    Write-Host "PATH updated. You may need to restart your terminal for changes to take effect." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  YOU'RE ALL SET!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "The ralph2ralph skill is now available for:" -ForegroundColor White
Write-Host "  - Claude Code" -ForegroundColor White
Write-Host "  - OpenCode" -ForegroundColor White
Write-Host "  - Codex" -ForegroundColor White
Write-Host ""
Write-Host "Just ask your agent to use it!" -ForegroundColor White
Write-Host ""
Write-Host "------------------------------------------" -ForegroundColor DarkGray
Write-Host "  CLAUDE CODE (OPTIONAL)" -ForegroundColor Yellow
Write-Host "------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host "For the stop hook that keeps Claude engaged:" -ForegroundColor White
Write-Host ""
Write-Host "  /plugin marketplace add aefmind/real-a2a-crossplatform" -ForegroundColor Cyan
Write-Host "  /plugin install ralph2ralph@reala2a" -ForegroundColor Cyan
Write-Host ""

# Verify installation
try {
    $version = & $binaryPath --version 2>&1
    Write-Host "Verification: $version" -ForegroundColor Green
} catch {
    Write-Host "Note: Run 'real-a2a --help' to verify installation" -ForegroundColor Yellow
}
