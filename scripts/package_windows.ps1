#!/usr/bin/env pwsh
<#
.SYNOPSIS
Package the OpenMuse Windows build.

.DESCRIPTION
Kept as the documented Windows entry point (the README and older tooling call
it). All build logic lives in scripts/ci/build-windows.ps1, which is also what
.github/workflows/windows-build.yml runs, so a local package and a CI package are
produced by exactly the same steps.

.PARAMETER Profile
release (default) or debug.

.PARAMETER DomainCacheDir
Reuse a previously built rust/flutter domain when its fingerprint still matches.

.PARAMETER ForceRebuild
Ignore every domain cache.

.PARAMETER SkipTests
Skip the Dart and Rust test suites (cargo build instead of cargo test).

.EXAMPLE
pwsh scripts/package_windows.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('release', 'debug')][string] $Profile = 'release',
    [string] $DomainCacheDir = '',
    [switch] $ForceRebuild,
    [switch] $SkipTests,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$arguments = @{
    Profile    = $Profile
    SkipTests  = $SkipTests
    DryRun     = $DryRun
}
if ($DomainCacheDir) { $arguments.DomainCacheDir = $DomainCacheDir }
if ($ForceRebuild) { $arguments.ForceRebuild = $true }

& (Join-Path $PSScriptRoot 'ci/build-windows.ps1') @arguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
