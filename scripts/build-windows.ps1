[CmdletBinding()]
param(
    [ValidateSet("debug", "release")]
    [string]$Configuration = "release",
    [int]$Jobs = 4
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $repoRoot
try {
    foreach ($command in @("swift", "node", "npm")) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "Missing $command. Install Swift for Windows (including its Visual Studio/Windows SDK prerequisites) and Node.js."
        }
    }
    Push-Location Dashboard
    try {
        npm ci
        if ($LASTEXITCODE -ne 0) { throw "Dashboard dependency installation failed." }
        npm run typecheck
        if ($LASTEXITCODE -ne 0) { throw "Dashboard typecheck failed." }
        npm run build
        if ($LASTEXITCODE -ne 0) { throw "Dashboard build failed." }
    } finally { Pop-Location }

    foreach ($product in @("sloppy", "SloppyNode")) {
        swift build --configuration $Configuration --jobs $Jobs --product $product
        if ($LASTEXITCODE -ne 0) { throw "Swift build failed for $product." }
    }
    $binPath = (& swift build --configuration $Configuration --show-bin-path | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not locate the build output." }
    Write-Host ""
    Write-Host "Server and dashboard: & '$binPath\sloppy.exe' run"
    Write-Host "Terminal UI:          & '$binPath\sloppy.exe'"
    Write-Host "Dashboard:            http://127.0.0.1:25102"
} finally { Pop-Location }
