#!/usr/bin/env pwsh
<#
.SYNOPSIS
Compute the Windows build-domain fingerprints and export them as cache keys.

.DESCRIPTION
Computes nothing but the keys: no build step runs here. The workflow feeds the
values into `actions/cache/restore` and `actions/cache/save`, and
build-windows.ps1 computes the exact same values when it decides whether a domain
can be skipped -- so a key and its marker always agree.

Run it *after* the toolchains are on PATH: the Flutter SDK, the Rust toolchain
and the MSVC toolset are inputs of the domains they build, and computing the keys
before they exist produces values like `flutter=absent` that can never be hit
again.

.PARAMETER Profile
Build profile; part of every fingerprint.

.PARAMETER RustTarget
rustup target that the Rust domain builds for.

.EXAMPLE
pwsh scripts/ci/domain-fingerprints.ps1
# rust=9f2c...  dart=1ab4...  flutter=77de...  pack=c0a1...
#>
[CmdletBinding()]
param(
    [ValidateSet('release', 'debug')][string] $Profile = 'release',
    [string] $RustTarget = 'x86_64-pc-windows-msvc'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'lib/domains.ps1')
. (Join-Path $PSScriptRoot 'lib/domain-plan.ps1')

$plan = Get-OpenMuseDomainPlan -RepoRoot $RepoRoot -Profile $Profile -RustTarget $RustTarget

foreach ($domain in $plan.Keys) {
    $entry = $plan[$domain]
    $line = "$domain=$($entry.fingerprint)"
    Write-Output $line
    if ($env:GITHUB_OUTPUT) {
        Add-Content -Path $env:GITHUB_OUTPUT -Value $line
    }
}
