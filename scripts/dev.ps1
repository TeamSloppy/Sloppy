#Requires -Version 5.1
<#
.SYNOPSIS
Build, install, and manage Sloppy on Windows, including build prerequisites.
.PARAMETER Fast
Require installed prerequisites, use debug unless configured, and reuse cached dependencies and Dashboard/dist.
.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1 setup
.EXAMPLE
.\scripts\dev.ps1 start
.EXAMPLE
.\scripts\dev.ps1 setup -Fast
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("setup", "start", "stop", "restart", "status", "logs", "autostart", "autostart-off")]
    [string]$Command = "setup",
    [string]$InstallRoot = $(if ($env:SLOPPY_INSTALL_ROOT) { $env:SLOPPY_INSTALL_ROOT } else { Join-Path $env:LOCALAPPDATA "Sloppy" }),
    [ValidateSet("debug", "release")]
    [string]$Configuration = "release",
    [ValidateRange(1, 128)]
    [int]$Jobs = 4,
    [string]$ConfigPath,
    [switch]$SkipPrerequisites,
    [switch]$SkipBuild,
    [switch]$Fast,
    [switch]$NoPath,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
if ($Fast -and -not $PSBoundParameters.ContainsKey("Configuration")) { $Configuration = "debug" }
$repoRoot = Split-Path -Parent $PSScriptRoot
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$binDir = Join-Path $InstallRoot "bin"
$dashboardDir = Join-Path $InstallRoot "dashboard"
$stateFile = Join-Path $InstallRoot "server.json"
$logDir = Join-Path $InstallRoot "logs"
$executable = Join-Path $binDir "sloppy.exe"
$autostartKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

. "$PSScriptRoot/windows-prerequisites.ps1"

function Get-SloppyServer {
    if (-not (Test-Path -LiteralPath $stateFile)) { return $null }
    try {
        $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        $process = Get-Process -Id $state.pid -ErrorAction Stop
        # A PID alone can belong to an unrelated process after a reboot or a crash.
        if ($process.Path -ne $executable -or
            $process.StartTime.ToUniversalTime().Ticks.ToString() -ne $state.startedAt) { return $null }
        return $process
    } catch { return $null }
}

function Stop-SloppyServer {
    $server = Get-SloppyServer
    if ($server) {
        & taskkill.exe /pid $server.Id /t /f | Out-Host
        if ($LASTEXITCODE -ne 0 -and -not $server.HasExited) { throw "Could not stop Sloppy (PID $($server.Id))." }
        $server.WaitForExit(10000) | Out-Null
        Write-Host "Sloppy server stopped."
    } else { Write-Host "Sloppy server is not running." }
    if (Test-Path -LiteralPath $stateFile) { Remove-Item -LiteralPath $stateFile -Force }
}

function Start-SloppyServer {
    param([string]$ServerConfigPath = $ConfigPath)
    $server = Get-SloppyServer
    if ($server) { Write-Host "Sloppy server is already running (PID $($server.Id))."; return }
    if (-not (Test-Path -LiteralPath $executable)) { throw "Sloppy is not installed. Run scripts/dev.ps1 setup first." }
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $arguments = @("run")
    $resolvedConfig = $null
    if ($ServerConfigPath) {
        $resolvedConfig = (Resolve-Path -LiteralPath $ServerConfigPath).Path
        $arguments += @("--config-path", ('"' + $resolvedConfig + '"'))
    }
    $previousDashboard = $env:CORE_DASHBOARD_PATH
    try {
        $env:CORE_DASHBOARD_PATH = $dashboardDir
        $server = Start-Process -FilePath $executable -ArgumentList $arguments -WorkingDirectory $InstallRoot `
            -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logDir "server.stdout.log") `
            -RedirectStandardError (Join-Path $logDir "server.stderr.log")
    } finally { $env:CORE_DASHBOARD_PATH = $previousDashboard }
    try {
        @{
            pid = $server.Id
            startedAt = $server.StartTime.ToUniversalTime().Ticks.ToString()
            configPath = $resolvedConfig
        } | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
        Start-Sleep -Seconds 2
        if ($server.HasExited) { throw "Sloppy exited during startup. Check $logDir/server.stderr.log." }
    } catch {
        if (-not $server.HasExited) { & taskkill.exe /pid $server.Id /t /f | Out-Null }
        if (Test-Path -LiteralPath $stateFile) { Remove-Item -LiteralPath $stateFile -Force }
        throw
    }
    Write-Host "Sloppy server started (PID $($server.Id)). Dashboard: http://127.0.0.1:25102"
    Write-Host "Logs: $logDir"
}

function Add-SloppyToPath {
    $userPath = Get-SloppyUserEnvironment "Path"
    $entries = @($userPath -split ";" | Where-Object { $_ })
    $normalized = $binDir.TrimEnd('\')
    if (-not ($entries | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -eq $normalized })) {
        Set-SloppyUserEnvironment "Path" (($entries + $binDir) -join ";")
    }
    Set-SloppyUserEnvironment "CORE_DASHBOARD_PATH" $dashboardDir
    $env:CORE_DASHBOARD_PATH = $dashboardDir
    if ($binDir -notin ($env:Path -split ";")) { $env:Path = "$binDir;$env:Path" }
    # Notify Explorer so terminals opened after installation receive the updated environment.
    if (-not ("Sloppy.EnvironmentBroadcast" -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace Sloppy {
    public static class EnvironmentBroadcast {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam,
            string lParam, uint flags, uint timeout, out UIntPtr result);
    }
}
'@
    }
    $result = [UIntPtr]::Zero
    [Sloppy.EnvironmentBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero,
        "Environment", 2, 5000, [ref]$result) | Out-Null
}

function Get-SloppyUserEnvironment {
    param([string]$Name)
    return [Environment]::GetEnvironmentVariable($Name, "User")
}

function Set-SloppyUserEnvironment {
    param([string]$Name, [string]$Value)
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
}

function Get-SloppyServiceInstallation {
    param([string]$ServiceRoot = (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".sloppy/service"))
    $settingsPath = Join-Path $ServiceRoot "service.json"
    if (-not (Test-Path -LiteralPath $settingsPath)) { return $null }
    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        if ($settings.executablePath -ne $executable) { return $null }
        $running = $false
        $processPath = Join-Path $ServiceRoot "process.json"
        if (Test-Path -LiteralPath $processPath) {
            $state = Get-Content -LiteralPath $processPath -Raw | ConvertFrom-Json
            $server = Get-Process -Id $state.pid -ErrorAction SilentlyContinue
            $running = $server -and $server.Path -eq $executable -and
                $server.StartTime.ToUniversalTime().Ticks.ToString() -eq $state.startedAt
        }
        return [pscustomobject]@{ running = [bool]$running; runner = (Join-Path $ServiceRoot "service.ps1") }
    } catch { return $null }
}

function Install-Sloppy {
    Initialize-SloppyPrerequisites -SkipInstall:($SkipPrerequisites -or $Fast) -DryRun:$DryRun
    $skipDashboard = $Fast -and (Test-Path -LiteralPath (Join-Path $repoRoot "Dashboard/dist/index.html"))
    if ($DryRun) {
        if ($SkipBuild) { Write-Host "Would use existing $Configuration build outputs." }
        elseif ($skipDashboard) { Write-Host "Would build sloppy and SloppyNode ($Configuration), reusing Dashboard/dist." }
        else { Write-Host "Would build sloppy, SloppyNode and Dashboard ($Configuration)." }
        Write-Host "Would install executables, Swift runtime DLLs and resources into $binDir."
        Write-Host "Would install Dashboard into $dashboardDir."
        if (-not $NoPath) { Write-Host "Would add $binDir to user PATH and set CORE_DASHBOARD_PATH." }
        return
    }
    $wasRunning = $null -ne (Get-SloppyServer)
    $serviceInstallation = Get-SloppyServiceInstallation
    $runningConfigPath = $null
    if ($wasRunning) { $runningConfigPath = (Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).configPath }
    if (-not $SkipBuild) {
        & "$PSScriptRoot/build-windows.ps1" -Configuration $Configuration -Jobs $Jobs `
            -SkipDashboard:$skipDashboard -SkipDependencyUpdate:$Fast
    }
    $binPath = (& swift build --package-path $repoRoot --configuration $Configuration --show-bin-path | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not locate build output." }
    foreach ($product in @("sloppy.exe", "SloppyNode.exe")) {
        if (-not (Test-Path -LiteralPath (Join-Path $binPath $product))) { throw "Missing $product. Rerun setup without -SkipBuild." }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "Dashboard/dist/index.html"))) { throw "Dashboard is not built. Rerun setup without -SkipBuild." }
    if ($wasRunning) { Stop-SloppyServer }
    if ($serviceInstallation -and $serviceInstallation.running) {
        & $executable service stop
        if ($LASTEXITCODE -ne 0) { throw "Could not stop the Windows service before updating Sloppy." }
    }
    New-Item -ItemType Directory -Force -Path $binDir, $dashboardDir | Out-Null
    foreach ($product in @("sloppy.exe", "SloppyNode.exe")) {
        Copy-Item -LiteralPath (Join-Path $binPath $product) -Destination $binDir -Force
    }
    # SwiftPM looks for these bundles beside the executable at runtime.
    foreach ($bundle in Get-ChildItem -LiteralPath $binPath -Directory -Filter "*.resources") {
        Copy-Item -LiteralPath $bundle.FullName -Destination $binDir -Recurse -Force
    }
    if ($serviceInstallation) {
        Copy-Item -LiteralPath (Join-Path $binDir "Sloppy_sloppy.resources/Windows/service.ps1") `
            -Destination $serviceInstallation.runner -Force
    }
    $targetInfo = (& swift -print-target-info) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Could not locate the Swift runtime." }
    foreach ($runtime in ($targetInfo | ConvertFrom-Json).paths.runtimeLibraryPaths) {
        foreach ($dll in @(Get-ChildItem -LiteralPath $runtime -Filter "*.dll" -File -ErrorAction SilentlyContinue)) {
            Copy-Item -LiteralPath $dll.FullName -Destination $binDir -Force
        }
    }
    foreach ($dll in Get-ChildItem -LiteralPath $binPath -Filter "*.dll" -File) {
        Copy-Item -LiteralPath $dll.FullName -Destination $binDir -Force
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot "Dashboard/dist") -Destination $dashboardDir -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "Dashboard/config.json") -Destination $dashboardDir -Force
    & $executable --version
    if ($LASTEXITCODE -ne 0) { throw "Installed Sloppy could not start (exit $LASTEXITCODE)." }
    if (-not $NoPath) { Add-SloppyToPath }
    if ($wasRunning) { Start-SloppyServer -ServerConfigPath $runningConfigPath }
    if ($serviceInstallation -and $serviceInstallation.running) {
        & $executable service start
        if ($LASTEXITCODE -ne 0) { throw "Windows service failed to restart. Check: sloppy service logs" }
    }
    Write-Host "Installation complete: $binDir"
    if ($NoPath) { Write-Host "Run: & '$executable' (TUI), or add run for server + Dashboard." }
    else { Write-Host "Open a new terminal: sloppy (TUI), sloppy run (server + Dashboard)." }
    Write-Host "Background server: .\scripts\dev.ps1 start"
}

function Set-SloppyAutostart {
    param([bool]$Enabled)
    if (-not $Enabled) {
        Remove-ItemProperty -LiteralPath $autostartKey -Name Sloppy -ErrorAction SilentlyContinue
        Write-Host "Sloppy login autostart removed."
        return
    }
    if (-not (Test-Path -LiteralPath $executable)) { throw "Run setup before enabling autostart." }
    $scriptPath = Join-Path $PSScriptRoot "dev.ps1"
    $commandLine = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $scriptPath + '" start -InstallRoot "' + $InstallRoot + '"'
    if ($ConfigPath) { $commandLine += ' -ConfigPath "' + (Resolve-Path -LiteralPath $ConfigPath).Path + '"' }
    New-Item -Path $autostartKey -Force | Out-Null
    New-ItemProperty -LiteralPath $autostartKey -Name Sloppy -Value $commandLine -PropertyType String -Force | Out-Null
    Write-Host "Sloppy will start at Windows login. Keep this checkout at $repoRoot."
}

if ($MyInvocation.InvocationName -ne ".") {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        [Environment]::OSVersion.Version.Build -lt 17763 -or -not [Environment]::Is64BitProcess) {
        throw "Run this script on Windows 10 1809+ or Windows 11 in 64-bit Windows PowerShell 5.1 or PowerShell 7."
    }
    if ($DryRun -and $Command -ne "setup") { Write-Host "Would run Sloppy command '$Command' for $InstallRoot."; return }
    switch ($Command) {
        "setup" { Install-Sloppy }
        "start" { Start-SloppyServer }
        "stop" { Stop-SloppyServer }
        "restart" {
            $restartConfig = $ConfigPath
            if (-not $restartConfig -and (Get-SloppyServer)) {
                $restartConfig = (Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).configPath
            }
            Stop-SloppyServer
            Start-SloppyServer -ServerConfigPath $restartConfig
        }
        "status" {
            $server = Get-SloppyServer
            if ($server) { Write-Host "Sloppy server is running (PID $($server.Id))." }
            else { Write-Host "Sloppy server is not running." }
        }
        "logs" {
            $log = Join-Path $logDir "server.stderr.log"
            if (-not (Test-Path -LiteralPath $log)) { throw "No server logs yet. Run start first." }
            Get-Content -LiteralPath $log -Tail 50 -Wait
        }
        "autostart" { Set-SloppyAutostart $true }
        "autostart-off" { Set-SloppyAutostart $false }
    }
}
