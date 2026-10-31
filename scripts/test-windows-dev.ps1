#Requires -Version 5.1
# Offline build workflow checks; no compilers, package installs or user environment writes.
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot (".build/windows-dev-test-" + [Guid]::NewGuid().ToString("N"))
$fixtureScripts = Join-Path $testRoot "scripts"
$dashboardEntry = Join-Path $testRoot "Dashboard/dist/index.html"
$originalPath = $env:Path
$originalDashboard = $env:CORE_DASHBOARD_PATH
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")

function Assert-DevBuild {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Force -Path $fixtureScripts, (Split-Path -Parent $dashboardEntry) | Out-Null
    foreach ($file in @("dev.ps1", "install.ps1", "build-windows.ps1")) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $fixtureScripts
    }
    @'
function Initialize-SloppyPrerequisites {
    param([switch]$SkipInstall, [switch]$DryRun)
    if (-not $DryRun) { throw "Tests must not install or build real software." }
    $script:skipInstall = $SkipInstall.IsPresent
}
'@ | Set-Content -LiteralPath (Join-Path $fixtureScripts "windows-prerequisites.ps1")
    Set-Content -LiteralPath $dashboardEntry -Value "Dashboard fixture"
    $installer = Join-Path $fixtureScripts "install.ps1"
    $manager = Join-Path $fixtureScripts "dev.ps1"
    $fixtureInstall = Join-Path $testRoot "installed Sloppy"
    $plan = (& $installer -Fast -DryRun -InstallRoot $fixtureInstall 6>&1 | Out-String)
    Assert-DevBuild ($plan.Contains("(debug), reusing Dashboard/dist")) "Fast install must reuse the Dashboard and default to debug."
    $plan = (& $manager setup -Fast -Configuration release -DryRun -InstallRoot $fixtureInstall 6>&1 | Out-String)
    Assert-DevBuild ($plan.Contains("(release), reusing Dashboard/dist")) "Fast setup ignored an explicit release configuration."
    $plan = (& $installer -DryRun -InstallRoot $fixtureInstall 6>&1 | Out-String)
    Assert-DevBuild ($plan.Contains("sloppy, SloppyNode and Dashboard (release)")) "Normal setup must retain the full release build."
    & {
        . $manager -Fast -DryRun -InstallRoot $fixtureInstall
        Install-Sloppy
        Assert-DevBuild $script:skipInstall "Fast setup must not install prerequisites."
    }
    Remove-Item -LiteralPath $dashboardEntry
    $plan = (& $installer -Fast -DryRun -InstallRoot $fixtureInstall 6>&1 | Out-String)
    Assert-DevBuild ($plan.Contains("sloppy, SloppyNode and Dashboard (debug)")) "Fast setup must build a missing Dashboard."
    Assert-DevBuild (-not (Test-Path -LiteralPath $fixtureInstall)) "Dry run created an installation."

    & {
        . $manager -InstallRoot $fixtureInstall
        $serviceFixture = Join-Path $testRoot "service fixture"
        New-Item -ItemType Directory -Path $serviceFixture | Out-Null
        $executable = (Get-Process -Id $PID).Path
        @{ executablePath = $executable } | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $serviceFixture "service.json")
        @{ pid = $PID; startedAt = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString() } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $serviceFixture "process.json")
        Assert-DevBuild (Get-SloppyServiceInstallation -ServiceRoot $serviceFixture).running "Installer did not detect a running Windows service."
        $executable = Join-Path $fixtureInstall "bin/sloppy.exe"
        Assert-DevBuild ($null -eq (Get-SloppyServiceInstallation -ServiceRoot $serviceFixture)) "Installer matched a service owned by a different executable."
    }

    # Exercise the builder with command spies, including failure propagation.
    $devBuildState = @{ swiftCalls = @(); npmCalls = @(); swiftExit = 0 }
    function swift {
        $devBuildState.swiftCalls += ,@($args)
        $global:LASTEXITCODE = $devBuildState.swiftExit
        if ($args -contains "--show-bin-path") { Join-Path $testRoot "output" }
    }
    function node {}
    function npm.cmd { $devBuildState.npmCalls += ($args -join " "); $global:LASTEXITCODE = 0 }
    $builder = Join-Path $fixtureScripts "build-windows.ps1"
    $failed = $false
    try { & $builder -SkipDashboard } catch { $failed = $true }
    Assert-DevBuild ($failed -and $devBuildState.swiftCalls.Count -eq 0) "A missing Dashboard must fail before Swift builds."
    Set-Content -LiteralPath $dashboardEntry -Value "Dashboard fixture"
    & $builder -Configuration debug -Jobs 2 -SkipDashboard -SkipDependencyUpdate
    Assert-DevBuild ($devBuildState.npmCalls.Count -eq 0) "Reusing Dashboard must skip npm entirely."
    Assert-DevBuild (($devBuildState.swiftCalls[0] -join " ") -eq "build --configuration debug --jobs 2 --skip-update --product sloppy") "Fast Sloppy build options were lost."
    Assert-DevBuild (($devBuildState.swiftCalls[1] -join " ") -eq "build --configuration debug --jobs 2 --skip-update --product SloppyNode") "SloppyNode was not rebuilt."
    & $builder
    Assert-DevBuild (($devBuildState.npmCalls -join ",") -eq "ci,run typecheck,run build") "Normal builds must still install, check and build Dashboard."
    Assert-DevBuild (-not ($devBuildState.swiftCalls[3] -contains "--skip-update")) "Normal builds must retain dependency updates."
    $devBuildState.swiftExit = 1
    $failed = $false
    try { & $builder -SkipDashboard } catch { $failed = $true }
    Assert-DevBuild $failed "Swift build failures must stop the build script."
    & {
        . $manager -Fast -InstallRoot $fixtureInstall
        function Initialize-SloppyPrerequisites {}
        function Get-SloppyServer { return [pscustomobject]@{ Id = 42 } }
        function Stop-SloppyServer { $devBuildState.stopped = $true }
        New-Item -ItemType Directory -Force -Path $fixtureInstall | Out-Null
        @{ configPath = $null } | ConvertTo-Json | Set-Content -LiteralPath $stateFile
        $devBuildState.stopped = $false
        $failed = $false
        try { Install-Sloppy } catch { $failed = $true }
        Assert-DevBuild ($failed -and -not $devBuildState.stopped) "A failed build must leave the running server untouched."
    }
    Assert-DevBuild ($env:Path -eq $originalPath -and $env:CORE_DASHBOARD_PATH -eq $originalDashboard) "Tests changed the process environment."
    Assert-DevBuild ([Environment]::GetEnvironmentVariable("Path", "User") -eq $userPath) "Tests changed user PATH."
    Write-Host "Windows fast setup, configuration overrides, Dashboard reuse/fallback and build failure checks passed."
} finally {
    $env:Path = $originalPath
    $env:CORE_DASHBOARD_PATH = $originalDashboard
    Write-Host "Build workflow fixtures: $testRoot"
}
