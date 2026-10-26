#Requires -Version 5.1
# Offline acceptance checks: no software installation, network or user PATH writes.
$ErrorActionPreference = "Stop"
$bootstrap = Join-Path $PSScriptRoot "bootstrap-windows-source.ps1"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("sloppy-bootstrap-" + [Guid]::NewGuid().ToString("N"))
$installRoot = Join-Path $testRoot "installed Sloppy"
$global:SloppyBootstrapTestState = @{
    gitCalls = @()
    dirty = $false
    failClone = $false
    origin = "https://github.com/TeamSloppy/Sloppy.git"
}
$originalOS = $env:OS
$env:OS = "Windows_NT"

function Assert-Bootstrap {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Invoke-RestMethod {
    param($Uri)
    Assert-Bootstrap ($Uri -eq "https://raw.githubusercontent.com/TeamSloppy/Sloppy/main/scripts/windows-prerequisites.ps1") "Unexpected download URL."
    return 'function Initialize-SloppyPrerequisites { $script:prerequisitesChecked = $true }'
}
function git.exe {
    $global:SloppyBootstrapTestState.gitCalls += ($args -join " ")
    $global:LASTEXITCODE = 0
    if ($args[0] -eq "clone") {
        $destination = $args[-1]
        New-Item -ItemType Directory -Force -Path (Join-Path $destination ".git"), (Join-Path $destination "scripts") | Out-Null
        if ($global:SloppyBootstrapTestState.failClone) { $global:LASTEXITCODE = 1; return }
        @'
param([string]$InstallRoot, [switch]$SkipPrerequisites, [switch]$NoPath)
if (-not $SkipPrerequisites -or -not $NoPath) { throw "Installer options were not forwarded." }
Set-Content -LiteralPath (Join-Path $InstallRoot "installed.txt") -Value "ok"
'@ | Set-Content -LiteralPath (Join-Path $destination "scripts/install.ps1")
    } elseif ($args[2] -eq "remote") { return $global:SloppyBootstrapTestState.origin }
    elseif ($args[2] -eq "branch") { return "main" }
    elseif ($args[2] -eq "status" -and $global:SloppyBootstrapTestState.dirty) { return " M user-work.swift" }
}
function powershell.exe {
    Assert-Bootstrap ($args[0] -eq "-NoProfile" -and $args[1] -eq "-ExecutionPolicy" -and $args[2] -eq "Bypass") "Setup must allow scripts in its own process without changing the user's execution policy."
    & $args[4] -InstallRoot $args[6] -SkipPrerequisites -NoPath
    $global:LASTEXITCODE = 0
}

try {
    & $bootstrap -InstallRoot $installRoot -DryRun
    Assert-Bootstrap (-not (Test-Path -LiteralPath $installRoot)) "Dry run created files."
    Assert-Bootstrap ($global:SloppyBootstrapTestState.gitCalls.Count -eq 0) "Dry run invoked Git."

    & $bootstrap -InstallRoot $installRoot -NoPath
    Assert-Bootstrap (Test-Path -LiteralPath (Join-Path $installRoot "installed.txt")) "Fresh bootstrap did not invoke the installer."
    Assert-Bootstrap ($global:SloppyBootstrapTestState.gitCalls[0].StartsWith("clone --depth 1 --branch main")) "Fresh bootstrap did not clone main."
    $global:SloppyBootstrapTestState.gitCalls = @()
    & $bootstrap -InstallRoot $installRoot -NoPath
    Assert-Bootstrap (($global:SloppyBootstrapTestState.gitCalls -join "|").Contains("merge --ff-only origin/main")) "Repeat bootstrap did not fast-forward."

    $global:SloppyBootstrapTestState.dirty = $true
    $global:SloppyBootstrapTestState.gitCalls = @()
    $rejected = $false
    try { & $bootstrap -InstallRoot $installRoot -NoPath } catch { $rejected = $true }
    Assert-Bootstrap $rejected "Dirty checkout was not rejected."
    Assert-Bootstrap (-not (($global:SloppyBootstrapTestState.gitCalls -join "|") -match "fetch|merge|reset|clean")) "Dirty checkout was changed."
    $global:SloppyBootstrapTestState.dirty = $false
    $global:SloppyBootstrapTestState.origin = "https://example.com/other.git"
    $rejected = $false
    try { & $bootstrap -InstallRoot $installRoot -NoPath } catch { $rejected = $true }
    Assert-Bootstrap $rejected "Foreign checkout was not rejected."

    $global:SloppyBootstrapTestState.failClone = $true
    $failedRoot = Join-Path $testRoot "failed install"
    $rejected = $false
    try { & $bootstrap -InstallRoot $failedRoot -NoPath } catch { $rejected = $true }
    Assert-Bootstrap $rejected "Failed clone was accepted."
    Assert-Bootstrap (@(Get-ChildItem -LiteralPath $failedRoot).Count -eq 0) "Failed clone left a broken source checkout."
    Write-Host "Windows bootstrap: dry run, fresh setup, repeat setup, dirty/foreign checkout and download failure passed."
} finally {
    $env:OS = $originalOS
    Remove-Variable -Name SloppyBootstrapTestState -Scope Global
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
