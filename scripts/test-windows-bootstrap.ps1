#Requires -Version 5.1
# Offline release-installer checks. No network, executable launch or user environment writes.
$ErrorActionPreference = "Stop"
$bootstrap = Join-Path $PSScriptRoot "bootstrap-windows.ps1"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("sloppy-binary-test-" + [Guid]::NewGuid().ToString("N"))
$installRoot = Join-Path $testRoot "installed Sloppy"
$global:SloppyReleaseTestState = @{
    root = $testRoot; installRoot = $installRoot; downloads = 0
    missing = $false; probeExit = 0; locked = $false; failMove = $false
}
$originalOS = $env:OS
$originalPath = $env:Path
$originalDashboard = $env:CORE_DASHBOARD_PATH
$env:OS = "Windows_NT"

function Assert-ReleaseInstall {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function New-ReleaseFixture {
    param([switch]$Incomplete)
    $payload = Join-Path $global:SloppyReleaseTestState.root "payload"
    if (Test-Path -LiteralPath $payload) { Remove-Item -LiteralPath $payload -Recurse -Force }
    foreach ($file in @("bin/sloppy.exe", "bin/SloppyNode.exe", "bin/swiftCore.dll", "bin/vcruntime140.dll", "dashboard/dist/index.html", "dashboard/config.json", "share/sloppy/licenses/NOTICE.txt")) {
        if ($Incomplete -and $file -eq "bin/swiftCore.dll") { continue }
        $path = Join-Path $payload $file
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        Set-Content -LiteralPath $path -Value "release fixture"
    }
    $zip = Join-Path $global:SloppyReleaseTestState.root "Sloppy-windows-x86_64.zip"
    Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $zip -Force
    ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash + "  Sloppy-windows-x86_64.zip") |
        Set-Content -LiteralPath (Join-Path $global:SloppyReleaseTestState.root "SHA256SUMS.txt")
}
function Invoke-RestMethod {
    param($Uri, $Headers)
    Assert-ReleaseInstall ($Uri -like "https://api.github.com/repos/TeamSloppy/Sloppy/releases/*") "Unexpected request; source or build tools must never be downloaded by default."
    $assets = @(@{ name = "SHA256SUMS.txt"; browser_download_url = "https://fixture.invalid/SHA256SUMS.txt" })
    if (-not $global:SloppyReleaseTestState.missing) {
        $assets += @{ name = "Sloppy-windows-x86_64.zip"; browser_download_url = "https://fixture.invalid/Sloppy-windows-x86_64.zip" }
    }
    return @{ tag_name = "v9.9.9"; assets = $assets }
}
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing)
    $global:SloppyReleaseTestState.downloads++
    Copy-Item -LiteralPath (Join-Path $global:SloppyReleaseTestState.root ([Uri]$Uri).Segments[-1]) -Destination $OutFile
}
function Start-Process {
    param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru, [switch]$NoNewWindow)
    Assert-ReleaseInstall ($ArgumentList -eq "--version" -and $FilePath.EndsWith("sloppy.exe")) "Unexpected process launch."
    return [pscustomobject]@{ ExitCode = $global:SloppyReleaseTestState.probeExit }
}
function Get-Process {
    param($Name, $ErrorAction)
    if ($global:SloppyReleaseTestState.locked) {
        return [pscustomobject]@{ Path = (Join-Path $global:SloppyReleaseTestState.installRoot "bin/sloppy.exe") }
    }
}
function Move-Item {
    param($LiteralPath, $Destination)
    if ($global:SloppyReleaseTestState.failMove -and $LiteralPath.Contains("unpacked") -and (Split-Path -Leaf $LiteralPath) -eq "dashboard") {
        $global:SloppyReleaseTestState.failMove = $false
        throw "Simulated file replacement failure."
    }
    Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
}
function git.exe { throw "The release installer must not use Git." }
function swift.exe { throw "The release installer must not use Swift." }
function winget.exe { throw "The release installer must not install prerequisites." }
function powershell.exe { throw "The release installer must not run the source installer." }
function Assert-Rejected {
    $rejected = $false
    try { & $bootstrap -InstallRoot $installRoot -NoPath } catch { $rejected = $true }
    Assert-ReleaseInstall $rejected "Invalid installation was accepted."
    Assert-ReleaseInstall (Test-Path -LiteralPath (Join-Path $installRoot "bin/keep.txt")) "Previous binary installation was lost."
    Assert-ReleaseInstall (Test-Path -LiteralPath (Join-Path $installRoot "dashboard/keep.txt")) "Previous Dashboard installation was lost."
}

try {
    & $bootstrap -InstallRoot $installRoot -DryRun
    Assert-ReleaseInstall (-not (Test-Path -LiteralPath $installRoot)) "Dry run created files."
    Assert-ReleaseInstall ($global:SloppyReleaseTestState.downloads -eq 0) "Dry run downloaded files."
    New-ReleaseFixture
    & $bootstrap -InstallRoot $installRoot -NoPath
    Set-Content -LiteralPath (Join-Path $installRoot "personal-config.json") -Value "preserve"
    & $bootstrap -InstallRoot $installRoot -NoPath
    Assert-ReleaseInstall ((Get-Content -LiteralPath (Join-Path $installRoot "personal-config.json")) -eq "preserve") "Repeat install changed user data."
    Assert-ReleaseInstall ($env:Path -eq $originalPath -and $env:CORE_DASHBOARD_PATH -eq $originalDashboard) "-NoPath changed the environment."
    Set-Content -LiteralPath (Join-Path $installRoot "bin/keep.txt") -Value "old binary"
    Set-Content -LiteralPath (Join-Path $installRoot "dashboard/keep.txt") -Value "old Dashboard"

    ('0' * 64 + "  Sloppy-windows-x86_64.zip") | Set-Content -LiteralPath (Join-Path $testRoot "SHA256SUMS.txt")
    Assert-Rejected
    New-ReleaseFixture -Incomplete
    Assert-Rejected
    New-ReleaseFixture
    $global:SloppyReleaseTestState.missing = $true
    Assert-Rejected
    $global:SloppyReleaseTestState.missing = $false
    $global:SloppyReleaseTestState.probeExit = 1
    Assert-Rejected
    $global:SloppyReleaseTestState.probeExit = 0
    $global:SloppyReleaseTestState.locked = $true
    Assert-Rejected
    $global:SloppyReleaseTestState.locked = $false
    $global:SloppyReleaseTestState.failMove = $true
    Assert-Rejected
    Write-Host "Windows binary installer: fresh/repeat install, checksum, incomplete/missing release, runtime failure, running process and rollback passed."
} finally {
    $env:OS = $originalOS
    Remove-Variable -Name SloppyReleaseTestState -Scope Global
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
