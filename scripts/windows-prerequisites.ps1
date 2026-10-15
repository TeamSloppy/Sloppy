# Shared by the Windows development installer. Requires Windows PowerShell 5.1 or newer.

function Update-SloppyEnvironment {
    param([switch]$PreferRegistered)
    # Keep process-only overrides (CI/toolchain settings), and add newly installed tools.
    $registered = @([Environment]::GetEnvironmentVariable("Path", "User"),
        [Environment]::GetEnvironmentVariable("Path", "Machine"))
    $paths = @($env:Path) + $registered
    if ($PreferRegistered) { $paths = $registered + @($env:Path) }
    $env:Path = (($paths -join ";") -split ";" | Where-Object { $_ } | Select-Object -Unique) -join ";"
    foreach ($name in @("SDKROOT", "SWIFTFLAGS")) {
        $value = [Environment]::GetEnvironmentVariable($name, "User")
        if (-not $value) { $value = [Environment]::GetEnvironmentVariable($name, "Machine") }
        if ($value -and ($PreferRegistered -or -not [Environment]::GetEnvironmentVariable($name, "Process"))) {
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

function Test-SloppyToolVersion {
    param([string]$Command, [version]$Minimum)
    if (-not (Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue)) { return $false }
    $output = & $Command --version 2>&1
    if ($LASTEXITCODE -ne 0) { return $false }
    $match = [regex]::Match(($output -join " "), '\d+\.\d+(?:\.\d+)?')
    return $match.Success -and ([version]$match.Value -ge $Minimum)
}

function Test-SloppyBuildTools {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio/Installer/vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) { return $false }
    $component = "Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { $component = "Microsoft.VisualStudio.Component.VC.Tools.ARM64" }
    $installation = & $vswhere -latest -products '*' -requires $component -property installationPath
    return $LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($installation -join ""))
}

function Test-SloppyWindowsSDK {
    $kits = Join-Path ${env:ProgramFiles(x86)} "Windows Kits/10/Include"
    $architecture = "x64"
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { $architecture = "arm64" }
    foreach ($version in @(Get-ChildItem -LiteralPath $kits -Directory -ErrorAction SilentlyContinue)) {
        $sqliteLibrary = Join-Path (Split-Path -Parent $kits) ("Lib/" + $version.Name + "/um/$architecture/winsqlite3.lib")
        if ((Test-Path -LiteralPath (Join-Path $version.FullName "um/Windows.h")) -and
            (Test-Path -LiteralPath (Join-Path $version.FullName "um/winsqlite/winsqlite3.h")) -and
            (Test-Path -LiteralPath (Join-Path $version.FullName "ucrt/stdio.h")) -and
            (Test-Path -LiteralPath $sqliteLibrary)) { return $true }
    }
    return $false
}

function Get-SloppyMissingPackages {
    if (-not (Test-SloppyToolVersion "git.exe" ([version]"2.0"))) { "Git.Git" }
    if (-not (Test-SloppyToolVersion "node.exe" ([version]"24.0")) -or
        -not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) { "OpenJS.NodeJS.LTS" }
    if (-not (Test-SloppyBuildTools) -or -not (Test-SloppyWindowsSDK)) { "Microsoft.VisualStudio.2022.BuildTools" }
    if (-not (Test-SloppyToolVersion "swift.exe" ([version]"6.3.1"))) { "Swift.Toolchain" }
}

function Install-SloppyWinGet {
    if (Get-Command winget.exe -ErrorAction SilentlyContinue) { return }
    Write-Host "Installing WinGet using Microsoft's PowerShell module..."
    # Official bootstrap: https://learn.microsoft.com/windows/package-manager/winget/
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -Scope CurrentUser -Force | Out-Null
    Install-Module -Name Microsoft.WinGet.Client -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
    Import-Module Microsoft.WinGet.Client
    Repair-WinGetPackageManager -Force -Latest | Out-Host
    Update-SloppyEnvironment -PreferRegistered
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "WinGet could not be installed. Install Microsoft App Installer and rerun setup."
    }
}

function Install-SloppyPackage {
    param([string]$Id)
    $arguments = @("install", "--id", $Id, "--exact", "--source", "winget", "--silent",
        "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity")
    if ($Id -eq "Swift.Toolchain") { $arguments += @("--version", "6.3.1") }
    if ($Id -eq "Microsoft.VisualStudio.2022.BuildTools") {
        # --force also runs the installer when Build Tools exists without the C++/SDK components.
        $arguments += @("--force", "--override", ("--wait --passive --norestart " +
            "--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 " +
            "--add Microsoft.VisualStudio.Component.Windows11SDK.22621"))
        if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { $arguments[-1] += " --add Microsoft.VisualStudio.Component.VC.Tools.ARM64" }
    }
    Write-Host "Installing $Id (Windows may request administrator permission)..."
    & winget.exe @arguments | Out-Host
    $code = $LASTEXITCODE
    if ($code -in @(1641, 3010, -1978334967)) {
        throw "$Id requires a Windows restart. Restart Windows, then run setup again."
    }
    if ($code -ne 0 -and $code -ne -1978335189) { throw "Installation of $Id failed (exit $code). Rerun setup after resolving the installer error." }
    Update-SloppyEnvironment -PreferRegistered
}

function Enable-SloppyDeveloperMode {
    $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
    if ((Get-ItemProperty -LiteralPath $key -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense -eq 1) { return }
    Write-Host "Enabling Windows Developer Mode for SwiftPM symbolic links (administrator permission required)..."
    $script = @'
$ErrorActionPreference = "Stop"
try {
    $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
    New-Item -Path $key -Force | Out-Null
    New-ItemProperty -LiteralPath $key -Name AllowDevelopmentWithoutDevLicense -PropertyType DWord -Value 1 -Force | Out-Null
} catch { exit 1 }
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    $process = Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -Wait -PassThru `
        -ArgumentList @("-NoProfile", "-EncodedCommand", $encoded)
    if ($process.ExitCode -ne 0) { throw "Developer Mode could not be enabled. Enable it in Windows Settings, then rerun setup." }
}

function Initialize-SloppyPrerequisites {
    param([switch]$SkipInstall, [switch]$DryRun)
    Update-SloppyEnvironment
    $missing = @(Get-SloppyMissingPackages)
    if ($DryRun) {
        if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { Write-Host "Would bootstrap WinGet." }
        foreach ($package in $missing) { Write-Host "Would install $package through WinGet." }
        Write-Host "Would ensure Windows Developer Mode is enabled for SwiftPM."
        return
    }
    if ($SkipInstall) {
        if ($missing.Count) { throw "Missing prerequisites: $($missing -join ', '). Run setup without -SkipPrerequisites to install them." }
        return
    }
    if ($missing.Count) {
        Install-SloppyWinGet
        foreach ($package in $missing) { Install-SloppyPackage $package }
        $remaining = @(Get-SloppyMissingPackages)
        if ($remaining.Count) { throw "Tools are still unavailable: $($remaining -join ', '). Open a new terminal and rerun setup; Windows may need a restart." }
    }
    Enable-SloppyDeveloperMode
}
