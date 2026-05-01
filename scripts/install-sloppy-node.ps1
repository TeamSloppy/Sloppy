param(
    [string]$ReleaseTag = $env:SLOPPY_RELEASE_TAG,
    [string]$ReleaseRepo = $(if ($env:SLOPPY_RELEASE_REPO) { $env:SLOPPY_RELEASE_REPO } else { "TeamSloppy/Sloppy" }),
    [string]$InstallRoot = $(if ($env:SLOPPY_NODE_INSTALL_ROOT) { $env:SLOPPY_NODE_INSTALL_ROOT } else { Join-Path $env:LOCALAPPDATA "SloppyNode" }),
    [string]$BinDir = $(if ($env:SLOPPY_BIN_DIR) { $env:SLOPPY_BIN_DIR } else { Join-Path $env:LOCALAPPDATA "Sloppy\bin" }),
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not $ReleaseTag) {
    $latest = Invoke-RestMethod -Headers @{ "User-Agent" = "install-sloppy-node.ps1" } -Uri "https://api.github.com/repos/$ReleaseRepo/releases/latest"
    $ReleaseTag = $latest.tag_name
}

$asset = "SloppyNode-windows-x86_64.zip"
$baseUrl = "https://github.com/$ReleaseRepo/releases/download/$ReleaseTag"
$sumsUrl = "$baseUrl/SHA256SUMS.txt"
$assetUrl = "$baseUrl/$asset"

Write-Host "Installing sloppy-node from $ReleaseRepo @ $ReleaseTag ($asset)"
if ($DryRun) {
    Write-Host "Would download $sumsUrl"
    Write-Host "Would download $assetUrl"
    Write-Host "Would extract into $InstallRoot and copy to $BinDir\sloppy-node.exe"
    exit 0
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $sumsPath = Join-Path $tmp "SHA256SUMS.txt"
    $assetPath = Join-Path $tmp $asset
    Invoke-WebRequest -Headers @{ "User-Agent" = "install-sloppy-node.ps1" } -Uri $sumsUrl -OutFile $sumsPath
    Invoke-WebRequest -Headers @{ "User-Agent" = "install-sloppy-node.ps1" } -Uri $assetUrl -OutFile $assetPath

    $expected = (Get-Content $sumsPath | Where-Object { $_ -match "\s$([regex]::Escape($asset))$" } | Select-Object -First 1).Split(" ")[0]
    if (-not $expected) { throw "Checksum file did not include $asset." }
    $actual = (Get-FileHash -Algorithm SHA256 $assetPath).Hash.ToLowerInvariant()
    if ($expected.ToLowerInvariant() -ne $actual) { throw "SHA256 mismatch for $asset." }

    New-Item -ItemType Directory -Force -Path $InstallRoot, $BinDir | Out-Null
    Expand-Archive -Force -Path $assetPath -DestinationPath $InstallRoot
    Copy-Item -Force (Join-Path $InstallRoot "bin\sloppy-node.exe") (Join-Path $BinDir "sloppy-node.exe")
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host "Install complete."
Write-Host "  Binary: $BinDir\sloppy-node.exe"
Write-Host "  Verify: '{""action"":""status"",""payload"":{}}' | sloppy-node invoke --stdin"
