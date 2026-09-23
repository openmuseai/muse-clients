# Shared helpers for the Windows build: repository identity, toolchain identity,
# per-domain fingerprints and the on-disk markers that let build-windows.ps1 skip
# a domain whose inputs did not change.
#
# Design rule (same as the reference implementation): a fingerprint covers every
# input that can change a domain's output -- committed content, the toolchain and
# the parameters -- and a domain is only reused when the marker matches *and* its
# outputs are still present. Anything less produces a package that looks fresh
# but is not.

Set-StrictMode -Version Latest

function Test-OpenMuseWindowsHost {
    <#
    .SYNOPSIS
    True on Windows, in both Windows PowerShell 5.1 and PowerShell 7+.

    .DESCRIPTION
    `$IsWindows` only exists in PowerShell 6+, so scripts that may also be run
    with the 5.1 that ships with Windows cannot use it directly under
    Set-StrictMode.
    #>
    if (Test-Path variable:IsWindows) { return [bool] $IsWindows }
    return ($env:OS -eq 'Windows_NT')
}

function Write-OpenMuseTextFile {
    <#
    .SYNOPSIS
    Write UTF-8 text without a byte-order mark.

    .DESCRIPTION
    `Set-Content -Encoding utf8` adds a BOM in Windows PowerShell 5.1, which
    would put three stray bytes at the top of build-info.txt. The build scripts
    are run by both shells.
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Lines
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, [string[]] $Lines, $utf8)
}

function Get-OpenMuseSha256Hex {
    <#
    .SYNOPSIS
    SHA-256 of a UTF-8 string, as lowercase hex.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-OpenMuseTreeDigest {
    <#
    .SYNOPSIS
    Digest of the committed content under a set of paths.

    .DESCRIPTION
    Uses git objects rather than the working tree, so it is fast, stable across
    line-ending settings and unaffected by untracked build output. Deleted paths
    and paths that never existed contribute nothing rather than throwing, which
    keeps a fingerprint computable before a domain has produced its outputs.
    #>
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Paths,
        [string] $Commit = 'HEAD'
    )

    $paths = @($Paths | Sort-Object -Unique)
    if ($paths.Count -eq 0) { return Get-OpenMuseSha256Hex '' }

    $lines = @(& git -C $RepoRoot ls-tree -r $Commit -- @paths 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-tree failed for: $($paths -join ', ')"
    }
    return Get-OpenMuseSha256Hex (($lines | Sort-Object) -join "`n")
}

function Get-OpenMuseCommandVersion {
    <#
    .SYNOPSIS
    First line of a command's version output, or 'absent' when it is not usable.

    .DESCRIPTION
    `dart --version` writes to stderr, and Windows PowerShell 5.1 escalates a
    native command's stderr to a terminating error as soon as the streams are
    merged. Relax the preference for the duration of the call so the version is
    read instead of the whole probe being reported as absent -- otherwise a local
    5.1 run and a CI PowerShell 7 run would compute different fingerprints.
    #>
    param(
        [Parameter(Mandatory)][string] $Command,
        [string[]] $Arguments = @('--version')
    )

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Command @Arguments 2>&1 | Select-Object -First 1
        if ($null -eq $output) { return 'absent' }
        return ($output.ToString()).Trim()
    } catch {
        return 'absent'
    } finally {
        $ErrorActionPreference = $previous
    }
}

function Invoke-OpenMuseNative {
    <#
    .SYNOPSIS
    Run a native command and fail on a non-zero exit, in 5.1 and 7 alike.

    .DESCRIPTION
    stderr from a native command is a diagnostic, not a failure: rustup and
    flutter both narrate progress there. Windows PowerShell 5.1 turns such a line
    into a terminating error while $ErrorActionPreference is Stop, so relax it
    around the call and let the exit code decide.
    #>
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Arguments,
        [string] $WorkingDirectory = '',
        [string] $What = ''
    )

    $label = if ($What) { $What } else { "$FilePath $($Arguments -join ' ')" }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $exitCode = 0
    try {
        if ($WorkingDirectory) {
            Push-Location $WorkingDirectory
            try { & $FilePath @Arguments; $exitCode = $LASTEXITCODE } finally { Pop-Location }
        } else {
            & $FilePath @Arguments
            $exitCode = $LASTEXITCODE
        }
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($exitCode -ne 0) { throw "$label failed with exit code $exitCode" }
}

function Get-OpenMuseVisualStudioIdentity {
    <#
    .SYNOPSIS
    Visual Studio install version, MSVC toolset and Windows SDK versions.

    .DESCRIPTION
    Runner images are refreshed monthly. A stale MSVC toolset silently changes
    the produced binaries, so it is part of every native fingerprint.
    #>
    $identity = [ordered]@{ vs = 'absent'; msvc = 'absent'; sdk = 'absent' }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $install = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First 1)
        $version = (& $vswhere -latest -property installationVersion 2>$null | Select-Object -First 1)
        if ($version) { $identity.vs = ($version.ToString()).Trim() }
        if ($install) {
            $tools = Join-Path $install.ToString().Trim() 'VC\Tools\MSVC'
            if (Test-Path $tools) {
                $latest = Get-ChildItem $tools -Directory | Sort-Object Name | Select-Object -Last 1
                if ($latest) { $identity.msvc = $latest.Name }
            }
        }
    }

    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Include'
    if (Test-Path $kits) {
        $latest = Get-ChildItem $kits -Directory | Sort-Object Name | Select-Object -Last 1
        if ($latest) { $identity.sdk = $latest.Name }
    }

    return $identity
}

function Get-OpenMuseToolchainIdentity {
    <#
    .SYNOPSIS
    Everything outside the repository that can change a Windows build output.
    #>
    param([switch] $IncludeFlutter)

    $visualStudio = Get-OpenMuseVisualStudioIdentity
    $identity = [ordered]@{
        rustc  = Get-OpenMuseCommandVersion -Command 'rustc' -Arguments @('-V')
        cargo  = Get-OpenMuseCommandVersion -Command 'cargo' -Arguments @('-V')
        python = Get-OpenMuseCommandVersion -Command 'python' -Arguments @('-V')
        vs     = $visualStudio.vs
        msvc   = $visualStudio.msvc
        sdk    = $visualStudio.sdk
        cmake  = Get-OpenMuseCommandVersion -Command 'cmake'
        ninja  = Get-OpenMuseCommandVersion -Command 'ninja'
    }

    if ($IncludeFlutter) {
        $flutter = Get-OpenMuseCommandVersion -Command 'flutter'
        $dart = Get-OpenMuseCommandVersion -Command 'dart'
        if ($flutter -eq 'absent' -and $env:FLUTTER_ROOT) {
            $flutter = "FLUTTER_ROOT=$env:FLUTTER_ROOT"
        }
        $identity['flutter'] = $flutter
        $identity['dart'] = $dart
    }

    return $identity
}

function Get-OpenMuseFingerprint {
    <#
    .SYNOPSIS
    Fingerprint of one build domain: content digest plus toolchain plus parameters.
    #>
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string[]] $Paths,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Toolchain,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Parameters
    )

    $manifest = [ordered]@{
        content    = Get-OpenMuseTreeDigest -RepoRoot $RepoRoot -Paths $Paths
        toolchain  = $Toolchain
        parameters = $Parameters
    }
    # ConvertTo-Json keeps a stable key order for an ordered dictionary, so the
    # digest only moves when a value moves.
    return Get-OpenMuseSha256Hex ($manifest | ConvertTo-Json -Depth 6 -Compress)
}

function Read-OpenMuseDomainMarker {
    param(
        [Parameter(Mandatory)][string] $DomainCacheDir,
        [Parameter(Mandatory)][string] $Domain
    )

    $file = Join-Path $DomainCacheDir "$Domain.json"
    if (-not (Test-Path $file)) { return $null }
    try {
        return Get-Content $file -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Test-OpenMuseDomainReusable {
    <#
    .SYNOPSIS
    True when the marker matches the expected fingerprint and the outputs exist.
    #>
    param(
        $Marker,
        [Parameter(Mandatory)][string] $Fingerprint,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Outputs
    )

    if ($null -eq $Marker) { return $false }
    if ($Marker.fingerprint -ne $Fingerprint) { return $false }
    foreach ($output in $Outputs) {
        if (-not (Test-Path $output)) { return $false }
    }
    return $true
}

function Write-OpenMuseDomainMarker {
    <#
    .SYNOPSIS
    Record that a domain was built with this fingerprint.

    .DESCRIPTION
    Written only *after* the domain succeeded, and written next to the outputs it
    describes so the marker and the artefacts always travel together in a cache
    entry.
    #>
    param(
        [Parameter(Mandatory)][string] $DomainCacheDir,
        [Parameter(Mandatory)][string] $Domain,
        [Parameter(Mandatory)][string] $Fingerprint,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Toolchain
    )

    New-Item -ItemType Directory -Force -Path $DomainCacheDir | Out-Null
    $file = Join-Path $DomainCacheDir "$Domain.json"
    $json = [ordered]@{
        domain      = $Domain
        fingerprint = $Fingerprint
        builtAt     = (Get-Date).ToUniversalTime().ToString('o')
        toolchain   = $Toolchain
    } | ConvertTo-Json -Depth 6
    Write-OpenMuseTextFile -Path $file -Lines @($json)
}

function Format-OpenMuseDomainState {
    param(
        [Parameter(Mandatory)][string] $Domain,
        [Parameter(Mandatory)][string] $State,
        [Parameter(Mandatory)][string] $Fingerprint
    )

    return "$Domain=$State($($Fingerprint.Substring(0, 12)))"
}
