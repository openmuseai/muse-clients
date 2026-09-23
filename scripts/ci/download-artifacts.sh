#!/usr/bin/env bash
# Download artifacts from a successful GitHub Actions run and check SHA256SUMS.
#
#   ./scripts/ci/download-artifacts.sh
#   ./scripts/ci/download-artifacts.sh --run-id 123
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/github.sh
source "${SCRIPT_DIR}/lib/github.sh"

REPOSITORY="${REPOSITORY:-openmuseai/muse-clients}"
WORKFLOW="${WORKFLOW:-macos-build.yml}"
RUN_ID=""
OUT_DIR=""
TOKEN_ARG=""
VERIFY_ONLY=0
KEEP_ZIP=0

usage() {
  cat <<'EOF'
usage: download-artifacts.sh [options]

  --run-id <id>        run to download (default: latest successful run of the workflow)
  --repo <owner/repo>
  --workflow <file>    used when --run-id is omitted (default: macos-build.yml)
  --out <dir>          destination (default: tmp/ci-artifacts/<run id>)
  --token <pat>
  --verify-only        only re-check SHA256SUMS.txt already on disk
  --keep-zip           keep the downloaded artifact zip files
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2 ;;
    --repo) REPOSITORY="$2"; shift 2 ;;
    --workflow) WORKFLOW="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --token) TOKEN_ARG="$2"; shift 2 ;;
    --verify-only) VERIFY_ONLY=1; shift ;;
    --keep-zip) KEEP_ZIP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! GITHUB_TOKEN="$(github_token "$TOKEN_ARG")"; then
  echo "no GitHub token: export OPENMUSE_TOKEN=<PAT with repo>" >&2
  exit 1
fi
export GITHUB_TOKEN
printf 'using the token from %s\n' "${GITHUB_TOKEN_SOURCE:---token}"

if [[ -z "$RUN_ID" ]]; then
  listing="$(github_api GET "/repos/${REPOSITORY}/actions/workflows/${WORKFLOW}/runs?status=success&per_page=1")"
  RUN_ID="$(printf '%s' "$listing" | python3 -c 'import json,sys; runs=json.load(sys.stdin).get("workflow_runs") or []; print(runs[0]["id"] if runs else "")')"
  if [[ -z "$RUN_ID" ]]; then
    echo "no successful run of ${WORKFLOW} on ${REPOSITORY}" >&2
    exit 1
  fi
fi

if [[ -z "$OUT_DIR" ]]; then
  ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
  OUT_DIR="${ROOT}/tmp/ci-artifacts/${RUN_ID}"
fi
mkdir -p "$OUT_DIR"

echo "run: https://github.com/${REPOSITORY}/actions/runs/${RUN_ID}"
echo "out: $OUT_DIR"

if [[ "$VERIFY_ONLY" -eq 0 ]]; then
  echo "==> listing artifacts"
  listed="$(github_api GET "/repos/${REPOSITORY}/actions/runs/${RUN_ID}/artifacts")"
  count="$(printf '%s' "$listed" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("artifacts") or []))')"
  if [[ "$count" -eq 0 ]]; then
    echo "run ${RUN_ID} has no artifacts (the build did not reach the upload step)" >&2
    exit 1
  fi

  python3 - "$listed" "$OUT_DIR" <<'PY'
import json, os, sys
data = json.loads(sys.argv[1])
out_dir = sys.argv[2]
meta = []
for artifact in data.get("artifacts") or []:
    name = artifact.get("name") or ""
    size = int(artifact.get("size_in_bytes") or 0)
    mb = round(size / (1024 * 1024), 1)
    if artifact.get("expired"):
        print(f"    stale {name:<34} (expired)")
        continue
    print(f"    get   {name:<34} {mb} MB")
    meta.append({"id": artifact["id"], "name": name})
json.dump(meta, open(os.path.join(out_dir, ".artifact-list.json"), "w"))
PY

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    art_id="${line%% *}"
    art_name="${line#* }"
    zip_path="${OUT_DIR}/${art_name}.zip"
    echo "          -> $(basename "$zip_path")"
    github_download_artifact \
      "https://api.github.com/repos/${REPOSITORY}/actions/artifacts/${art_id}/zip" \
      "$zip_path"
    target="${OUT_DIR}/${art_name}"
    rm -rf "$target"
    mkdir -p "$target"
    unzip -q -o "$zip_path" -d "$target"
    if [[ "$KEEP_ZIP" -eq 0 ]]; then
      rm -f "$zip_path"
    fi
  done < <(python3 -c '
import json,sys
for item in json.load(open(sys.argv[1])):
    print(item["id"], item["name"])
' "${OUT_DIR}/.artifact-list.json")
  rm -f "${OUT_DIR}/.artifact-list.json"
fi

echo "==> verifying SHA256SUMS"
sums="$(find "$OUT_DIR" -name SHA256SUMS.txt -type f | head -1 || true)"
if [[ -z "$sums" ]]; then
  echo "    no SHA256SUMS.txt in the artifacts"
else
  dir="$(dirname "$sums")"
  if ! github_sha256sums_check "$dir"; then
    echo "one or more files did not match SHA256SUMS.txt" >&2
    exit 1
  fi
fi

echo "artifacts are in $OUT_DIR"
