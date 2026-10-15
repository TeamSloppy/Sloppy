#Requires -Version 5.1
<#
.SYNOPSIS
Install Sloppy, Dashboard, and all Windows build prerequisites from this checkout.
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = $(if ($env:SLOPPY_INSTALL_ROOT) { $env:SLOPPY_INSTALL_ROOT } else { Join-Path $env:LOCALAPPDATA "Sloppy" }),
    [ValidateSet("debug", "release")]
    [string]$Configuration = "release",
    [ValidateRange(1, 128)]
    [int]$Jobs = 4,
    [switch]$SkipPrerequisites,
    [switch]$SkipBuild,
    [switch]$NoPath,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
& "$PSScriptRoot/dev.ps1" setup @PSBoundParameters
