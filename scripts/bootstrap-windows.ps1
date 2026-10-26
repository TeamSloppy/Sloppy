#Requires -Version 5.1
<#
.SYNOPSIS
Install the prebuilt Sloppy CLI and Dashboard. No compiler or build tools required.
.EXAMPLE
irm https://sloppy.team/install.ps1 | iex
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = $(if ($env:SLOPPY_INSTALL_ROOT) { $env:SLOPPY_INSTALL_ROOT } else { Join-Path $env:LOCALAPPDATA "Sloppy" }),
    [string]$ReleaseTag = $env:SLOPPY_RELEASE_TAG,
    [switch]$FromSource,
    [switch]$NoPath,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$archiveName = "Sloppy-windows-x86_64.zip"
$binDir = Join-Path $InstallRoot "bin"
$dashboardDir = Join-Path $InstallRoot "dashboard"

if ($FromSource) {
    if ($DryRun) { Write-Host "Would build Sloppy from source and install missing development tools."; return }
    $sourceURL = "https://github.com/TeamSloppy/Sloppy/releases/latest/download/bootstrap-windows-source.ps1"
    if ($ReleaseTag) { $sourceURL = "https://github.com/TeamSloppy/Sloppy/releases/download/" + [Uri]::EscapeDataString($ReleaseTag) + "/bootstrap-windows-source.ps1" }
    $sourceInstaller = Invoke-RestMethod $sourceURL
    & ([scriptblock]::Create($sourceInstaller)) -InstallRoot $InstallRoot -NoPath:$NoPath
    return
}
if ($DryRun) {
    Write-Host "Would download $archiveName and verify its SHA-256 checksum."
    Write-Host "Would install the prebuilt CLI, runtime DLLs and Dashboard into $InstallRoot."
    if (-not $NoPath) { Write-Host "Would add $binDir to your user PATH." }
    return
}
if ($env:OS -ne "Windows_NT" -or -not [Environment]::Is64BitOperatingSystem) {
    throw "This installer requires 64-bit Windows. On macOS/Linux use https://sloppy.team/install.sh."
}
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$releaseAPI = "https://api.github.com/repos/TeamSloppy/Sloppy/releases/latest"
if ($ReleaseTag) { $releaseAPI = "https://api.github.com/repos/TeamSloppy/Sloppy/releases/tags/" + [Uri]::EscapeDataString($ReleaseTag) }
$release = Invoke-RestMethod -Uri $releaseAPI -Headers @{ "User-Agent" = "Sloppy-Installer" }
$archive = $release.assets | Where-Object { $_.name -eq $archiveName } | Select-Object -First 1
$checksums = $release.assets | Where-Object { $_.name -eq "SHA256SUMS.txt" } | Select-Object -First 1
if (-not $archive -or -not $checksums) {
    throw "Release $($release.tag_name) does not include the full Windows package yet. No build tools were installed. Try again after a Windows release is published, or explicitly use -FromSource."
}

$temporary = Join-Path ([IO.Path]::GetTempPath()) ("sloppy-release-" + [Guid]::NewGuid().ToString("N"))
$backup = Join-Path $InstallRoot (".install-backup-" + [Guid]::NewGuid().ToString("N"))
$previous = @()
$installed = @()
$committed = $false
$rolledBack = $false
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $zip = Join-Path $temporary $archiveName
    $sums = Join-Path $temporary "SHA256SUMS.txt"
    Write-Host "Downloading Sloppy $($release.tag_name) for Windows..."
    Invoke-WebRequest -UseBasicParsing -Uri $checksums.browser_download_url -OutFile $sums
    $entry = Get-Content -LiteralPath $sums | Where-Object { $_ -match ('^[a-fA-F0-9]{64}\s+\*?' + [regex]::Escape($archiveName) + '$') } | Select-Object -First 1
    if (-not $entry) { throw "SHA256SUMS.txt has no checksum for $archiveName." }
    $expected = ($entry -split '\s+')[0]
    Invoke-WebRequest -UseBasicParsing -Uri $archive.browser_download_url -OutFile $zip
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $expected) { throw "The download failed SHA-256 verification. Your installation was not changed." }
    $unpacked = Join-Path $temporary "unpacked"
    Expand-Archive -LiteralPath $zip -DestinationPath $unpacked
    foreach ($required in @("bin/sloppy.exe", "bin/SloppyNode.exe", "bin/swiftCore.dll", "bin/vcruntime140.dll", "dashboard/dist/index.html", "dashboard/config.json", "share/sloppy/licenses")) {
        if (-not (Test-Path -LiteralPath (Join-Path $unpacked $required))) { throw "The release archive is incomplete: missing $required." }
    }
    $probe = Start-Process -FilePath (Join-Path $unpacked "bin/sloppy.exe") -ArgumentList "--version" -Wait -PassThru -NoNewWindow
    if ($probe.ExitCode -ne 0) { throw "The packaged Sloppy runtime could not start. Your installation was not changed." }
    $executables = @((Join-Path $binDir "sloppy.exe"), (Join-Path $binDir "SloppyNode.exe"))
    if (Get-Process -Name sloppy, SloppyNode -ErrorAction SilentlyContinue | Where-Object { $_.Path -in $executables }) {
        throw "Close Sloppy and SloppyNode before updating, then rerun this command."
    }
    New-Item -ItemType Directory -Force -Path $InstallRoot, $backup | Out-Null
    foreach ($directory in @("bin", "dashboard", "share")) {
        $destination = Join-Path $InstallRoot $directory
        if (Test-Path -LiteralPath $destination) {
            Move-Item -LiteralPath $destination -Destination (Join-Path $backup $directory)
            $previous += $directory
        }
        Move-Item -LiteralPath (Join-Path $unpacked $directory) -Destination $destination
        $installed += $directory
    }
    $committed = $true
    if (-not $NoPath) {
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $entries = @($userPath -split ';' | Where-Object { $_ })
        if (-not ($entries | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -eq $binDir.TrimEnd('\') })) {
            [Environment]::SetEnvironmentVariable("Path", (($entries + $binDir) -join ';'), "User")
        }
        [Environment]::SetEnvironmentVariable("CORE_DASHBOARD_PATH", $dashboardDir, "User")
        $env:CORE_DASHBOARD_PATH = $dashboardDir
        if ($binDir -notin ($env:Path -split ';')) { $env:Path = "$binDir;$env:Path" }
    }
    Write-Host "Sloppy $($release.tag_name) installed. No build tools required."
    Write-Host "Run sloppy for the terminal UI, or sloppy run for the server and Dashboard."
    if ($NoPath) { Write-Host "Executable: $(Join-Path $binDir 'sloppy.exe')" }
} catch {
    if (-not $committed) {
        foreach ($directory in $installed) { Remove-Item -LiteralPath (Join-Path $InstallRoot $directory) -Recurse -Force }
        foreach ($directory in $previous) { Move-Item -LiteralPath (Join-Path $backup $directory) -Destination (Join-Path $InstallRoot $directory) }
        $rolledBack = $true
    }
    throw
} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force
    if (($committed -or $rolledBack) -and (Test-Path -LiteralPath $backup)) {
        Remove-Item -LiteralPath $backup -Recurse -Force
    } elseif (Test-Path -LiteralPath $backup) {
        Write-Warning "The previous installation is preserved at $backup."
    }
}
