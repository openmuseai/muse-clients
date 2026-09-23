#!/usr/bin/env bash
# Print the macOS toolchain the Flutter build will actually see.
#
# Pair of .github/workflows/diagnose-macos.yml. Takes minutes, not the full
# package, so it is the first thing to run when macos-build.yml cannot see
# Xcode or Flutter.
#
#   ./scripts/ci/diagnose-macos.sh
#   ./scripts/ci/diagnose-macos.sh --check-build
set -euo pipefail

CHECK_BUILD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-build) CHECK_BUILD=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

section() { printf '\n\033[0;36m==> %s\033[0m\n' "$1"; }
kv() { printf '  %-18s %s\n' "$1" "$2"; }

section "host"
kv sw_vers "$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
kv arch "$(uname -m)"
kv root "$ROOT"

section "xcode"
if xcode-select -p >/dev/null 2>&1; then
  kv xcode-select "$(xcode-select -p)"
else
  kv xcode-select "MISSING"
fi
if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -version 2>/dev/null | sed 's/^/  /'
else
  kv xcodebuild "MISSING"
fi

section "python / node / rust / flutter"
command -v python3 >/dev/null && kv python3 "$(python3 --version 2>&1)" || kv python3 MISSING
command -v node >/dev/null && kv node "$(node --version)" || kv node MISSING
command -v npm >/dev/null && kv npm "$(npm --version)" || kv npm MISSING
command -v rustc >/dev/null && kv rustc "$(rustc -V)" || kv rustc MISSING
command -v cargo >/dev/null && kv cargo "$(cargo --version)" || kv cargo MISSING
if command -v flutter >/dev/null 2>&1; then
  flutter --version | sed 's/^/  /'
  printf '\n  flutter doctor -v:\n'
  flutter doctor -v | sed 's/^/  /' || true
else
  kv flutter MISSING
fi

section "pinned inputs"
for path in \
  plugins/helix/assets/engines/helix/hx \
  plugins/helix/assets/engines/helix/runtime/languages.toml \
  third_party/node/v22.19.0/node-v22.19.0-darwin-arm64.tar.gz \
  third_party/node/v22.19.0/node-v22.19.0-darwin-x64.tar.gz \
  third_party/dsh/package-lock.json
do
  if [[ -e "$ROOT/$path" ]]; then
    kv present "$path"
  else
    kv MISSING "$path"
  fi
done

if [[ "$CHECK_BUILD" -eq 1 ]]; then
  section "scratch flutter build macos"
  if ! command -v flutter >/dev/null 2>&1; then
    echo "flutter is missing; cannot run --check-build" >&2
    exit 1
  fi
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/muse-macos-diag.XXXXXX")"
  flutter config --enable-macos-desktop >/dev/null
  (
    cd "$scratch"
    flutter create --platforms=macos diag_app
    cd diag_app
    flutter build macos --debug
  )
  printf '  scratch build succeeded in %s\n' "$scratch"
  rm -rf "$scratch"
fi

printf '\ndiagnose-macos: done\n'
