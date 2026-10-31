[CmdletBinding()]
param(
    [ValidateSet("debug", "release")]
    [string]$Configuration = "release",
    [ValidateRange(1, 128)]
    [int]$Jobs = 4,
    [switch]$SkipDashboard,
    [switch]$SkipDependencyUpdate
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $repoRoot
try {
    $commands = @("swift")
    if (-not $SkipDashboard) { $commands += @("node", "npm.cmd") }
    foreach ($command in $commands) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "Missing $command. Run scripts/install.ps1 to install Windows prerequisites and Sloppy."
        }
    }
    if ($SkipDashboard) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "Dashboard/dist/index.html"))) {
            throw "Dashboard is not built. Rerun without -SkipDashboard."
        }
        Write-Host "Reusing Dashboard/dist (-SkipDashboard)."
    } else {
        Push-Location Dashboard
        try {
            npm.cmd ci
            if ($LASTEXITCODE -ne 0) { throw "Dashboard dependency installation failed." }
            npm.cmd run typecheck
            if ($LASTEXITCODE -ne 0) { throw "Dashboard typecheck failed." }
            npm.cmd run build
            if ($LASTEXITCODE -ne 0) { throw "Dashboard build failed." }
        } finally { Pop-Location }
    }

    $buildArguments = @("build", "--configuration", $Configuration, "--jobs", $Jobs)
    if ($SkipDependencyUpdate) { $buildArguments += "--skip-update" }
    foreach ($product in @("sloppy", "SloppyNode")) {
        & swift @buildArguments --product $product
        if ($LASTEXITCODE -ne 0) { throw "Swift build failed for $product." }
    }
    $binPath = (& swift build --configuration $Configuration --show-bin-path | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not locate the build output." }
    Write-Host ""
    Write-Host "Server and dashboard: & '$binPath\sloppy.exe' run"
    Write-Host "Terminal UI:          & '$binPath\sloppy.exe'"
    Write-Host "Dashboard:            http://127.0.0.1:25102"
} finally { Pop-Location }
