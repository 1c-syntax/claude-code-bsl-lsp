# BSL Language Server — install & auto-update hook (PowerShell)
# For native Windows without Git Bash

$ErrorActionPreference = "SilentlyContinue"

$BSL_LS_REPO = "1c-syntax/bsl-language-server"
$UPDATE_INTERVAL = 480 # seconds

$ARCHIVE_DIR = "bsl-language-server"
$BINARY_SUBPATH = "bsl-language-server.exe"
$ARCHIVE_NAME = "bsl-language-server_win.zip"
$DATA_DIR = Join-Path $env:LOCALAPPDATA "Programs\bsl-language-server"
$SERVER_INFO = Join-Path $DATA_DIR "SERVER-INFO"

# ── SERVER-INFO helpers ─────────────────────────────────────────────

function Read-ServerInfo {
    if (Test-Path $SERVER_INFO) {
        try {
            return Get-Content $SERVER_INFO -Raw | ConvertFrom-Json
        } catch {
            return $null
        }
    }
    return $null
}

function Write-ServerInfo {
    param([string]$Version, [long]$Timestamp)
    New-Item -ItemType Directory -Path $DATA_DIR -Force | Out-Null
    @{ version = $Version; lastUpdate = $Timestamp } | ConvertTo-Json | Set-Content $SERVER_INFO
}

# ── Version comparison ──────────────────────────────────────────────

function Compare-SemVer {
    param([string]$Latest, [string]$Installed)
    $l = [version]($Latest -replace '^v', '')
    $i = [version]($Installed -replace '^v', '')
    return $l -gt $i
}

# ── GitHub API ──────────────────────────────────────────────────────

function Get-LatestVersion {
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$BSL_LS_REPO/releases/latest" `
            -Headers @{ "User-Agent" = "claude-code-bsl-lsp" }
        return $release.tag_name
    } catch {
        return $null
    }
}

# ── Binary resolution ──────────────────────────────────────────────

function Find-InstalledBinary {
    param([string]$Version)
    $binary = Join-Path $DATA_DIR "$Version\$ARCHIVE_DIR\$BINARY_SUBPATH"
    if (Test-Path $binary) { return $binary }
    return $null
}

# ── Download & install ──────────────────────────────────────────────

function Install-BslLanguageServer {
    param([string]$Version)

    $url = "https://github.com/$BSL_LS_REPO/releases/download/$Version/$ARCHIVE_NAME"
    $versionDir = Join-Path $DATA_DIR $Version
    $tmpZip = Join-Path $env:TEMP "bsl-ls-$Version.zip"

    Write-Host "[bsl-language-server] Downloading $Version (win)..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing
    } catch {
        Write-Host "[bsl-language-server] Download failed."
        return $false
    }

    Write-Host "[bsl-language-server] Extracting..."
    try {
        New-Item -ItemType Directory -Path $versionDir -Force | Out-Null
        Expand-Archive -Path $tmpZip -DestinationPath $versionDir -Force
    } catch {
        Write-Host "[bsl-language-server] Extraction failed."
        return $false
    } finally {
        Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
    }

    $binary = Join-Path $versionDir "$ARCHIVE_DIR\$BINARY_SUBPATH"
    if (-not (Test-Path $binary)) {
        Write-Host "[bsl-language-server] Binary not found at: $binary"
        return $false
    }

    Write-Host "[bsl-language-server] Installed $Version"
    return $true
}

# ── Cleanup old versions ───────────────────────────────────────────

function Remove-OldVersions {
    param([string]$CurrentVersion)
    Get-ChildItem -Path $DATA_DIR -Directory | Where-Object {
        $_.Name -like "v*" -and $_.Name -ne $CurrentVersion
    } | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force
        Write-Host "[bsl-language-server] Removed old version $($_.Name)"
    }
}

# ── Main ────────────────────────────────────────────────────────────

$info = Read-ServerInfo
$installedVersion = if ($info) { $info.version } else { $null }
$lastUpdate = if ($info) { $info.lastUpdate } else { 0 }
$nowMs = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())

# Throttle: skip GitHub check if updated recently
if ($installedVersion -and $lastUpdate -gt 0) {
    $elapsedS = ($nowMs - $lastUpdate) / 1000
    if ($elapsedS -lt $UPDATE_INTERVAL) {
        $binary = Find-InstalledBinary $installedVersion
        if ($binary) {
            Write-Host "[bsl-language-server] Up to date ($installedVersion)"
            exit 0
        }
    }
}

# Query GitHub
$latestVersion = Get-LatestVersion
if (-not $latestVersion) {
    if ($installedVersion) {
        Write-ServerInfo -Version $installedVersion -Timestamp $nowMs
        Write-Host "[bsl-language-server] Offline, using $installedVersion"
        exit 0
    }
    Write-Host "[bsl-language-server] Cannot reach GitHub API and no version installed."
    Write-Host "          Install manually: https://github.com/$BSL_LS_REPO/releases/latest"
    exit 0
}

# Compare versions
$needsInstall = $false
if (-not $installedVersion) {
    $needsInstall = $true
} elseif (Compare-SemVer -Latest $latestVersion -Installed $installedVersion) {
    Write-Host "[bsl-language-server] Update available: $installedVersion -> $latestVersion"
    $needsInstall = $true
} else {
    $binary = Find-InstalledBinary $installedVersion
    if (-not $binary) { $needsInstall = $true }
}

if ($needsInstall) {
    if (Install-BslLanguageServer -Version $latestVersion) {
        Write-ServerInfo -Version $latestVersion -Timestamp $nowMs
        Remove-OldVersions -CurrentVersion $latestVersion

        # Check PATH
        $binaryDir = Join-Path $DATA_DIR "$latestVersion\$ARCHIVE_DIR"
        $pathDirs = $env:PATH -split ";"
        if ($binaryDir -notin $pathDirs) {
            Write-Host "[bsl-language-server] Warning: binary dir is not in PATH."
            Write-Host "          Run: [Environment]::SetEnvironmentVariable('PATH', `$env:PATH + ';$binaryDir', 'User')"
        }
    } else {
        Write-Host "          Install manually: https://github.com/$BSL_LS_REPO/releases/latest"
    }
} else {
    Write-ServerInfo -Version $installedVersion -Timestamp $nowMs
    Write-Host "[bsl-language-server] Up to date ($installedVersion)"
}

exit 0
