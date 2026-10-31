#Requires -Version 5.1
# Exercise a uniquely named scheduled task with a local probe, leaving other servers untouched.
$ErrorActionPreference = "Stop"
# Interactive tasks need a logged-in desktop user; headless CI still runs the Swift/unit checks.
$interactiveUser = (Get-CimInstance Win32_ComputerSystem).UserName
if (-not $interactiveUser -or $interactiveUser -ne [Security.Principal.WindowsIdentity]::GetCurrent().Name) {
    Write-Host "Skipping live Windows service smoke test: the current account has no interactive desktop session."
    return
}
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot (".build/windows-service-test-" + [Guid]::NewGuid().ToString("N"))
$serviceRoot = Join-Path $testRoot "service's data & settings"
$taskName = "Sloppy.Service.Test." + [Guid]::NewGuid().ToString("N")
$manager = Join-Path $repoRoot "Sources/sloppy/Resources/Windows/service.ps1"
$probe = Join-Path $testRoot "service probe.exe"
$config = Join-Path $testRoot "server's settings & cash$.json"

function Assert-Service {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Service {
    param([string]$Action, [string[]]$Extra = @())
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $manager `
        -Command $Action -ServiceRoot $serviceRoot -TaskName $taskName @Extra
    if ($LASTEXITCODE -ne 0) {
        $actionExitCode = $LASTEXITCODE
        Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue | Format-List TaskName,LastTaskResult,LastRunTime
        $runnerLog = Join-Path $serviceRoot "logs/runner.log"
        if (Test-Path -LiteralPath $runnerLog) { Get-Content -LiteralPath $runnerLog -Tail 20 }
        throw "Service action '$Action' failed (exit $actionExitCode)."
    }
}

New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
try {
    Add-Type -OutputAssembly $probe -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
public class SloppyServiceProbe {
    public static void Main(string[] args) {
        Console.WriteLine("SLOPPY_SERVICE_STDOUT");
        Console.Error.WriteLine("SLOPPY_SERVICE_STDERR");
        File.WriteAllText(args[2] + ".args", String.Join("|", args));
        Thread.Sleep(Timeout.Infinite);
    }
}
'@
    Set-Content -LiteralPath $config -Value "service configuration fixture"
    Invoke-Service install @("-ExecutablePath", $probe, "-ConfigPath", $config)
    $task = Get-ScheduledTask -TaskName $taskName
    Assert-Service ($task.Principal.LogonType -eq "Interactive" -and $task.Principal.RunLevel -eq "Limited") "Task must run as the current user without elevation."
    Assert-Service ($task.Settings.ExecutionTimeLimit -eq "PT0S" -and $task.Settings.RestartCount -gt 0) "Task must allow continuous operation and restart on failure."
    Assert-Service (-not $task.Settings.DisallowStartIfOnBatteries -and -not $task.Settings.StopIfGoingOnBatteries) "Task must work on battery power."
    $stateFile = Join-Path $serviceRoot "process.json"
    $first = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    Invoke-Service start
    $second = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    Assert-Service ($first.pid -eq $second.pid) "Repeated start launched another server."
    Assert-Service ((Get-Content -LiteralPath ($config + ".args") -Raw) -eq "run|--config-path|$config") "Config path was not preserved through the scheduled task."
    Assert-Service ((Get-Content -LiteralPath (Join-Path $serviceRoot "logs/service.log") -Raw).Contains("SLOPPY_SERVICE_STDERR")) "Service stderr was not captured."
    Assert-Service ((Get-Content -LiteralPath (Join-Path $serviceRoot "logs/service.stdout.log") -Raw).Contains("SLOPPY_SERVICE_STDOUT")) "Service stdout was not captured."
    $logReader = Start-Process powershell.exe -WindowStyle Hidden -PassThru `
        -ArgumentList @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ('"' + $manager + '"'),
            "-Command", "logs", "-ServiceRoot", ('"' + $serviceRoot + '"'), "-Lines", "1") `
        -RedirectStandardOutput (Join-Path $testRoot "followed.log") -RedirectStandardError (Join-Path $testRoot "followed-errors.log")
    try {
        Start-Sleep -Seconds 2
        $followed = Get-Content -LiteralPath (Join-Path $testRoot "followed.log") -Raw
        Assert-Service ($followed.Contains("SLOPPY_SERVICE_STDOUT") -and $followed.Contains("SLOPPY_SERVICE_STDERR")) "Log following must include both stdout and stderr."
    } finally {
        if (-not $logReader.HasExited) { $logReader.Kill(); $logReader.WaitForExit() }
        $logReader.Dispose()
    }
    Invoke-Service status
    Invoke-Service restart
    $second = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    Assert-Service ($first.pid -ne $second.pid) "Restart did not replace the service process."
    # Kill only our probe; the scheduled runner must recover without another CLI command.
    Stop-Process -Id $second.pid -Force
    $recovered = $false
    $recoveryDeadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        Start-Sleep -Seconds 1
        if (Test-Path -LiteralPath $stateFile) {
            $recoveryState = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            if ($recoveryState.pid -ne $second.pid -and (Get-Process -Id $recoveryState.pid -ErrorAction SilentlyContinue)) {
                $recovered = $true
                break
            }
        }
    } while ([DateTime]::UtcNow -lt $recoveryDeadline)
    Assert-Service $recovered "The scheduled runner did not restart the crashed service."
    Invoke-Service stop
    Invoke-Service stop
    Assert-Service (-not (Test-Path -LiteralPath $stateFile)) "Stop left process state behind."
    Assert-Service ((Get-ScheduledTask -TaskName $taskName).State -eq "Ready") "Stop must preserve login autostart."
    # A recycled or forged PID must not cause an unrelated process to be stopped.
    @{ pid = $PID; executablePath = $probe
        startedAt = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString() } |
        ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
    Invoke-Service stop
    Invoke-Service start
    Invoke-Service uninstall
    Assert-Service (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) "Uninstall left the task registered."
    Assert-Service (-not (Test-Path -LiteralPath (Join-Path $serviceRoot "service.json"))) "Uninstall retained the service definition."
    Assert-Service (Test-Path -LiteralPath (Join-Path $serviceRoot "logs/service.log")) "Uninstall must preserve logs."
    Write-Host "Windows service lifecycle, crash recovery, config quoting, logs and stale PID checks passed."
} finally {
    Invoke-Service uninstall
    Write-Host "Windows service smoke files: $testRoot"
}
