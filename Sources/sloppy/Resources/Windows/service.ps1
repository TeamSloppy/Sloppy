#Requires -Version 5.1
# Bundled with Sloppy; the installed copy runs independently of the source checkout.
[CmdletBinding()]
param(
    [ValidateSet("install", "uninstall", "start", "stop", "restart", "status", "logs", "run")]
    [string]$Command = "status",
    [string]$ExecutablePath,
    [string]$ConfigPath,
    [string]$ServiceRoot = (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".sloppy/service"),
    [string]$TaskName = ("Sloppy.Server." + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value),
    [ValidateRange(1, 100000)]
    [int]$Lines = 50
)

$ErrorActionPreference = "Stop"
$ServiceRoot = [IO.Path]::GetFullPath($ServiceRoot)
$settingsFile = Join-Path $ServiceRoot "service.json"
$processFile = Join-Path $ServiceRoot "process.json"
$runnerFile = Join-Path $ServiceRoot "service.ps1"
$logDir = Join-Path $ServiceRoot "logs"
$stdoutLog = Join-Path $logDir "service.stdout.log"
$stderrLog = Join-Path $logDir "service.log"
$powershellPath = Join-Path $env:SystemRoot "System32/WindowsPowerShell/v1.0/powershell.exe"

function Get-SloppyServiceTask {
    Get-ScheduledTask -TaskName $TaskName -TaskPath "\" -ErrorAction SilentlyContinue
}

function Get-SloppyServiceProcess {
    if (-not (Test-Path -LiteralPath $processFile)) { return $null }
    try {
        $state = Get-Content -LiteralPath $processFile -Raw | ConvertFrom-Json
        $server = Get-Process -Id $state.pid -ErrorAction Stop
        if ($server.Path -eq $state.executablePath -and
            $server.StartTime.ToUniversalTime().Ticks.ToString() -eq $state.startedAt) { return $server }
    } catch { }
    return $null
}

function Stop-SloppyService {
    $task = Get-SloppyServiceTask
    $server = Get-SloppyServiceProcess
    if ($task) { Stop-ScheduledTask -TaskName $TaskName -TaskPath "\" }
    if ($server -and -not $server.HasExited) {
        & taskkill.exe /pid $server.Id /t /f | Out-Null
        if ($LASTEXITCODE -ne 0 -and -not $server.HasExited) { throw "Could not stop Sloppy (PID $($server.Id))." }
        if (-not $server.WaitForExit(10000)) { throw "Timed out stopping Sloppy." }
    }
    # Wait for the runner to exit before permitting another instance to start.
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        $task = Get-SloppyServiceTask
        if (-not $task -or $task.State -notin @("Running", "Queued")) { break }
        Start-Sleep -Milliseconds 250
    }
    if ($task -and $task.State -in @("Running", "Queued")) { throw "Timed out stopping the Sloppy scheduled task." }
    if (Test-Path -LiteralPath $processFile) { Remove-Item -LiteralPath $processFile -Force }
    Write-Host "Sloppy service stopped."
}

function Start-SloppyService {
    if (-not (Get-SloppyServiceTask) -or -not (Test-Path -LiteralPath $settingsFile)) {
        throw "Service is not installed. Run: sloppy service install"
    }
    if (Get-SloppyServiceProcess) { Write-Host "Sloppy service is already running."; return }
    Start-ScheduledTask -TaskName $TaskName -TaskPath "\"
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        Start-Sleep -Milliseconds 250
        $server = Get-SloppyServiceProcess
        if ($server) {
            Start-Sleep -Milliseconds 500
            if (-not $server.HasExited) { Write-Host "Sloppy service started (PID $($server.Id))."; return }
        }
        # A stopped task can become ready before its engine accepts the next start.
        # IgnoreNew prevents duplicates when a previous request is still being processed.
        if ($attempt % 8 -eq 7 -and (Get-SloppyServiceTask).State -eq "Ready") {
            Start-ScheduledTask -TaskName $TaskName -TaskPath "\"
        }
    }
    throw "Sloppy failed to start. Check: sloppy service status; sloppy service logs"
}

function Install-SloppyService {
    $resolvedExecutable = (Resolve-Path -LiteralPath $ExecutablePath).Path
    $resolvedConfig = $null
    if ($ConfigPath) { $resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path }
    $workingDirectory = (Get-Location).Path
    $dashboardPath = $env:CORE_DASHBOARD_PATH
    if (-not $dashboardPath) {
        $candidate = Join-Path (Split-Path -Parent (Split-Path -Parent $resolvedExecutable)) "dashboard"
        if (Test-Path -LiteralPath (Join-Path $candidate "dist/index.html")) { $dashboardPath = $candidate }
    }
    # Validate all paths before replacing an existing service.
    if (Get-SloppyServiceTask) { Stop-SloppyService }
    New-Item -ItemType Directory -Force -Path $ServiceRoot, $logDir | Out-Null
    if ($PSCommandPath -ne $runnerFile) { Copy-Item -LiteralPath $PSCommandPath -Destination $runnerFile -Force }
    @{
        executablePath = $resolvedExecutable; configPath = $resolvedConfig
        workingDirectory = $workingDirectory; dashboardPath = $dashboardPath; path = $env:Path
    } | ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding UTF8
    $escapedRunner = $runnerFile.Replace("'", "''")
    $escapedRoot = $ServiceRoot.Replace("'", "''")
    $escapedTask = $TaskName.Replace("'", "''")
    $invocation = "& '$escapedRunner' -Command run -ServiceRoot '$escapedRoot' -TaskName '$escapedTask'; exit `$LASTEXITCODE"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($invocation))
    $action = New-ScheduledTaskAction -Execute $powershellPath `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded" `
        -WorkingDirectory $workingDirectory
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity
    $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
        -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $TaskName -TaskPath "\" -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Description "Sloppy background server (current user)." -Force | Out-Null
    Start-SloppyService
    Write-Host "Sloppy service installed. Starts at Windows login and restarts after failures."
    Write-Host "Task: $TaskName"
    Write-Host "Logs: $logDir"
}

function Invoke-SloppyServiceRunner {
    $settings = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json
    $arguments = @("run")
    if ($settings.configPath) { $arguments += @("--config-path", ('"' + $settings.configPath + '"')) }
    if ($settings.dashboardPath) { $env:CORE_DASHBOARD_PATH = $settings.dashboardPath }
    $env:Path = (@($settings.path, [Environment]::GetEnvironmentVariable("Path", "User"),
        [Environment]::GetEnvironmentVariable("Path", "Machine")) -join ";")
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    while ($true) {
        $server = Start-Process -FilePath $settings.executablePath -ArgumentList $arguments `
            -WorkingDirectory $settings.workingDirectory -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
        # Keep the native handle open so Windows PowerShell retains the child's exit code.
        $null = $server.Handle
        try {
            @{ pid = $server.Id; startedAt = $server.StartTime.ToUniversalTime().Ticks.ToString()
                executablePath = $settings.executablePath } | ConvertTo-Json |
                Set-Content -LiteralPath ($processFile + ".new") -Encoding UTF8
            Move-Item -LiteralPath ($processFile + ".new") -Destination $processFile -Force
            $server.WaitForExit()
            $exitCode = $server.ExitCode
            if ($null -eq $exitCode) { $exitCode = 1 }
        } catch {
            if (-not $server.HasExited) { $server.Kill() }
            throw
        } finally {
            if (Test-Path -LiteralPath $processFile) { Remove-Item -LiteralPath $processFile -Force }
            $server.Dispose()
        }
        if ($exitCode -eq 0) { exit 0 }
        # Supervise the child directly so recovery also works for manually started tasks.
        Start-Sleep -Seconds 5
    }
}

function Watch-SloppyServiceLogs {
    $logs = @($stderrLog, $stdoutLog, (Join-Path $logDir "runner.log")) | Where-Object { Test-Path -LiteralPath $_ }
    if (-not $logs) { throw "No service logs yet. Run: sloppy service start" }
    $readers = @()
    try {
        foreach ($log in $logs) {
            $stream = [IO.File]::Open($log, [IO.FileMode]::Open, [IO.FileAccess]::Read,
                ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            $stream.Seek(0, [IO.SeekOrigin]::End) | Out-Null
            $readers += [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
            Get-Content -LiteralPath $log -Tail $Lines
        }
        while ($true) {
            foreach ($reader in $readers) {
                if ($reader.BaseStream.Length -lt $reader.BaseStream.Position) {
                    $reader.DiscardBufferedData()
                    $reader.BaseStream.Seek(0, [IO.SeekOrigin]::Begin) | Out-Null
                }
                $text = $reader.ReadToEnd()
                if ($text) { [Console]::Write($text) }
            }
            Start-Sleep -Milliseconds 250
        }
    } finally {
        foreach ($reader in $readers) { $reader.Dispose() }
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    switch ($Command) {
        "install" { Install-SloppyService }
        "start" { Start-SloppyService }
        "stop" { Stop-SloppyService }
        "restart" { Stop-SloppyService; Start-SloppyService }
        "uninstall" {
            Stop-SloppyService
            if (Get-SloppyServiceTask) { Unregister-ScheduledTask -TaskName $TaskName -TaskPath "\" -Confirm:$false }
            foreach ($file in @($settingsFile, $runnerFile)) {
                if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
            }
            Write-Host "Sloppy service removed. Logs have been preserved at $logDir."
        }
        "status" {
            $task = Get-SloppyServiceTask
            $server = Get-SloppyServiceProcess
            Write-Host "Sloppy service (Windows Task Scheduler)"
            Write-Host "Task: $TaskName"
            Write-Host "Installed: $([bool]$task)"
            Write-Host "Running: $([bool]$server)"
            if ($task) {
                $info = Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath "\"
                Write-Host "State: $($task.State); last task result: $($info.LastTaskResult)"
            }
            if ($server) { Write-Host "PID: $($server.Id)" }
            Write-Host "Logs: $logDir"
        }
        "logs" { Watch-SloppyServiceLogs }
        "run" {
            try { Invoke-SloppyServiceRunner } catch {
                New-Item -ItemType Directory -Force -Path $logDir | Out-Null
                $_ | Out-String | Add-Content -LiteralPath (Join-Path $logDir "runner.log")
                exit 1
            }
        }
    }
}
