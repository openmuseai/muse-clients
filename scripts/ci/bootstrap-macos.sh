#!/usr/bin/env bash
# Prepare a Mac (developer machine or GitHub macos-14) for the OpenMuse build.
#
# The workflow installs Rust, Flutter and Node. This script only makes that
# toolchain usable: rustup targets, the macOS desktop artifacts, and a check
# that the pinned Helix / Node / DSH inputs are in the checkout.
#
#   ./scripts/ci/bootstrap-macos.sh
#   ./scripts/ci/bootstrap-macos.sh --expected-flutter-version 3.44.2
set -euo pipefail

RUST_TARGETS="aarch64-apple-darwin"
EXPECTED_FLUTTER=""
SKIP_PRECACHE=0

usage() {
  cat <<'EOF'
usage: bootstrap-macos.sh [options]

  --rust-targets <list>              comma-separated rustup targets
  --expected-flutter-version <ver>   fail when flutter --version does not match
  --skip-precache                    do not run flutter precache --macos
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rust-targets) RUST_TARGETS="$2"; shift 2 ;;
    --expected-flutter-version) EXPECTED_FLUTTER="$2"; shift 2 ;;
    --skip-precache) SKIP_PRECACHE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

step() { printf '\033[0;36m==> %s\033[0m\n' "$1"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "bootstrap-macos.sh only runs on macOS" >&2
  exit 1
fi

step "checking the base toolchain"
for cmd in git python3 curl xcodebuild flutter dart cargo rustc rustup node npm; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd is not on PATH" >&2
    exit 1
  fi
done
echo "  xcode: $(xcodebuild -version | tr '\n' ' ')"
echo "  flutter: $(flutter --version | awk 'NR==1 {print; exit}')"
echo "  rustc: $(rustc -V)"
echo "  node: $(node --version)"

if [[ -n "$EXPECTED_FLUTTER" ]]; then
  actual="$(flutter --version | awk 'NR==1 {print $2; exit}')"
  if [[ "$actual" != "$EXPECTED_FLUTTER" ]]; then
    echo "flutter is $actual, expected $EXPECTED_FLUTTER" >&2
    exit 1
  fi
fi

step "rustup targets"
IFS=',' read -r -a targets <<<"$RUST_TARGETS"
for target in "${targets[@]}"; do
  target="$(printf '%s' "$target" | tr -d '[:space:]')"
  [[ -n "$target" ]] || continue
  echo "  rustup target add $target"
  rustup target add "$target"
done

step "flutter macos desktop"
flutter config --enable-macos-desktop
if [[ "$SKIP_PRECACHE" -eq 0 ]]; then
  flutter precache --macos
fi

step "pinned packager inputs"
required=(
  "$ROOT/plugins/helix/assets/engines/helix/hx"
  "$ROOT/plugins/helix/assets/engines/helix/runtime/languages.toml"
  "$ROOT/plugins/helix/assets/engines/helix/runtime/themes/onelight.toml"
  "$ROOT/plugins/helix/assets/engines/helix/runtime/themes/openmuse_dark.toml"
  "$ROOT/third_party/dsh/package.json"
  "$ROOT/third_party/dsh/package-lock.json"
  "$ROOT/third_party/node/v22.19.0/SHASUMS256.txt"
  "$ROOT/third_party/node/v22.19.0/node-v22.19.0-darwin-arm64.tar.gz"
  "$ROOT/third_party/node/v22.19.0/node-v22.19.0-darwin-x64.tar.gz"
)
missing=0
for path in "${required[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "  missing $path" >&2
    missing=1
  fi
done
if [[ ! -d "$ROOT/plugins/helix/assets/engines/helix/runtime/grammars" ]]; then
  echo "  missing helix runtime/grammars" >&2
  missing=1
fi
if [[ ! -d "$ROOT/plugins/helix/assets/engines/helix/runtime/queries" ]]; then
  echo "  missing helix runtime/queries" >&2
  missing=1
fi
if [[ "$missing" -ne 0 ]]; then
  echo "pinned Helix, DSH or Node inputs are not in this checkout" >&2
  exit 1
fi
echo "  helix, DSH lockfile and Node archives are present"

echo "bootstrap-macos: done"
