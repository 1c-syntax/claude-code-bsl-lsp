# Tests for hooks/check-bsl-ls.ps1.
# GitHub is replaced by a local HTTP server (python) serving fake releases
# via BSL_LS_GITHUB_API_URL / BSL_LS_GITHUB_URL; no internet access is needed.
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
    $script:GitHubUrl = $null
    $script:DataDir = Join-Path $root "localappdata" "Programs" "bsl-language-server"
    $script:PluginData = Join-Path $root "plugin-data"
    New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
}

function Remove-Sandbox {
    if ($script:Server) {
        Stop-Process -Id $script:Server.Id -Force -ErrorAction SilentlyContinue
        $script:Server.WaitForExit()
        $script:Server = $null
    }
    Remove-Item -LiteralPath $script:Sandbox -Recurse -Force
}

# Fake Windows layout: <dir>/bsl-language-server/{bsl-language-server.exe,app/}
function New-FakeServerDir([string]$Root, [string]$Version) {
    $serverDir = Join-Path $Root "bsl-language-server"
    New-Item -ItemType Directory -Path (Join-Path $serverDir "app") -Force | Out-Null
    Set-Content -Path (Join-Path $serverDir "bsl-language-server.exe") -Value "fake-bsl $Version"
    Set-Content -Path (Join-Path $serverDir "app" "bsl-language-server.cfg") -Value "cfg $Version"
    return $serverDir
}

function Install-FakeVersion([string]$Version) {
    New-FakeServerDir (Join-Path $script:DataDir $Version) $Version | Out-Null
}

function Set-ServerInfo([string]$Version, [long]$LastUpdate) {
    @{ version = $Version; lastUpdate = $LastUpdate } | ConvertTo-Json |
        Set-Content (Join-Path $script:DataDir "SERVER-INFO")
}

function Set-RecentServerInfo([string]$Version) {
    Set-ServerInfo $Version ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
}

# Serves <sandbox>/www over HTTP as a fake GitHub with $Version as latest release
function Start-FakeGitHub([string]$Version) {
    $www = Join-Path $script:Sandbox "www"
    $api = Join-Path $www "repos" "1c-syntax" "bsl-language-server" "releases"
    $dl = Join-Path $www "1c-syntax" "bsl-language-server" "releases" "download" $Version
    New-Item -ItemType Directory -Path $api, $dl -Force | Out-Null
    @{ tag_name = $Version } | ConvertTo-Json | Set-Content (Join-Path $api "latest")

    $build = Join-Path $script:Sandbox "build-$Version"
    $serverDir = New-FakeServerDir $build $Version
    Compress-Archive -Path $serverDir -DestinationPath (Join-Path $dl "bsl-language-server_win.zip")

    $serverScript = Join-Path $script:Sandbox "server.py"
    @'
import functools, http.server, sys
class Handler(http.server.SimpleHTTPRequestHandler):
    def guess_type(self, path):
        return "application/json" if path.endswith("latest") else "application/zip"
    def log_message(self, *args):
        pass
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=sys.argv[1]))
print(server.server_address[1], flush=True)
server.serve_forever()
'@ | Set-Content $serverScript

    $python = if ($IsWindows) { "python" } else { "python3" }
    $portFile = Join-Path $script:Sandbox "port"
    $script:Server = Start-Process -FilePath $python -ArgumentList "`"$serverScript`"", "`"$www`"" `
        -RedirectStandardOutput $portFile -PassThru -NoNewWindow
    $deadline = (Get-Date).AddSeconds(15)
    while (-not ((Test-Path $portFile) -and (Get-Content $portFile -Raw))) {
        if ((Get-Date) -gt $deadline) { throw "fake GitHub server did not start" }
        Start-Sleep -Milliseconds 100
    }
    $script:GitHubUrl = "http://127.0.0.1:$((Get-Content $portFile -Raw).Trim())"
}

function Invoke-Hook([switch]$NoPluginData) {
    $env:LOCALAPPDATA = Join-Path $script:Sandbox "localappdata"
    $env:TEMP = $script:Sandbox
    # Without a fake server GitHub is unreachable (closed port)
    $url = if ($script:GitHubUrl) { $script:GitHubUrl } else { "http://127.0.0.1:9" }
    $env:BSL_LS_GITHUB_API_URL = $url
    $env:BSL_LS_GITHUB_URL = $url
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

function Test-UpdateDownloadsAndRepointsLauncher {
    $name = "update: new release downloaded, launcher re-pointed, old version removed"
    New-Sandbox
    try {
        Install-FakeVersion "v1.0.0"
        Set-ServerInfo "v1.0.0" 0
        Start-FakeGitHub "v1.1.0"
        Invoke-Hook

        $content = Get-LauncherContent
        $oldDir = Join-Path $script:DataDir "v1.0.0"
        if ($content -eq "fake-bsl v1.1.0" -and -not (Test-Path -LiteralPath $oldDir)) {
            Pass $name
        } else {
            Fail $name "launcher: $content; old dir kept: $(Test-Path -LiteralPath $oldDir); output: $script:HookOutput"
        }
    } finally { Remove-Sandbox }
}

function Test-FailedLauncherKeepsOldVersion {
    $name = "launcher failure on update: previous version is not removed"
    New-Sandbox
    try {
        Install-FakeVersion "v1.0.0"
        Set-ServerInfo "v1.0.0" 0
        Set-Content -Path $script:PluginData -Value "" # a file: nothing can be created inside
        Start-FakeGitHub "v1.1.0"
        Invoke-Hook

        $oldDir = Join-Path $script:DataDir "v1.0.0"
        if ((Test-Path -LiteralPath $oldDir) -and $script:HookOutput -match "Installed v1\.1\.0") {
            Pass $name
        } else {
            Fail $name "old dir kept: $(Test-Path -LiteralPath $oldDir); output: $script:HookOutput"
        }
    } finally { Remove-Sandbox }
}

function Test-OfflineWithMissingBinaryReportsIt {
    $name = "offline + missing binary: reported, not claimed as in use"
    New-Sandbox
    try {
        Set-ServerInfo "v1.0.0" 0 # recorded, but not on disk
        Invoke-Hook

        if ($script:HookOutput -notmatch "Offline, using" -and $script:HookOutput -match "binary not found") {
            Pass $name
        } else {
            Fail $name "output: $script:HookOutput"
        }
    } finally { Remove-Sandbox }
}

function Test-FailedDownloadKeepsInstalledVersionLinked {
    $name = "failed download: launcher points to the installed version"
    New-Sandbox
    try {
        Install-FakeVersion "v1.0.0"
        Set-ServerInfo "v1.0.0" 0
        Start-FakeGitHub "v1.1.0"
        Get-ChildItem -Path (Join-Path $script:Sandbox "www") -Recurse -Filter *.zip | Remove-Item
        Invoke-Hook

        $content = Get-LauncherContent
        if ($content -eq "fake-bsl v1.0.0") {
            Pass $name
        } else {
            Fail $name "launcher: $content; output: $script:HookOutput"
        }
    } finally { Remove-Sandbox }
}

# ── Run ─────────────────────────────────────────────────────────────

Write-Host "check-bsl-ls.ps1"
Test-ExistingInstallGetsLauncher
Test-LauncherIsRepointedWithoutTouchingOldTarget
Test-DanglingLauncherIsReplaced
Test-MissingPluginDataWarns
Test-UpdateDownloadsAndRepointsLauncher
Test-FailedLauncherKeepsOldVersion
Test-OfflineWithMissingBinaryReportsIt
Test-FailedDownloadKeepsInstalledVersionLinked

Write-Host ""
Write-Host "passed: $script:Passed, failed: $script:Failed"
if ($script:Failed -gt 0) { exit 1 }
