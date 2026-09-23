#!/usr/bin/env pwsh
<#
.SYNOPSIS
The one Windows entry point: build, test and package OpenMuse.

.DESCRIPTION
All Windows build logic lives here (and in scripts/ci/lib), so the GitHub
workflow, a developer machine and any other CI vendor run exactly the same steps.
The workflow only prepares toolchains, moves cache entries and uploads artefacts.

Domains and reuse:

  rust     cargo test --workspace --locked        cacheable
  dart     pub get + analyze (+ test) per package never cached
  flutter  flutter build windows --release        cacheable
  pack     zip + SHA256SUMS + build-info          never cached

With -DomainCacheDir a domain whose fingerprint still matches is skipped and
recorded as reused; -ForceRebuild ignores every cache. See
docs/windows-incremental-build.md.

.PARAMETER Profile
release (default) or debug.

.PARAMETER RustTargets
Comma separated rustup targets; the first is packaged.

.PARAMETER DomainCacheDir
Directory holding <domain>.json markers, normally restored from actions/cache.

.PARAMETER ForceRebuild
Ignore every domain cache and rebuild everything.

.PARAMETER DryRun
Print the plan and exit without touching anything.

.EXAMPLE
pwsh scripts/ci/build-windows.ps1 -DomainCacheDir .muse-domain-cache

.EXAMPLE
pwsh scripts/ci/build-windows.ps1 -SkipTests -SkipRust
#>
[CmdletBinding()]
param(
    [ValidateSet('release', 'debug')][string] $Profile = 'release',
    [string] $RustTargets = 'x86_64-pc-windows-msvc',
    [string] $DomainCacheDir = '',
    [switch] $ForceRebuild,
    [switch] $DryRun,
    [switch] $SkipPreflight,
    [switch] $SkipRust,
    [switch] $SkipDart,
    [switch] $SkipFlutterBuild,
    [switch] $SkipTests,
    [switch] $SkipZip,
    [switch] $SkipVerify
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'lib/domains.ps1')
. (Join-Path $PSScriptRoot 'lib/domain-plan.ps1')

$AppRoot = Join-Path $RepoRoot 'app/openmuse_host'
$DistRoot = Join-Path $RepoRoot 'dist'
$BundleRoot = Join-Path $AppRoot "build/windows/x64/runner/$(if ($Profile -eq 'release') { 'Release' } else { 'Debug' })"
$Archive = Join-Path $DistRoot 'OpenMuse-windows-x64.zip'
$Sums = Join-Path $DistRoot 'SHA256SUMS.txt'
$BuildInfo = Join-Path $DistRoot 'build-info.txt'

# Dart packages that must analyse and test cleanly. Kept explicit so a new
# directory is a conscious decision rather than something a glob silently picks
# up (or drops).
$DartPackages = @(
    'packages/openmuse_plugin_sdk',
    'packages/muse_resource_contract',
    'packages/muse_engine_adapter',
    'packages/muse_engine_tck',
    'packages/muse_resource_bridge',
    'packages/muse_surface_orchestrator',
    'packages/muse_helix_surface',
    'packages/muse_ioffice_adapter',
    'packages/muse_web_viewer_surface',
    'plugins/dsh-agent',
    'plugins/helix',
    'plugins/native-text-gate',
    'plugins/open-file-viewer',
    'distribution/openmuse_builtin_plugins'
)

$script:DomainStates = [ordered]@{}

function Write-Step {
    param([string] $Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Native {
    <#
    .SYNOPSIS
    Run a native command in a directory and fail loudly on a non-zero exit.
    #>
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Arguments,
        [Parameter(Mandatory)][string] $WorkingDirectory,
        [string] $What = ''
    )

    $label = if ($What) { $What } else { "$FilePath $($Arguments -join ' ')" }
    if ($DryRun) {
        Write-Host "    [dry-run] (cd $WorkingDirectory) $label" -ForegroundColor DarkGray
        return
    }

    Push-Location $WorkingDirectory
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$label failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

function Test-Reusable {
    param([string] $Domain)

    $entry = $script:Plan[$Domain]
    if ($ForceRebuild -or -not $entry.cached -or -not $DomainCacheDir) { return $false }
    $marker = Read-OpenMuseDomainMarker -DomainCacheDir $DomainCacheDir -Domain $Domain
    return (Test-OpenMuseDomainReusable -Marker $marker -Fingerprint $entry.fingerprint -Outputs $entry.outputs)
}

function Set-State {
    param([string] $Domain, [string] $State)
    $script:DomainStates[$Domain] = $State
    $fingerprint = $script:Plan[$Domain].fingerprint
    Write-Host "    $(Format-OpenMuseDomainState -Domain $Domain -State $State -Fingerprint $fingerprint)"
}

if (-not (Test-OpenMuseWindowsHost)) {
    throw 'build-windows.ps1 only builds the Windows target.'
}
if ($DomainCacheDir -and -not [System.IO.Path]::IsPathRooted($DomainCacheDir)) {
    $DomainCacheDir = Join-Path $RepoRoot $DomainCacheDir
}

$script:Plan = Get-OpenMuseDomainPlan -RepoRoot $RepoRoot -Profile $Profile -RustTarget $RustTargets.Split(',')[0].Trim()

Write-Host "OpenMuse Windows build" -ForegroundColor Green
Write-Host "  repository   $RepoRoot"
Write-Host "  profile      $Profile"
Write-Host "  commit       $(& git -C $RepoRoot rev-parse --short HEAD)"
Write-Host "  cache dir    $(if ($DomainCacheDir) { $DomainCacheDir } else { '(disabled)' })"
foreach ($domain in $script:Plan.Keys) {
    Write-Host ("  {0,-8} {1}  {2}" -f $domain, $script:Plan[$domain].fingerprint.Substring(0, 12), $script:Plan[$domain].description)
}

if ($DryRun) {
    Write-Host ''
    Write-Host 'dry run: nothing was changed.' -ForegroundColor Yellow
    exit 0
}

# --- preflight ---------------------------------------------------------------
if (-not $SkipPreflight) {
    Write-Step 'preflight'
    foreach ($command in @('git', 'cargo', 'rustc', 'flutter', 'dart')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "$command is not on PATH; run scripts/ci/bootstrap-windows.ps1 first."
        }
    }
    if (-not (Test-Path (Join-Path $AppRoot 'pubspec.yaml'))) {
        throw "missing app manifest: $AppRoot/pubspec.yaml"
    }
    Write-Host '    toolchain present'
}

# --- rust domain -------------------------------------------------------------
if (-not $SkipRust) {
    Write-Step 'domain rust'
    if (Test-Reusable -Domain 'rust') {
        Set-State -Domain 'rust' 'cache'
    } else {
        $arguments = if ($SkipTests) { @('build', '--workspace', '--locked') } else { @('test', '--workspace', '--locked') }
        Invoke-Native -FilePath 'cargo' -Arguments $arguments -WorkingDirectory $RepoRoot -What "cargo $($arguments -join ' ')"
        if ($DomainCacheDir) {
            Write-OpenMuseDomainMarker -DomainCacheDir $DomainCacheDir -Domain 'rust' `
                -Fingerprint $script:Plan['rust'].fingerprint -Toolchain (Get-OpenMuseToolchainIdentity)
        }
        Set-State -Domain 'rust' 'build'
    }
} else {
    Set-State -Domain 'rust' 'skipped'
}

# --- dart domain -------------------------------------------------------------
if (-not $SkipDart) {
    Write-Step 'domain dart'
    Set-State -Domain 'dart' 'build'

    foreach ($relative in $DartPackages) {
        $packageRoot = Join-Path $RepoRoot $relative
        if (-not (Test-Path (Join-Path $packageRoot 'pubspec.yaml'))) {
            Write-Host "    (skip ${relative}: no pubspec.yaml)" -ForegroundColor DarkGray
            continue
        }
        Write-Host "    $relative" -ForegroundColor White
        # --no-example keeps `pub get` from resolving a nested example project.
        Invoke-Native -FilePath 'flutter' -Arguments @('pub', 'get') -WorkingDirectory $packageRoot
        Invoke-Native -FilePath 'flutter' -Arguments @('analyze') -WorkingDirectory $packageRoot
        if (-not $SkipTests -and (Test-Path (Join-Path $packageRoot 'test'))) {
            Invoke-Native -FilePath 'flutter' -Arguments @('test') -WorkingDirectory $packageRoot
        }
    }

    Write-Host "    app/openmuse_host" -ForegroundColor White
    Invoke-Native -FilePath 'flutter' -Arguments @('pub', 'get') -WorkingDirectory $AppRoot
    Invoke-Native -FilePath 'flutter' -Arguments @('analyze') -WorkingDirectory $AppRoot
    if (-not $SkipTests) {
        Invoke-Native -FilePath 'flutter' -Arguments @('test') -WorkingDirectory $AppRoot
    }
} else {
    Set-State -Domain 'dart' 'skipped'
}

# --- flutter domain ----------------------------------------------------------
if (-not $SkipFlutterBuild) {
    Write-Step 'domain flutter'
    if (Test-Reusable -Domain 'flutter') {
        Set-State -Domain 'flutter' 'cache'
    } else {
        # pub get is idempotent and cheap; the build must never run against a
        # stale package config, which is exactly what a restored build dir can
        # hide.
        Invoke-Native -FilePath 'flutter' -Arguments @('pub', 'get') -WorkingDirectory $AppRoot
        Invoke-Native -FilePath 'flutter' -Arguments @('build', 'windows', "--$Profile") -WorkingDirectory $AppRoot
        if ($DomainCacheDir) {
            Write-OpenMuseDomainMarker -DomainCacheDir $DomainCacheDir -Domain 'flutter' `
                -Fingerprint $script:Plan['flutter'].fingerprint -Toolchain (Get-OpenMuseToolchainIdentity -IncludeFlutter)
        }
        Set-State -Domain 'flutter' 'build'
    }
} else {
    Set-State -Domain 'flutter' 'skipped'
}

# --- pack --------------------------------------------------------------------
if (-not $SkipZip) {
    Write-Step 'domain pack'
    Set-State -Domain 'pack' 'build'

    $executable = Join-Path $BundleRoot 'OpenMuse.exe'
    if (-not (Test-Path $executable)) {
        throw "missing Windows executable: $executable (run without -SkipFlutterBuild)"
    }

    New-Item -ItemType Directory -Force -Path $DistRoot | Out-Null
    if (Test-Path $Archive) { Remove-Item $Archive -Force }
    # ZipFile rather than Compress-Archive: it writes ZIP-spec forward slashes,
    # has no 2 GB ceiling and is markedly faster on a Flutter bundle.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $BundleRoot, $Archive, [System.IO.Compression.CompressionLevel]::Optimal, $false)

    $hash = (Get-FileHash -Algorithm SHA256 $Archive).Hash.ToLowerInvariant()
    "$hash  $(Split-Path -Leaf $Archive)" | Set-Content -Path $Sums -Encoding ascii

    $states = ($script:DomainStates.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ','
    Write-OpenMuseTextFile -Path $BuildInfo -Lines @(
        "product: OpenMuse"
        "profile: $Profile"
        "commit: $(& git -C $RepoRoot rev-parse HEAD)"
        "builtAt: $((Get-Date).ToUniversalTime().ToString('o'))"
        "flutter: $(Get-OpenMuseCommandVersion -Command 'flutter')"
        "rustc: $(Get-OpenMuseCommandVersion -Command 'rustc' -Arguments @('-V'))"
        "domains: $states"
        "archive: $(Split-Path -Leaf $Archive) sha256=$hash"
    )

    Write-Host "    $Archive"
    Write-Host "    $(Split-Path -Leaf $Sums) / $(Split-Path -Leaf $BuildInfo)"
} else {
    Set-State -Domain 'pack' 'skipped'
}

# --- verify ------------------------------------------------------------------
if (-not $SkipVerify) {
    Write-Step 'verify'
    if (-not (Test-Path $Archive)) {
        throw "no archive to verify; run without -SkipZip"
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
        foreach ($required in @('OpenMuse.exe', 'flutter_windows.dll', 'data/app.so')) {
            if ($names -notcontains $required) {
                throw "the archive is missing $required"
            }
        }
        Write-Host "    archive entries: $($names.Count); OpenMuse.exe, flutter_windows.dll and data/app.so present"
    } finally {
        $zip.Dispose()
    }

    $expected = ((Get-Content $Sums -First 1) -split '\s+')[0]
    $actual = (Get-FileHash -Algorithm SHA256 $Archive).Hash.ToLowerInvariant()
    if ($expected -ne $actual) { throw 'SHA256SUMS.txt does not match the archive' }
    Write-Host "    sha256 $actual"
}

Write-Host ''
Write-Host "build complete: $(Format-OpenMuseDomainState -Domain 'pack' -State 'ok' -Fingerprint $script:Plan['pack'].fingerprint)" -ForegroundColor Green
if ($env:GITHUB_STEP_SUMMARY) {
    $states = ($script:DomainStates.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ','
    @('## Windows build', '', "``domains: $states``", '') | Add-Content -Path $env:GITHUB_STEP_SUMMARY
}
