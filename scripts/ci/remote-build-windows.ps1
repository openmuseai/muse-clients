#!/usr/bin/env pwsh
<#
.SYNOPSIS
Trigger the Windows build on GitHub and follow it from this terminal.

.DESCRIPTION
Turns the GitHub Windows runner into a remote Windows build machine without the
gh CLI: it dispatches .github/workflows/windows-build.yml through the Actions REST
API, waits for the run, prints step progress, and on failure lists the failed
steps (optionally downloading the log archive).

The token needs the repo and workflow scopes. Pass -Token, or rely on
OPENMUSE_TOKEN (the variable this project standardises on). If neither is
available the script falls back to gh auth token and then to the PAT git already
stores for github.com, so it normally needs no setup at all.

  setx OPENMUSE_TOKEN '<PAT>'          # once, then open a new terminal
  pwsh scripts/ci/remote-build-windows.ps1
  pwsh scripts/ci/remote-build-windows.ps1 -Push -Inputs @{ profile = 'debug' }
  pwsh scripts/ci/remote-build-windows.ps1 -DownloadLogs -Inputs @{ skip_tests = 'false' }

.EXAMPLE
pwsh scripts/ci/remote-build-windows.ps1 -Push
#>
[CmdletBinding()]
param(
    [string] $Repository = 'openmuseai/muse-clients',
    [string] $Workflow = 'windows-build.yml',
    [string] $Ref = '',
    [hashtable] $Inputs = @{},
    [string] $Token = '',
    [string] $RunId = '',
    [switch] $Push,
    [string] $Remote = 'origin',
    [switch] $NoWatch,
    [switch] $DownloadLogs,
    [int] $PollSeconds = 30,
    [int] $TimeoutMinutes = 180
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    Write-Host "note: could not pin TLS 1.2 ($($_.Exception.Message))" -ForegroundColor Yellow
}

function Write-Step {
    param([string] $Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

$script:CredentialStoreError = ''
function Get-StoredGitHubToken {
    <#
    Read the PAT that Git Credential Manager already keeps for github.com.

    Ask git rather than the Windows credential store directly: GCM stores its own
    serialised blob (the entry `cmdkey /list` shows as 'git:https://github.com'),
    and `git credential fill` is the supported way to read it back. Reading
    CredentialBlob by hand guesses at the encoding and can silently return a
    mangled token.

    The request goes through a temp file because Git for Windows reads the
    credential protocol more reliably from a redirected file than from a
    PowerShell pipeline.
    #>
    param([string] $HostName = 'github.com')
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("openmuse-cred-" + [guid]::NewGuid().ToString('n'))
    try {
        [System.IO.File]::WriteAllText($temp, "protocol=https`nhost=$HostName`n", (New-Object System.Text.ASCIIEncoding))
        $output = @(& cmd /c "git credential fill < `"$temp`" 2>&1")
        $passwordLine = $output | Where-Object { $_ -like 'password=*' } | Select-Object -First 1
        if (-not $passwordLine) {
            $script:CredentialStoreError = "git credential fill returned no password for $HostName"
            return $null
        }
        $secret = ($passwordLine -replace '^password=', '').Trim()
        if ([string]::IsNullOrWhiteSpace($secret)) {
            $script:CredentialStoreError = "the stored credential for $HostName has no secret"
            return $null
        }
        $userLine = $output | Where-Object { $_ -like 'username=*' } | Select-Object -First 1
        $userName = if ($userLine) { ($userLine -replace '^username=', '').Trim() } else { '' }
        return @{ Token = $secret; UserName = $userName }
    } catch {
        $script:CredentialStoreError = $_.Exception.Message
        return $null
    } finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $temp
    }
}

# Token resolution, most explicit first:
#   -Token -> OPENMUSE_TOKEN -> GH_TOKEN/GITHUB_TOKEN -> gh auth token -> the
#   credential git already stores for github.com.
if ([string]::IsNullOrWhiteSpace($Token)) {
    foreach ($name in @('OPENMUSE_TOKEN', 'GH_TOKEN', 'GITHUB_TOKEN')) {
        $candidate = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            $candidate = [Environment]::GetEnvironmentVariable($name, 'User')
        }
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $Token = $candidate.Trim()
            Write-Host "using the token from $name" -ForegroundColor DarkGray
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($Token) -and (Get-Command 'gh' -ErrorAction SilentlyContinue)) {
    try {
        $fromGh = (& gh auth token 2>$null | Select-Object -First 1)
        if ($fromGh) { $Token = $fromGh.ToString().Trim() }
    } catch { }
}
if ([string]::IsNullOrWhiteSpace($Token)) {
    $stored = Get-StoredGitHubToken
    if ($stored) {
        $Token = $stored.Token
        Write-Host "using the github credential stored for git (user: $($stored.UserName))" -ForegroundColor DarkGray
    }
}
if ([string]::IsNullOrWhiteSpace($Token)) {
    throw @"
no token available; pick one:
  - this project's standard variable (repo + workflow scopes):
      setx OPENMUSE_TOKEN '<PAT>'      # then open a new terminal
  - let git store it once and this script reuses it:
      git push    # and complete the Git Credential Manager prompt
  - or install the gh CLI once: gh auth login

credential store: $(if ($script:CredentialStoreError) { $script:CredentialStoreError } else { 'no stored github credential found' })
"@
}

$headers = @{
    Authorization          = "token $Token"
    Accept                 = 'application/vnd.github+json'
    'User-Agent'           = 'openmuse-remote-build'
    'X-GitHub-Api-Version' = '2022-11-28'
}
$api = "https://api.github.com/repos/$Repository"

function Get-RepoRoot {
    return (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

if ([string]::IsNullOrWhiteSpace($Ref)) {
    $Ref = (& git -C (Get-RepoRoot) rev-parse --abbrev-ref HEAD).Trim()
    if ($Ref -eq 'HEAD') { throw 'detached HEAD: pass -Ref <branch>' }
}
Write-Host "repository: $Repository"
Write-Host "workflow:   $Workflow"
Write-Host "ref:        $Ref"

if ($Push) {
    Write-Step "git push $Remote $Ref"
    & git -C (Get-RepoRoot) push $Remote $Ref
    if ($LASTEXITCODE -ne 0) { throw "git push failed ($LASTEXITCODE)" }
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    Write-Step 'dispatching workflow_dispatch'
    $dispatchedAt = [DateTime]::UtcNow.AddSeconds(-5)
    $body = @{ ref = $Ref }
    if ($Inputs.Count -gt 0) { $body['inputs'] = $Inputs }
    $json = $body | ConvertTo-Json -Depth 5 -Compress
    Invoke-RestMethod -Method Post -Uri "$api/actions/workflows/$Workflow/dispatches" -Headers $headers -Body $json -ContentType 'application/json' | Out-Null
    Write-Host "    accepted (inputs: $(if ($Inputs.Count) { ($Inputs.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ' } else { 'defaults' }))"

    if ($NoWatch) { exit 0 }

    Write-Step 'waiting for the run to appear'
    $run = $null
    for ($attempt = 0; $attempt -lt 20 -and -not $run; $attempt++) {
        Start-Sleep -Seconds 3
        $runs = Invoke-RestMethod -Uri "$api/actions/runs?event=workflow_dispatch&branch=$Ref&per_page=10" -Headers $headers
        $run = $runs.workflow_runs |
            Where-Object { $_.path -like "*$Workflow" -and ([DateTime]$_.created_at) -ge $dispatchedAt } |
            Sort-Object created_at -Descending |
            Select-Object -First 1
    }
    if (-not $run) { throw "the run did not appear; check $api/actions/workflows/$Workflow" }
    $RunId = $run.id
    Write-Host "    run $RunId : $($run.html_url)"
} else {
    Write-Step "watching existing run $RunId"
    $existing = Invoke-RestMethod -Uri "$api/actions/runs/$RunId" -Headers $headers
    Write-Host "    $($existing.name) on $($existing.head_branch): $($existing.html_url)"
}

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$seen = @{}
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $PollSeconds
    try {
        $current = Invoke-RestMethod -Uri "$api/actions/runs/$RunId" -Headers $headers
        $jobs = (Invoke-RestMethod -Uri "$api/actions/runs/$RunId/jobs" -Headers $headers).jobs
    } catch {
        Write-Host "    (poll failed: $($_.Exception.Message))" -ForegroundColor Yellow
        continue
    }

    foreach ($job in $jobs) {
        foreach ($step in $job.steps) {
            $state = switch ($step.status) {
                'completed' { if ($step.conclusion -eq 'success') { 'ok' } elseif ($step.conclusion -eq 'skipped') { 'skipped' } else { $step.conclusion } }
                'in_progress' { 'running' }
                default { 'pending' }
            }
            $key = "$($job.name)/$($step.name)"
            if (-not $seen.ContainsKey($key) -or $seen[$key] -ne $state) {
                $seen[$key] = $state
                $colour = switch ($state) {
                    'ok' { 'Green' }
                    'running' { 'Cyan' }
                    'skipped' { 'DarkGray' }
                    'pending' { 'DarkGray' }
                    default { 'Red' }
                }
                Write-Host ("    [{0,-8}] {1}" -f $state, $step.name) -ForegroundColor $colour
            }
        }
    }

    if ($current.status -eq 'completed') {
        Write-Host ''
        $ok = $current.conclusion -eq 'success'
        Write-Host "run finished: $($current.status)/$($current.conclusion)" -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
        Write-Host "url: $($current.html_url)"
        if (-not $ok) {
            Write-Step 'failed steps'
            foreach ($job in $jobs) {
                foreach ($step in $job.steps) {
                    if ($step.status -eq 'completed' -and $step.conclusion -notin @('success', 'skipped')) {
                        Write-Host "    $($job.name) / $($step.name): $($step.conclusion)" -ForegroundColor Red
                    }
                }
            }
            if ($DownloadLogs) {
                $dir = Join-Path (Get-RepoRoot) 'tmp/ci-logs'
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
                $zip = Join-Path $dir "run-$RunId.zip"
                Write-Step "downloading logs -> $zip"
                Invoke-WebRequest -Uri "$api/actions/runs/$RunId/logs" -Headers $headers -OutFile $zip -UseBasicParsing
                Write-Host "    $(if (Test-Path $zip) { [int]((Get-Item $zip).Length / 1KB) } else { 0 }) KB"
            }
            exit 1
        }
        exit 0
    }
}
Write-Host "timed out after $TimeoutMinutes minutes; run $RunId is still going: https://github.com/$Repository/actions/runs/$RunId" -ForegroundColor Yellow
exit 2
