#!/usr/bin/env bash
# Unique macOS build entry. desktop-gates.yml and macos-build.yml both call this,
# and scripts/package_macos.sh stays the packager they share.
#
#   ./scripts/ci/build-macos.sh
#   ./scripts/ci/build-macos.sh --profile debug --skip-tests
#   ./scripts/ci/build-macos.sh --dry-run
set -euo pipefail

PROFILE="release"
RUST_TARGETS="aarch64-apple-darwin"
SKIP_TESTS=0
DRY_RUN=0

usage() {
  cat <<'EOF'
usage: build-macos.sh [options]

  --profile release|debug
  --rust-targets <list>   recorded in build-info; packaging uses the host arch
  --skip-tests            cargo build instead of cargo test; skip flutter test
  --dry-run               print the steps and exit
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --rust-targets) RUST_TARGETS="$2"; shift 2 ;;
    --skip-tests) SKIP_TESTS=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$PROFILE" in
  release|debug) ;;
  *) echo "profile must be release or debug" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DIST="$ROOT/dist"
ARCHIVE="$DIST/OpenMuse-macos.zip"
SUMS="$DIST/SHA256SUMS.txt"
INFO="$DIST/build-info.txt"

step() { printf '\033[0;36m==> %s\033[0m\n' "$1"; }

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "profile=$PROFILE rust_targets=$RUST_TARGETS skip_tests=$SKIP_TESTS"
  if [[ "$SKIP_TESTS" -eq 1 ]]; then
    echo "cargo build --workspace --locked"
  else
    echo "cargo test --workspace --locked"
  fi
  echo "scripts/package_macos.sh --profile $PROFILE$([[ "$SKIP_TESTS" -eq 1 ]] && echo ' --skip-tests')"
  echo "write $SUMS and $INFO"
  exit 0
fi

step "rust"
if [[ "$SKIP_TESTS" -eq 1 ]]; then
  (cd "$ROOT" && cargo build --workspace --locked)
else
  (cd "$ROOT" && cargo test --workspace --locked)
fi

step "package"
pack_args=(--profile "$PROFILE")
if [[ "$SKIP_TESTS" -eq 1 ]]; then
  pack_args+=(--skip-tests)
fi
"$ROOT/scripts/package_macos.sh" "${pack_args[@]}"

step "checksums"
if [[ ! -f "$ARCHIVE" ]]; then
  echo "package_macos.sh did not write $ARCHIVE" >&2
  exit 1
fi
hash="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
printf '%s  %s\n' "$hash" "$(basename "$ARCHIVE")" >"$SUMS"
commit="$(git -C "$ROOT" rev-parse HEAD)"
{
  echo "product: OpenMuse"
  echo "profile: $PROFILE"
  echo "commit: $commit"
  echo "arch: $(uname -m)"
  echo "rust_targets: $RUST_TARGETS"
  echo "builtAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "flutter: $(flutter --version | awk 'NR==1 {print; exit}')"
  echo "rustc: $(rustc -V)"
  echo "archive: $(basename "$ARCHIVE") sha256=$hash"
} >"$INFO"

step "verify"
if ! unzip -l "$ARCHIVE" | grep -q 'OpenMuse.app/Contents/MacOS/OpenMuse'; then
  echo "archive is missing OpenMuse.app/Contents/MacOS/OpenMuse" >&2
  exit 1
fi
actual="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$actual" != "$hash" ]]; then
  echo "SHA256SUMS.txt does not match the archive" >&2
  exit 1
fi
echo "  sha256 $actual"
echo "build-macos: done"
echo "  $ARCHIVE"
