#Requires -Version 5.1
[CmdletBinding()]
param([ValidateSet("debug", "release")][string]$Configuration = "release")

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot (".build/windows-install-smoke-" + [Guid]::NewGuid().ToString("N"))
$installRoot = Join-Path $testRoot "installed Sloppy"
$manager = Join-Path $PSScriptRoot "dev.ps1"
$installer = Join-Path $PSScriptRoot "install.ps1"
$originalPath = $env:Path
$originalDashboard = $env:CORE_DASHBOARD_PATH
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$userDashboard = [Environment]::GetEnvironmentVariable("CORE_DASHBOARD_PATH", "User")

function Assert-SloppyInstall {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

# Exercise a clean-machine package plan and recovery without installing software on the test host.
& {
    . "$PSScriptRoot/windows-prerequisites.ps1"
    $script:installedPackages = @{}
    function Update-SloppyEnvironment {}
    function Test-SloppyToolVersion {
        param($Command, $Minimum)
        $id = @{ "git.exe" = "Git.Git"; "node.exe" = "OpenJS.NodeJS.LTS"; "swift.exe" = "Swift.Toolchain" }[$Command]
        return $script:installedPackages.ContainsKey($id)
    }
    function Test-SloppyBuildTools { return $script:installedPackages.ContainsKey("Microsoft.VisualStudio.2022.BuildTools") }
    function Test-SloppyWindowsSDK { return Test-SloppyBuildTools }
    function Install-SloppyWinGet { $script:bootstrapped = $true }
    function Enable-SloppyDeveloperMode { $script:developerMode = $true }
    function Install-SloppyPackage { param($Id); $script:installedPackages[$Id] = $true }
    $expected = @("Git.Git", "OpenJS.NodeJS.LTS", "Microsoft.VisualStudio.2022.BuildTools", "Swift.Toolchain")
    Assert-SloppyInstall ((@(Get-SloppyMissingPackages) -join ",") -eq ($expected -join ",")) "Clean-machine package plan is incomplete."
    $failed = $false
    try { Initialize-SloppyPrerequisites -SkipInstall } catch { $failed = $true }
    Assert-SloppyInstall $failed "Missing dependencies must fail with -SkipPrerequisites."
    Initialize-SloppyPrerequisites
    Assert-SloppyInstall ($script:bootstrapped -and $script:developerMode -and $script:installedPackages.Count -eq 4) "Dependency installation did not complete."
    function Install-SloppyWinGet { throw "An installed machine must not bootstrap WinGet." }
    function Install-SloppyPackage { throw "An installed machine must not reinstall packages." }
    Initialize-SloppyPrerequisites
}
Write-Host "Windows prerequisite planning and repeat setup checks passed."

& {
    . "$PSScriptRoot/windows-prerequisites.ps1"
    function Update-SloppyEnvironment {}
    function winget.exe { $script:wingetArguments = @($args); $global:LASTEXITCODE = $script:wingetResult }
    $script:wingetResult = 0
    Install-SloppyPackage "Swift.Toolchain"
    $versionIndex = [Array]::IndexOf($script:wingetArguments, "--version")
    Assert-SloppyInstall ($versionIndex -ge 0 -and $script:wingetArguments[$versionIndex + 1] -eq "6.3.1") "Swift installation is not pinned to the tested toolchain."
    Install-SloppyPackage "Microsoft.VisualStudio.2022.BuildTools"
    $overrideIndex = [Array]::IndexOf($script:wingetArguments, "--override")
    Assert-SloppyInstall ($overrideIndex -ge 0 -and
        $script:wingetArguments[$overrideIndex + 1].Contains("--add Microsoft.VisualStudio.Component.Windows11SDK.22621")) "C++ installer lost its SDK options."
    foreach ($code in @(3010, 123)) {
        $script:wingetResult = $code
        $failed = $false
        try { Install-SloppyPackage "Swift.Toolchain" } catch { $failed = $true }
        Assert-SloppyInstall $failed "Installer errors and reboot requirements must stop setup."
    }
}

New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    & {
        . $manager -InstallRoot $installRoot
        $script:userEnvironment = @{ Path = "C:\Existing Tools" }
        function Get-SloppyUserEnvironment { param($Name); return $script:userEnvironment[$Name] }
        function Set-SloppyUserEnvironment { param($Name, $Value); $script:userEnvironment[$Name] = $Value }
        Add-SloppyToPath
        Add-SloppyToPath
        Assert-SloppyInstall ($script:userEnvironment.Path -eq "C:\Existing Tools;$installRoot\bin") "PATH installation discarded entries or added a duplicate."
        Assert-SloppyInstall ($script:userEnvironment.CORE_DASHBOARD_PATH -eq "$installRoot\dashboard") "Installed Dashboard environment is missing."
    }
    $env:Path = $originalPath
    $env:CORE_DASHBOARD_PATH = $originalDashboard
    # This uses real build outputs, copies the runtime, and never writes the user's environment.
    & $installer -InstallRoot $installRoot -Configuration $Configuration -Fast -SkipBuild -NoPath
    & $installer -InstallRoot $installRoot -Configuration $Configuration -SkipPrerequisites -SkipBuild -NoPath
    $installedExe = Join-Path $installRoot "bin/sloppy.exe"
    Assert-SloppyInstall (Test-Path -LiteralPath (Join-Path $installRoot "bin/Sloppy_sloppy.resources/schema.sql")) "SQLite resource bundle was not installed."
    Assert-SloppyInstall (Test-Path -LiteralPath (Join-Path $installRoot "dashboard/dist/index.html")) "Dashboard was not installed."
    Assert-SloppyInstall (-not (Test-Path -LiteralPath (Join-Path $installRoot "dashboard/dist/dist"))) "Repeated installation nested the Dashboard bundle."
    & {
        . $manager -InstallRoot $installRoot
        $script:autostartValue = $null
        function New-Item { param($Path, [switch]$Force) }
        function New-ItemProperty {
            param($LiteralPath, $Name, $Value, $PropertyType, [switch]$Force)
            $script:autostartValue = $Value
        }
        function Remove-ItemProperty {
            [CmdletBinding()]param($LiteralPath, $Name)
            $script:autostartValue = $null
        }
        Set-SloppyAutostart $true
        Assert-SloppyInstall ($script:autostartValue.Contains('-WindowStyle Hidden') -and
            $script:autostartValue.Contains('start -InstallRoot "' + $installRoot + '"')) "Login autostart command is not correctly quoted."
        Set-SloppyAutostart $false
        Assert-SloppyInstall ($null -eq $script:autostartValue) "Login autostart was not removed."
    }
    $env:Path = (Join-Path $env:SystemRoot "System32") + ";" + (Join-Path $installRoot "bin")
    & $installedExe --version
    Assert-SloppyInstall ($LASTEXITCODE -eq 0) "Installed Sloppy requires the Swift toolchain PATH."
    $env:Path = $originalPath

    # A stale PID must never cause stop to terminate an unrelated process.
    @{ pid = $PID; startedAt = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString() } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $installRoot "server.json") -Encoding UTF8
    & $manager stop -InstallRoot $installRoot
    Assert-SloppyInstall (-not (Test-Path -LiteralPath (Join-Path $installRoot "server.json"))) "Stale server state was not cleared."

    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 25102)
    try { $probe.Start() } finally { $probe.Stop() }
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    $config = Join-Path $testRoot "server config.json"
    @{
        listen = @{ host = "127.0.0.1"; port = $port }
        workspace = @{ basePath = $testRoot; name = "workspace" }
        auth = @{ token = "" }; models = @(); plugins = @(); gateways = @(); nodes = @("local")
        memory = @{ backend = "sqlite-local-vectors" }; sqlitePath = "core.sqlite"
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $config -Encoding UTF8
    & $manager start -InstallRoot $installRoot -ConfigPath $config
    $firstState = Get-Content -LiteralPath (Join-Path $installRoot "server.json") -Raw | ConvertFrom-Json
    & $manager start -InstallRoot $installRoot -ConfigPath $config
    $secondState = Get-Content -LiteralPath (Join-Path $installRoot "server.json") -Raw | ConvertFrom-Json
    Assert-SloppyInstall ($firstState.pid -eq $secondState.pid) "Repeated start launched another server."
    $health = Invoke-WebRequest "http://127.0.0.1:$port/health" -UseBasicParsing -TimeoutSec 15
    Assert-SloppyInstall ($health.StatusCode -eq 200) "Installed server health failed."
    $dashboard = Invoke-WebRequest "http://127.0.0.1:25102/" -UseBasicParsing -TimeoutSec 15
    Assert-SloppyInstall ($dashboard.StatusCode -eq 200) "Installed Dashboard failed."
    $log = Get-Content -LiteralPath (Join-Path $installRoot "logs/server.stderr.log") -Raw
    Assert-SloppyInstall ($log.Contains("Using dashboard bundle from override")) "Server did not use the installed Dashboard."
    & $manager status -InstallRoot $installRoot
    & $installer -InstallRoot $installRoot -Configuration $Configuration -SkipPrerequisites -SkipBuild -NoPath
    $firstState = Get-Content -LiteralPath (Join-Path $installRoot "server.json") -Raw | ConvertFrom-Json
    Assert-SloppyInstall ($firstState.configPath -eq $config) "Updating a running installation lost the server config."
    $null = Invoke-WebRequest "http://127.0.0.1:$port/health" -UseBasicParsing -TimeoutSec 15
    & $manager restart -InstallRoot $installRoot
    $newState = Get-Content -LiteralPath (Join-Path $installRoot "server.json") -Raw | ConvertFrom-Json
    Assert-SloppyInstall ($newState.pid -ne $firstState.pid) "Restart did not replace the server process."
    Assert-SloppyInstall ($newState.configPath -eq $config) "Restart lost the server config."
    & $manager stop -InstallRoot $installRoot
    & $manager stop -InstallRoot $installRoot
    Assert-SloppyInstall ($userPath -eq [Environment]::GetEnvironmentVariable("Path", "User")) "Smoke test changed user PATH."
    Assert-SloppyInstall ($userDashboard -eq [Environment]::GetEnvironmentVariable("CORE_DASHBOARD_PATH", "User")) "Smoke test changed user Dashboard configuration."
    Write-Host "Windows installed runtime, resources, Dashboard, start/status/restart/stop and stale PID checks passed."
} finally {
    $env:Path = $originalPath
    $env:CORE_DASHBOARD_PATH = $originalDashboard
    & $manager stop -InstallRoot $installRoot
    Write-Host "Installer smoke logs and files: $testRoot"
}
