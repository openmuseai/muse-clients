#!/usr/bin/env pwsh
<#
.SYNOPSIS
Prepare a Windows machine (developer box or CI runner) for the OpenMuse build.

.DESCRIPTION
Everything the pipeline needs before a domain can be evaluated: the Rust target,
the Flutter Windows desktop artefacts and a UTF-8 console for the Python helpers.
It deliberately installs nothing that the workflow already installs through an
action (Rust itself, Flutter itself); it makes the *existing* toolchain usable and
reports what it found, so a failure here is a toolchain problem and not a build
problem.

Safe to run repeatedly.

.PARAMETER RustTargets
Comma separated rustup targets to add. The first one is what gets packaged
(`cargo build` still decides the real target from the workspace).

.PARAMETER ExpectedFlutterVersion
Fail when the installed Flutter does not match. Empty (the default) only warns.

.PARAMETER SkipRustTargets
Do not touch rustup (used by the diagnose workflow, which must not mutate state).

.PARAMETER SkipPrecache
Do not download the Flutter Windows desktop artefacts.

.EXAMPLE
pwsh scripts/ci/bootstrap-windows.ps1 -RustTargets x86_64-pc-windows-msvc
#>
[CmdletBinding()]
param(
    [string] $RustTargets = 'x86_64-pc-windows-msvc',
    [string] $ExpectedFlutterVersion = '',
    [switch] $SkipRustTargets,
    [switch] $SkipPrecache
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'lib/domains.ps1')

function Write-Step {
    param([string] $Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Assert-Command {
    param([string] $Name, [string] $Hint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is not on PATH. $Hint"
    }
}

if (-not (Test-OpenMuseWindowsHost)) {
    throw 'bootstrap-windows.ps1 only runs on Windows.'
}

# The runner's console code page is not UTF-8, so a helper that prints non-ASCII
# dies with UnicodeEncodeError before doing any work.
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

Write-Step 'checking the base toolchain'
Assert-Command -Name 'git' -Hint 'Install Git for Windows.'
Assert-Command -Name 'cargo' -Hint 'Install Rust (https://rustup.rs).'
Assert-Command -Name 'rustc' -Hint 'Install Rust (https://rustup.rs).'
Assert-Command -Name 'flutter' -Hint 'Install Flutter or run the workflow, which installs it.'
Assert-Command -Name 'dart' -Hint 'Install Flutter; dart ships with it.'

$targets = @($RustTargets -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if (-not $SkipRustTargets) {
    foreach ($target in $targets) {
        Write-Step "rustup target add $target"
        & rustup target add $target
        if ($LASTEXITCODE -ne 0) { throw "rustup target add $target failed ($LASTEXITCODE)" }
    }
}

Write-Step 'checking the Flutter Windows desktop toolchain'
$flutterVersion = (Get-OpenMuseCommandVersion -Command 'flutter')
if ($ExpectedFlutterVersion -and $flutterVersion -notmatch [regex]::Escape($ExpectedFlutterVersion)) {
    throw "Flutter $ExpectedFlutterVersion was requested but '$flutterVersion' is on PATH."
}
Write-Host "    $flutterVersion"

# `flutter config --enable-windows-desktop` is idempotent and makes the desktop
# target explicit rather than dependent on the machine's previous state.
& flutter config --enable-windows-desktop | Out-Null
if ($LASTEXITCODE -ne 0) { throw "flutter config failed ($LASTEXITCODE)" }

if (-not $SkipPrecache) {
    Write-Step 'flutter precache --windows'
    & flutter precache --windows
    if ($LASTEXITCODE -ne 0) { throw "flutter precache failed ($LASTEXITCODE)" }
}

$vs = Get-OpenMuseVisualStudioIdentity
Write-Step 'toolchain identity'
Write-Host "    rustc      $(Get-OpenMuseCommandVersion -Command 'rustc' -Arguments @('-V'))"
Write-Host "    visual std $($vs.vs)"
Write-Host "    msvc       $($vs.msvc)"
Write-Host "    windows sdk $($vs.sdk)"
Write-Host "    dart       $(Get-OpenMuseCommandVersion -Command 'dart')"

if ($vs.vs -eq 'absent' -or $vs.msvc -eq 'absent') {
    Write-Warning 'Visual Studio with the C++ desktop workload was not found; the Flutter Windows build will fail. Run scripts/ci/diagnose-windows-vs.ps1 to see what is installed.'
}

Write-Host ''
Write-Host 'bootstrap complete' -ForegroundColor Green
