# Tests for hooks/check-bsl-ls.ps1.
# Uses the throttled code path (installed version + recent SERVER-INFO), so
# no network access is needed.
#
# Usage: pwsh -NoProfile -File tests/check-bsl-ls.test.ps1 [-Hook <path>]

param(
    [string]$Hook = (Join-Path $PSScriptRoot ".." "hooks" "check-bsl-ls.ps1")
)

$ErrorActionPreference = "Stop"

$script:Passed = 0
$script:Failed = 0

function Pass([string]$Name) { $script:Passed++; Write-Host "  ok   - $Name" }
function Fail([string]$Name, [string]$Details) {
    $script:Failed++
    Write-Host "  FAIL - $Name"
    if ($Details) { Write-Host "         $Details" }
}

# ── Fixture ─────────────────────────────────────────────────────────

function New-Sandbox {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $root | Out-Null
    $script:Sandbox = $root
    $script:DataDir = Join-Path $root "localappdata" "Programs" "bsl-language-server"
    $script:PluginData = Join-Path $root "plugin-data"
    New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
}

function Remove-Sandbox {
    Remove-Item -LiteralPath $script:Sandbox -Recurse -Force
}

# Fake Windows layout: <DATA_DIR>/<version>/bsl-language-server/{bsl-language-server.exe,app/}
function Install-FakeVersion([string]$Version) {
    $serverDir = Join-Path $script:DataDir $Version "bsl-language-server"
    New-Item -ItemType Directory -Path (Join-Path $serverDir "app") -Force | Out-Null
    Set-Content -Path (Join-Path $serverDir "bsl-language-server.exe") -Value "fake-bsl $Version"
    Set-Content -Path (Join-Path $serverDir "app" "bsl-language-server.cfg") -Value "cfg $Version"
}

function Set-RecentServerInfo([string]$Version) {
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    @{ version = $Version; lastUpdate = $now } | ConvertTo-Json |
        Set-Content (Join-Path $script:DataDir "SERVER-INFO")
}

function Invoke-Hook([switch]$NoPluginData) {
    $env:LOCALAPPDATA = Join-Path $script:Sandbox "localappdata"
    $env:TEMP = $script:Sandbox
    if ($NoPluginData) {
        Remove-Item Env:CLAUDE_PLUGIN_DATA -ErrorAction SilentlyContinue
    } else {
        $env:CLAUDE_PLUGIN_DATA = $script:PluginData
    }
    $script:HookOutput = (& pwsh -NoProfile -File $Hook 2>&1 | Out-String).Trim()
}

function Get-LauncherContent {
    $exe = Join-Path $script:PluginData "bin" "bsl-language-server.exe"
    if (Test-Path -LiteralPath $exe) { return (Get-Content -LiteralPath $exe -Raw).Trim() }
    return "<missing $exe>"
}

# ── Tests ───────────────────────────────────────────────────────────

function Test-ExistingInstallGetsLauncher {
    $name = "existing install (throttled): launcher is created"
    New-Sandbox
    try {
        Install-FakeVersion "v1.0.0"
        Set-RecentServerInfo "v1.0.0"
        Invoke-Hook

        $content = Get-LauncherContent
        $cfg = Join-Path $script:PluginData "bin" "app" "bsl-language-server.cfg"
        if ($content -eq "fake-bsl v1.0.0" -and (Test-Path -LiteralPath $cfg)) {
            Pass $name
        } else {
            Fail $name "launcher: $content; app/ visible: $(Test-Path -LiteralPath $cfg); output: $script:HookOutput"
        }
    } finally { Remove-Sandbox }
}

function Test-LauncherIsRepointedWithoutTouchingOldTarget {
    $name = "version change: launcher re-pointed, old version files untouched"
    New-Sandbox
    try {
        Install-FakeVersion "v1.0.0"
        Install-FakeVersion "v1.1.0"
        Set-RecentServerInfo "v1.0.0"
        Invoke-Hook
        Set-RecentServerInfo "v1.1.0"
        Invoke-Hook

        $content = Get-LauncherContent
        $oldExe = Join-Path $script:DataDir "v1.0.0" "bsl-language-server" "bsl-language-server.exe"
        if ($content -eq "fake-bsl v1.1.0" -and (Test-Path -LiteralPath $oldExe)) {
            Pass $name
        } else {
            Fail $name "launcher: $content; old exe kept: $(Test-Path -LiteralPath $oldExe); output: $script:HookOutput"
        }
    } finally { Remove-Sandbox }
}

function Test-DanglingLauncherIsReplaced {
    $name = "dangling launcher (old version removed): launcher re-pointed"
    New-Sandbox
    try {
        Install-FakeVersion "v1.0.0"
        Set-RecentServerInfo "v1.0.0"
        Invoke-Hook
        Remove-Item -LiteralPath (Join-Path $script:DataDir "v1.0.0") -Recurse -Force
        Install-FakeVersion "v1.1.0"
        Set-RecentServerInfo "v1.1.0"
        Invoke-Hook

        $content = Get-LauncherContent
        if ($content -eq "fake-bsl v1.1.0") {
            Pass $name
        } else {
            Fail $name "launcher: $content; output: $script:HookOutput"
        }
    } finally { Remove-Sandbox }
}

function Test-MissingPluginDataWarns {
    $name = "no CLAUDE_PLUGIN_DATA: warns, still reports status"
    New-Sandbox
    try {
        Install-FakeVersion "v1.0.0"
        Set-RecentServerInfo "v1.0.0"
        Invoke-Hook -NoPluginData

        if ($script:HookOutput -match "CLAUDE_PLUGIN_DATA is not set" -and
            $script:HookOutput -match "Up to date \(v1\.0\.0\)") {
            Pass $name
        } else {
            Fail $name "output: $script:HookOutput"
        }
    } finally { Remove-Sandbox }
}

# ── Run ─────────────────────────────────────────────────────────────

Write-Host "check-bsl-ls.ps1"
Test-ExistingInstallGetsLauncher
Test-LauncherIsRepointedWithoutTouchingOldTarget
Test-DanglingLauncherIsReplaced
Test-MissingPluginDataWarns

Write-Host ""
Write-Host "passed: $script:Passed, failed: $script:Failed"
if ($script:Failed -gt 0) { exit 1 }
