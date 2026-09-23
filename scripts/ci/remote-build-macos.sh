#!/usr/bin/env bash
# Trigger the macOS build on GitHub and follow it from a Mac shell.
#
# Uses the Actions REST API (curl) so it works without the gh CLI. Token order
# matches scripts/ci/remote-build-windows.ps1: --token, OPENMUSE_TOKEN,
# GH_TOKEN, GITHUB_TOKEN, then `gh auth token`.
#
#   ./scripts/ci/remote-build-macos.sh
#   ./scripts/ci/remote-build-macos.sh --push
#   ./scripts/ci/remote-build-macos.sh --ref main -f profile=debug
#   ./scripts/ci/remote-build-macos.sh --run-id 123 --download-logs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/github.sh
source "${SCRIPT_DIR}/lib/github.sh"

REPOSITORY="${REPOSITORY:-openmuseai/muse-clients}"
WORKFLOW="${WORKFLOW:-macos-build.yml}"
REF=""
PUSH=0
DOWNLOAD=0
DOWNLOAD_LOGS=0
RUN_ID=""
TOKEN_ARG=""
POLL_SECONDS="${POLL_SECONDS:-20}"
TIMEOUT_MINUTES="${TIMEOUT_MINUTES:-180}"
INPUTS=()

usage() {
  cat <<'EOF'
usage: remote-build-macos.sh [options] [-f key=value ...]

  --ref <branch>       branch or tag to build (default: current branch)
  --repo <owner/repo>  repository that hosts the workflow
  --workflow <file>    workflow file name (default: macos-build.yml)
  --push               git push the current branch first
  --run-id <id>        watch an existing run instead of dispatching
  --download           after success, download artifacts (download-artifacts.sh)
  --download-logs      always fetch the run log zip into tmp/ci-logs/
  --token <pat>        override OPENMUSE_TOKEN / GH_TOKEN
  --timeout-minutes N  give up watching after N minutes (default: 180)
  -f key=value         workflow_dispatch input (repeatable)
  -h, --help

inputs the workflow accepts:
  profile         release | debug
  rust_targets    comma separated rustup targets
  skip_tests      true | false
  retention_days  artifact retention in days
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) REF="$2"; shift 2 ;;
    --repo) REPOSITORY="$2"; shift 2 ;;
    --workflow) WORKFLOW="$2"; shift 2 ;;
    --push) PUSH=1; shift ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --download) DOWNLOAD=1; shift ;;
    --download-logs) DOWNLOAD_LOGS=1; shift ;;
    --token) TOKEN_ARG="$2"; shift 2 ;;
    --timeout-minutes) TIMEOUT_MINUTES="$2"; shift 2 ;;
    -f|--field) INPUTS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! GITHUB_TOKEN="$(github_token "$TOKEN_ARG")"; then
  echo "no GitHub token: export OPENMUSE_TOKEN=<PAT with repo + workflow>" >&2
  exit 1
fi
export GITHUB_TOKEN
printf 'using the token from %s\n' "${GITHUB_TOKEN_SOURCE:---token}"

if [[ -z "$REF" ]]; then
  REF="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$REF" == "HEAD" ]]; then
    echo "detached HEAD: pass --ref <branch>" >&2
    exit 1
  fi
fi

if [[ "$PUSH" == "1" ]]; then
  echo "==> git push origin $REF"
  git push origin "$REF"
fi

if [[ -z "$RUN_ID" ]]; then
  inputs_json="{"
  first=1
  for pair in "${INPUTS[@]+"${INPUTS[@]}"}"; do
    [[ -n "$pair" ]] || continue
    key="${pair%%=*}"
    value="${pair#*=}"
    if [[ "$first" -eq 1 ]]; then
      first=0
    else
      inputs_json+=","
    fi
    inputs_json+="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1])+": "+json.dumps(sys.argv[2]))' "$key" "$value")"
  done
  inputs_json+="}"
  body="$(python3 -c 'import json,sys; print(json.dumps({"ref": sys.argv[1], "inputs": json.loads(sys.argv[2])}))' "$REF" "$inputs_json")"
  echo "==> dispatching $WORKFLOW on $REPOSITORY@$REF"
  code="$(github_api_code POST "/repos/${REPOSITORY}/actions/workflows/${WORKFLOW}/dispatches" "$body")"
  if [[ "$code" != "204" ]]; then
    echo "dispatch failed: HTTP $code" >&2
    printf '%s\n' "$GH_API_BODY" >&2
    exit 1
  fi

  echo "==> waiting for the run to appear"
  RUN_ID=""
  for _ in $(seq 1 30); do
    sleep 3
    listing="$(github_api GET "/repos/${REPOSITORY}/actions/workflows/${WORKFLOW}/runs?event=workflow_dispatch&branch=${REF}&per_page=5")"
    RUN_ID="$(python3 -c 'import json,sys; runs=json.load(sys.stdin).get("workflow_runs") or []; print(runs[0]["id"] if runs else "")' <<<"$listing")"
    [[ -n "$RUN_ID" ]] && break
  done
  if [[ -z "$RUN_ID" ]]; then
    echo "the run did not appear" >&2
    exit 1
  fi
fi

echo "run: https://github.com/${REPOSITORY}/actions/runs/${RUN_ID}"

deadline=$(( $(date +%s) + TIMEOUT_MINUTES * 60 ))
last_stamp=""
conclusion=""
status="queued"

print_jobs() {
  github_api GET "/repos/${REPOSITORY}/actions/runs/${RUN_ID}/jobs" | python3 -c '
import json, sys
data = json.load(sys.stdin)
marks = {
    "success": "ok",
    "in_progress": "running",
    "queued": "queued",
    "failure": "FAIL",
    "cancelled": "cancel",
    "skipped": "skip",
}
for job in data.get("jobs") or []:
    name = job.get("name")
    status = job.get("status")
    conclusion = job.get("conclusion") or "-"
    print("  job %s: %s / %s" % (name, status, conclusion))
    for step in job.get("steps") or []:
        raw = step.get("conclusion") or step.get("status") or "-"
        mark = marks.get(raw, raw)
        print("    [%-7s] %s %s" % (mark, step.get("number"), step.get("name")))
'
}

echo "==> watching (Ctrl-C stops watching; the run keeps going)"
while true; do
  run_json="$(github_api GET "/repos/${REPOSITORY}/actions/runs/${RUN_ID}")"
  status="$(printf '%s' "$run_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status") or "")')"
  conclusion="$(printf '%s' "$run_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("conclusion") or "")')"
  stamp="${status}/${conclusion:-}"
  if [[ "$stamp" != "$last_stamp" ]]; then
    printf '  status=%s conclusion=%s\n' "$status" "${conclusion:--}"
    print_jobs || true
    last_stamp="$stamp"
  fi
  if [[ "$status" == "completed" ]]; then
    break
  fi
  if [[ "$(date +%s)" -gt "$deadline" ]]; then
    echo "timed out after ${TIMEOUT_MINUTES} minutes; run is still ${status}" >&2
    exit 2
  fi
  sleep "$POLL_SECONDS"
done

if [[ "$DOWNLOAD_LOGS" -eq 1 || "$conclusion" != "success" ]]; then
  mkdir -p tmp/ci-logs
  log_zip="tmp/ci-logs/${RUN_ID}-logs.zip"
  echo "==> downloading run logs -> $log_zip"
  github_download_artifact "https://api.github.com/repos/${REPOSITORY}/actions/runs/${RUN_ID}/logs" "$log_zip" || true
fi

if [[ "$conclusion" == "success" ]]; then
  echo "build succeeded"
  if [[ "$DOWNLOAD" -eq 1 ]]; then
    "${SCRIPT_DIR}/download-artifacts.sh" --run-id "$RUN_ID" --repo "$REPOSITORY"
  fi
  exit 0
fi

echo "build failed (conclusion=${conclusion})" >&2
print_jobs || true
echo "failed step logs: unzip -l tmp/ci-logs/${RUN_ID}-logs.zip  (pass --download-logs)" >&2
exit 1
