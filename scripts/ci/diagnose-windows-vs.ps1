#!/usr/bin/env pwsh
<#
.SYNOPSIS
Answer "why can't the Windows build see Visual Studio?" without a full build.

.DESCRIPTION
Prints what the machine actually has -- vswhere, the MSVC toolset, the Windows
SDK, the CMake and Ninja that Flutter would use, and `flutter doctor` -- and then,
with -CheckBuild, creates a scratch Flutter project and builds it. That
combination reproduces a toolchain failure in minutes and proves the fix without
waiting for the real package.

Nothing in the repository is modified: the scratch project is created under the
temporary directory and removed afterwards unless -KeepScratch is passed.

.EXAMPLE
pwsh scripts/ci/diagnose-windows-vs.ps1
pwsh scripts/ci/diagnose-windows-vs.ps1 -CheckBuild
#>
[CmdletBinding()]
param(
    [switch] $CheckBuild,
    [switch] $KeepScratch,
    [string] $FlutterHome = ''
)

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false

. (Join-Path $PSScriptRoot 'lib/domains.ps1')

function Write-Section {
    param([string] $Title)
    Write-Host ''
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

Write-Section 'operating system'
Write-Host "PSVersion      $($PSVersionTable.PSVersion)"
Write-Host "IsWindows      $(Test-OpenMuseWindowsHost)"

Write-Section 'flutter'
if ($FlutterHome) {
    $env:FLUTTER_ROOT = $FlutterHome
    $env:PATH = (Join-Path $FlutterHome 'bin') + [System.IO.Path]::PathSeparator + $env:PATH
    Write-Host "FLUTTER_ROOT  $FlutterHome"
}
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutter) {
    Write-Host "flutter        $($flutter.Source)"
    & flutter --version
    & flutter doctor -v
} else {
    Write-Warning 'flutter is not on PATH'
}

Write-Section 'visual studio'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
    Write-Host "vswhere        $vswhere"
    & $vswhere -latest -products * -format json
    Write-Host '--- instances with the C++ desktop workload ---'
    & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath -property installationVersion
} else {
    Write-Warning "vswhere not found at $vswhere"
}

$identity = Get-OpenMuseVisualStudioIdentity
Write-Host "install version $($identity.vs)"
Write-Host "MSVC toolset    $($identity.msvc)"
Write-Host "Windows SDK     $($identity.sdk)"

Write-Section 'cmake and ninja'
Write-Host "cmake          $(Get-OpenMuseCommandVersion -Command 'cmake')"
Write-Host "ninja          $(Get-OpenMuseCommandVersion -Command 'ninja')"

Write-Section 'rust'
Write-Host "rustc          $(Get-OpenMuseCommandVersion -Command 'rustc' -Arguments @('-V'))"
Write-Host "cargo          $(Get-OpenMuseCommandVersion -Command 'cargo' -Arguments @('-V'))"
& rustup target list --installed

if (-not $CheckBuild) {
    Write-Host ''
    Write-Host 'toolchain probe complete (-CheckBuild was not requested)' -ForegroundColor Green
    exit 0
}

Write-Section 'scratch Flutter Windows build'
if (-not $flutter) { throw 'cannot run -CheckBuild without flutter on PATH' }

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("openmuse-diagnose-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
$failed = $false
try {
    Push-Location $scratch
    & flutter create --platforms=windows --project-name openmuse_diagnose .
    if ($LASTEXITCODE -eq 0) { & flutter build windows --release } else { $failed = $true }
    if ($LASTEXITCODE -ne 0) { $failed = $true }
} finally {
    Pop-Location
    if (-not $KeepScratch) { Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue }
}

if ($failed) {
    Write-Host ''
    Write-Host 'scratch build FAILED: the Windows toolchain cannot build a Flutter desktop app here.' -ForegroundColor Red
    exit 1
}
Write-Host ''
Write-Host 'scratch build PASSED: the Flutter Windows toolchain works on this machine.' -ForegroundColor Green
