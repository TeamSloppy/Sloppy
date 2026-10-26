#Requires -Version 5.1
<#
.SYNOPSIS
Install Sloppy on Windows without manually downloading a checkout or build tools.
.EXAMPLE
.\scripts\bootstrap-windows.ps1 -FromSource
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = $(if ($env:SLOPPY_INSTALL_ROOT) { $env:SLOPPY_INSTALL_ROOT } else { Join-Path $env:LOCALAPPDATA "Sloppy" }),
    [switch]$NoPath,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$sourceRoot = Join-Path $InstallRoot "source"
$repository = "https://github.com/TeamSloppy/Sloppy.git"

if ($DryRun) {
    Write-Host "Would install missing Git, Node.js, Swift and C++ build tools."
    Write-Host "Would clone or fast-forward $repository into $sourceRoot."
    Write-Host "Would build and install Sloppy and Dashboard into $InstallRoot."
    if (-not $NoPath) { Write-Host "Would add Sloppy to your user PATH." }
    return
}

if ($env:OS -ne "Windows_NT") { throw "On macOS or Linux, use: curl -fsSL https://sloppy.team/install.sh | bash" }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Write-Host "Installing Sloppy for Windows."
Write-Host "Windows currently builds from source. The first installation can take several minutes."
Write-Host "Missing build tools will be installed automatically; Windows may request administrator permission."

# Bootstrap prerequisites before Git is available. Keep the checkout for incremental
# updates and the background-server commands supplied by scripts/dev.ps1.
$prerequisites = Invoke-RestMethod "https://raw.githubusercontent.com/TeamSloppy/Sloppy/main/scripts/windows-prerequisites.ps1"
. ([scriptblock]::Create($prerequisites))
Initialize-SloppyPrerequisites

if (Test-Path -LiteralPath $sourceRoot) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot ".git"))) {
        throw "$sourceRoot already exists and is not a Git checkout. Move it aside or choose a different -InstallRoot."
    }
    $origin = & git.exe -C $sourceRoot remote get-url origin
    if ($LASTEXITCODE -ne 0 -or $origin -ne $repository) { throw "The existing source checkout has a different origin. Update it manually." }
    $branch = & git.exe -C $sourceRoot branch --show-current
    if ($LASTEXITCODE -ne 0 -or $branch -ne "main") { throw "The existing source checkout is not on main. Update it manually." }
    $changes = & git.exe -C $sourceRoot status --porcelain
    if ($LASTEXITCODE -ne 0 -or $changes) { throw "The source checkout contains local changes. Commit or move them before reinstalling." }
    & git.exe -C $sourceRoot fetch origin main
    if ($LASTEXITCODE -ne 0) { throw "Could not fetch Sloppy. Check your connection and try again." }
    & git.exe -C $sourceRoot merge --ff-only origin/main
    if ($LASTEXITCODE -ne 0) { throw "The source checkout cannot be fast-forwarded. Update it manually." }
} else {
    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
    $stagingRoot = Join-Path $InstallRoot ("source-download-" + [Guid]::NewGuid().ToString("N"))
    try {
        & git.exe clone --depth 1 --branch main $repository $stagingRoot
        if ($LASTEXITCODE -ne 0) { throw "Could not download Sloppy. Check your connection and try again." }
        Move-Item -LiteralPath $stagingRoot -Destination $sourceRoot
    } finally {
        if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
    }
}

$installer = Join-Path $sourceRoot "scripts/install.ps1"
if (-not (Test-Path -LiteralPath $installer)) { throw "The checkout is missing scripts/install.ps1." }
# Allow the downloaded setup scripts in this child process only. A fresh Windows
# PowerShell commonly has a Restricted execution policy; do not change user policy.
$setupArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $installer,
    "-InstallRoot", $InstallRoot, "-SkipPrerequisites")
if ($NoPath) { $setupArguments += "-NoPath" }
& powershell.exe @setupArguments
if ($LASTEXITCODE -ne 0) { throw "Sloppy setup failed. Resolve the error above and rerun the same install command." }
Write-Host "Open a new terminal and run sloppy. Run sloppy run for the server and web dashboard."
Write-Host "Background server: & '$sourceRoot/scripts/dev.ps1' start"
