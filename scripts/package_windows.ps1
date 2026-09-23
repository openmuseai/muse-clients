$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$AppRoot = Join-Path $RepoRoot "app/openmuse_host"
$DistRoot = Join-Path $RepoRoot "dist"
$BundleRoot = Join-Path $AppRoot "build/windows/x64/runner/Release"
$Archive = Join-Path $DistRoot "OpenMuse-windows-x64.zip"

Push-Location $AppRoot
try {
  flutter pub get
  flutter analyze
  flutter test
  flutter build windows --release
} finally {
  Pop-Location
}

$Executable = Join-Path $BundleRoot "OpenMuse.exe"
if (-not (Test-Path $Executable)) {
  throw "Missing Windows executable: $Executable"
}

New-Item -ItemType Directory -Force -Path $DistRoot | Out-Null
if (Test-Path $Archive) {
  Remove-Item $Archive
}
Compress-Archive -Path (Join-Path $BundleRoot "*") -DestinationPath $Archive
Write-Output $Archive

