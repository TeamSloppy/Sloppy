#Requires -Version 5.1
# Run after build-windows.ps1 on the Windows build host, never on the user's machine.
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) ".build/release-assets"))

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("sloppy-package-" + [Guid]::NewGuid().ToString("N"))
$stage = Join-Path $temporary "stage"
try {
    & "$PSScriptRoot/install.ps1" -InstallRoot $stage -SkipPrerequisites -SkipBuild -NoPath

    # App-local redistributables avoid requiring Visual Studio or a machine-wide
    # C++ runtime installation. Copy only Microsoft's redistributable CRT directory.
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio/Installer/vswhere.exe"
    $visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $visualStudio) { throw "Cannot locate the Visual C++ redistributable files." }
    $redistRoot = Join-Path $visualStudio "VC/Redist/MSVC"
    $version = Get-ChildItem -LiteralPath $redistRoot -Directory |
        Where-Object { $_.Name -match '^\d+(\.\d+){1,3}$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $version) { throw "Cannot locate a versioned Visual C++ redistributable directory." }
    $crt = Get-ChildItem -LiteralPath (Join-Path $version.FullName "x64") -Directory -Filter "Microsoft.VC*.CRT" | Select-Object -First 1
    if (-not $crt) { throw "Cannot locate the x64 redistributable CRT." }
    Get-ChildItem -LiteralPath $crt.FullName -File -Filter "*.dll" |
        Copy-Item -Destination (Join-Path $stage "bin") -Force
    foreach ($required in @("swiftCore.dll", "vcruntime140.dll", "vcruntime140_1.dll")) {
        if (-not (Test-Path -LiteralPath (Join-Path $stage "bin/$required"))) { throw "Missing runtime DLL: $required" }
    }

    $licenseRoot = Join-Path $stage "share/sloppy/licenses"
    New-Item -ItemType Directory -Force -Path $licenseRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSE") -Destination (Join-Path $licenseRoot "AGPL-3.0.txt")
    Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSES/MIT.txt") -Destination (Join-Path $licenseRoot "MIT.txt")
    Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSES/README.md") -Destination (Join-Path $licenseRoot "LICENSE-MAP.md")
    foreach ($notice in @("SOURCE_OFFER.md", "THIRD_PARTY_NOTICES.md")) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $notice) -Destination $licenseRoot
    }
    Get-ChildItem -LiteralPath (Join-Path $repoRoot ".build/checkouts") -Directory | ForEach-Object {
        $destination = Join-Path $licenseRoot ("third-party/" + $_.Name)
        Get-ChildItem -LiteralPath $_.FullName -Recurse -File |
            Where-Object { $_.Name -match '^(LICENSE|COPYING|NOTICE)(\..*)?$' } |
            ForEach-Object {
                New-Item -ItemType Directory -Force -Path $destination | Out-Null
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destination $_.Name) -Force
            }
    }
    @'
Swift runtime: Apache License 2.0 with Runtime Library Exception.
https://github.com/swiftlang/swift/blob/main/LICENSE.txt
Microsoft Visual C++ runtime: Microsoft Software License Terms.
https://visualstudio.microsoft.com/license-terms/
https://learn.microsoft.com/cpp/windows/redistributing-visual-cpp-files
'@ | Set-Content -LiteralPath (Join-Path $licenseRoot "RUNTIME-NOTICES.txt") -Encoding UTF8

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $archive = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) "Sloppy-windows-x86_64.zip"
    Compress-Archive -LiteralPath (Join-Path $stage "bin"), (Join-Path $stage "dashboard"), (Join-Path $stage "share") -DestinationPath $archive -Force
    Write-Host "Packaged $archive"
    if ($env:GITHUB_OUTPUT) { "core_zip_path=$archive" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append }
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
