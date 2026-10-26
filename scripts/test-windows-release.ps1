#Requires -Version 5.1
# Exercise the actual packaged PE binaries, with no development tools on PATH.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ArchivePath)

$ErrorActionPreference = "Stop"
$archive = (Resolve-Path -LiteralPath $ArchivePath).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("sloppy-portable-smoke-" + [Guid]::NewGuid().ToString("N"))
$installRoot = Join-Path $testRoot "installed Sloppy"
$global:SloppyPortableSmoke = @{ archive = $archive; root = $testRoot }
$previousPath = $env:Path
$previousDashboard = $env:CORE_DASHBOARD_PATH
$server = $null

# Use the real installer and archive without depending on an already published release.
function Invoke-RestMethod {
    param($Uri, $Headers)
    return @{ tag_name = "fixture"; assets = @(
        @{ name = "SHA256SUMS.txt"; browser_download_url = "https://fixture.invalid/SHA256SUMS.txt" },
        @{ name = "Sloppy-windows-x86_64.zip"; browser_download_url = "https://fixture.invalid/Sloppy-windows-x86_64.zip" }
    ) }
}
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing)
    if ($Uri.EndsWith("SHA256SUMS.txt")) {
        ((Get-FileHash -LiteralPath $global:SloppyPortableSmoke.archive -Algorithm SHA256).Hash + "  Sloppy-windows-x86_64.zip") |
            Set-Content -LiteralPath $OutFile
    } else { Copy-Item -LiteralPath $global:SloppyPortableSmoke.archive -Destination $OutFile }
}

try {
    $env:Path = Join-Path $env:SystemRoot "System32"
    foreach ($tool in @("swift.exe", "git.exe", "node.exe", "cl.exe")) {
        if (Get-Command $tool -ErrorAction SilentlyContinue) { throw "Development tool leaked into the portable smoke PATH: $tool" }
    }
    & "$PSScriptRoot/bootstrap-windows.ps1" -InstallRoot $installRoot -NoPath -ReleaseTag fixture
    $executable = Join-Path $installRoot "bin/sloppy.exe"
    & $executable --version
    if ($LASTEXITCODE -ne 0) { throw "Packaged Sloppy could not run without the toolchain PATH." }

    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $probe.Start()
    $port = $probe.LocalEndpoint.Port
    $probe.Stop()
    $config = Join-Path $testRoot "server.json"
    @{
        listen = @{ host = "127.0.0.1"; port = $port }
        workspace = @{ basePath = $testRoot; name = "workspace" }
        auth = @{ token = "" }; models = @(); plugins = @(); gateways = @(); nodes = @("local")
        memory = @{ backend = "sqlite-local-vectors" }; sqlitePath = "core.sqlite"
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $config -Encoding UTF8
    $env:CORE_DASHBOARD_PATH = Join-Path $installRoot "dashboard"
    $server = Start-Process -FilePath $executable -ArgumentList @("run", "--config-path", ('"' + $config + '"')) `
        -WorkingDirectory $installRoot -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $testRoot "stdout.log") -RedirectStandardError (Join-Path $testRoot "stderr.log")
    $healthy = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if ($server.HasExited) { throw "Packaged server exited during startup." }
        try {
            $response = Microsoft.PowerShell.Utility\Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/health" -TimeoutSec 2
            if ($response.StatusCode -eq 200) { $healthy = $true; break }
        } catch { Start-Sleep -Milliseconds 250 }
    }
    if (-not $healthy) { throw "Packaged server did not become healthy." }
    $dashboard = Microsoft.PowerShell.Utility\Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:25102/" -TimeoutSec 10
    if ($dashboard.StatusCode -ne 200 -or $dashboard.Content -notmatch '<html') { throw "Packaged Dashboard did not load." }
    Write-Host "Portable Windows CLI, DLL loading, SQLite, health and Dashboard passed without development tools on PATH."
} catch {
    $log = Join-Path $testRoot "stderr.log"
    if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 80 | Write-Host }
    throw
} finally {
    if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force; $server.WaitForExit() }
    $env:Path = $previousPath
    $env:CORE_DASHBOARD_PATH = $previousDashboard
    Remove-Variable -Name SloppyPortableSmoke -Scope Global
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
