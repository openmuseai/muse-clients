#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
packages=(
  muse_resource_contract
  muse_engine_adapter
  muse_engine_tck
  muse_resource_bridge
  muse_surface_orchestrator
  muse_helix_surface
  muse_ioffice_adapter
  muse_web_viewer_surface
)

for package in "${packages[@]}"; do
  package_root="$repo_root/packages/$package"
  echo "==> $package"
  (
    cd "$package_root"
    flutter analyze
    flutter test
  )
done
