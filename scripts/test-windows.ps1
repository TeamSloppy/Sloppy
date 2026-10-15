[CmdletBinding()]
param(
    [ValidateSet("debug", "release")]
    [string]$Configuration = "release",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $repoRoot
try {
    if (-not $SkipBuild) { & "$PSScriptRoot/build-windows.ps1" -Configuration $Configuration }
    $binPath = (& swift build --configuration $Configuration --show-bin-path | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not locate the build output." }
    $executable = Join-Path $binPath "sloppy.exe"
    if (-not (Test-Path -LiteralPath $executable)) { throw "Build sloppy before running the smoke test." }
    $testRoot = Join-Path $repoRoot (".build/windows-smoke-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    $configPath = Join-Path $testRoot "sloppy settings.json"
    @{
        listen = @{ host = "127.0.0.1"; port = $port }
        workspace = @{ basePath = $testRoot; name = "workspace with spaces" }
        auth = @{ token = "" }
        models = @()
        memory = @{ backend = "sqlite-local-vectors" }
        nodes = @("local")
        gateways = @()
        plugins = @()
        sqlitePath = "core.sqlite"
        ui = @{ dashboardTerminal = @{ enabled = $true; localOnly = $true } }
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding utf8

    # The dashboard port is fixed. Never test against or stop somebody else's server.
    $dashboardProbe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 25102)
    try { $dashboardProbe.Start() } finally { $dashboardProbe.Stop() }
    $server = Start-Process -FilePath $executable -ArgumentList @("run", "--config-path", ('"' + $configPath + '"')) `
        -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $testRoot "server.stdout.log") `
        -RedirectStandardError (Join-Path $testRoot "server.stderr.log")
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(60)
        do {
            if ($server.HasExited) { throw "Server exited; inspect $testRoot/server.stderr.log" }
            try { $health = Invoke-WebRequest "http://127.0.0.1:$port/health" -UseBasicParsing -TimeoutSec 2; break } catch {
                if ([DateTime]::UtcNow -ge $deadline) { throw "Server readiness timed out; inspect $testRoot" }
                Start-Sleep -Milliseconds 200
            }
        } while ($true)
        if ($health.StatusCode -ne 200) { throw "Health endpoint failed." }
        1..5 | ForEach-Object { $null = Invoke-RestMethod "http://127.0.0.1:$port/health" -TimeoutSec 5 }
        $index = Invoke-WebRequest "http://127.0.0.1:25102/" -UseBasicParsing -TimeoutSec 5
        $runtime = Invoke-RestMethod "http://127.0.0.1:25102/config.json" -TimeoutSec 5
        if ($runtime.apiBase -ne "http://127.0.0.1:$port") { throw "Dashboard points to the wrong API." }
        $asset = [regex]::Match($index.Content, 'src="([^"]+\.js)"').Groups[1].Value
        if (-not $asset) { throw "Dashboard JavaScript bundle is missing." }
        $null = Invoke-WebRequest ("http://127.0.0.1:25102" + $asset) -UseBasicParsing -TimeoutSec 15
        Write-Host "Windows server and dashboard HTTP checks passed."
        node scripts/windows-terminal-smoke.mjs "http://127.0.0.1:$port"
        if ($LASTEXITCODE -ne 0) { throw "Dashboard terminal WebSocket check failed." }
    } finally {
        if (-not $server.HasExited) { & taskkill.exe /pid $server.Id /t /f | Out-Null }
    }

    $driver = Join-Path $testRoot "tui-smoke.exe"
    swiftc Sources/sloppy/Terminal/WindowsPseudoTerminal.swift scripts/windows-tui-smoke.swift -o $driver
    if ($LASTEXITCODE -ne 0) { throw "TUI smoke driver compilation failed." }
    & $driver $executable $configPath (Join-Path $testRoot "tui.log")
    if ($LASTEXITCODE -ne 0) { throw "TUI smoke test failed; inspect $testRoot/tui.log" }
    Write-Host "Smoke test logs: $testRoot"
} finally { Pop-Location }
