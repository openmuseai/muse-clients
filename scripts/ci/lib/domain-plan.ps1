# The build domain plan for the Windows pipeline.
#
# One place defines what each domain contains, what it produces and whether it
# may be reused from cache, so `domain-fingerprints.ps1` (which exports the cache
# keys to the workflow) and `build-windows.ps1` (which decides whether to skip a
# step and writes the marker) can never disagree about a key.

Set-StrictMode -Version Latest

function Get-OpenMuseDomainPlan {
    <#
    .SYNOPSIS
    Domain -> { paths, fingerprint, outputs, cached } for the requested profile.

    .DESCRIPTION
    Domains mirror the reference windows pipeline:

      rust     `cargo test --workspace --locked`  (cacheable)
      dart     every Dart package plus the host  (never cached: tests must run)
      flutter  `flutter build windows --release` (cacheable)
      pack     zip + checksums + build-info      (never cached: it is the output)

    `pack` is deliberately *not* cached, so a cached artefact can never be
    published by accident; its fingerprint only documents which upstream state it
    was produced from.
    #>
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [string] $Profile = 'release',
        [string] $RustTarget = 'x86_64-pc-windows-msvc'
    )

    $app = 'app/openmuse_host'
    $dartPaths = @('app', 'packages', 'plugins', 'distribution', 'contracts', 'schemas')
    $rustPaths = @('Cargo.toml', 'Cargo.lock', 'crates')

    $rustToolchain = Get-OpenMuseToolchainIdentity
    $flutterToolchain = Get-OpenMuseToolchainIdentity -IncludeFlutter

    $plan = [ordered]@{}

    $plan['rust'] = @{
        description = 'Rust platform crates'
        paths       = $rustPaths
        fingerprint = Get-OpenMuseFingerprint -RepoRoot $RepoRoot -Paths $rustPaths `
            -Toolchain $rustToolchain -Parameters ([ordered]@{ rustTarget = $RustTarget; profile = $Profile })
        outputs     = @('target')
        cached      = $true
    }

    $plan['dart'] = @{
        description = 'Dart packages, plugins and host analysis/tests'
        paths       = $dartPaths
        fingerprint = Get-OpenMuseFingerprint -RepoRoot $RepoRoot -Paths $dartPaths `
            -Toolchain $flutterToolchain -Parameters ([ordered]@{ domain = 'dart'; profile = $Profile })
        outputs     = @()
        cached      = $false
    }

    $plan['flutter'] = @{
        description = 'Flutter Windows host build'
        paths       = $dartPaths
        fingerprint = Get-OpenMuseFingerprint -RepoRoot $RepoRoot -Paths $dartPaths `
            -Toolchain $flutterToolchain -Parameters ([ordered]@{ domain = 'flutter'; profile = $Profile })
        outputs     = @("$app/build/windows/x64/runner/Release/OpenMuse.exe")
        cached      = $true
    }

    $packPaths = @('scripts/package_windows.ps1', 'scripts/ci/build-windows.ps1', 'scripts/ci/lib')
    $plan['pack'] = @{
        description = 'Portable archive, checksums and build info'
        paths       = $packPaths
        fingerprint = Get-OpenMuseFingerprint -RepoRoot $RepoRoot -Paths $packPaths `
            -Toolchain @{ pack = 'powershell' } -Parameters ([ordered]@{
                rust = $plan['rust'].fingerprint
                dart = $plan['dart'].fingerprint
                flutter = $plan['flutter'].fingerprint
                profile = $Profile
            })
        outputs     = @('dist/OpenMuse-windows-x64.zip')
        cached      = $false
    }

    return $plan
}
