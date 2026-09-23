#!/usr/bin/env bash
# Shared GitHub REST helpers for the macOS CI scripts.
#
# Source this file, then use github_token / github_api / github_download_artifact.
# Token order matches scripts/ci/remote-build-windows.ps1: --token, OPENMUSE_TOKEN,
# GH_TOKEN, GITHUB_TOKEN, then `gh auth token`.

github_token() {
  if [[ -n "${1:-}" ]]; then
    GITHUB_TOKEN_SOURCE='--token'
    printf '%s\n' "$1"
    return 0
  fi
  local name
  for name in OPENMUSE_TOKEN GH_TOKEN GITHUB_TOKEN; do
    if [[ -n "${!name:-}" ]]; then
      GITHUB_TOKEN_SOURCE="$name"
      printf '%s\n' "${!name}"
      return 0
    fi
  done
  if command -v gh >/dev/null 2>&1; then
    local from_gh
    from_gh="$(gh auth token 2>/dev/null | head -1 || true)"
    if [[ -n "$from_gh" ]]; then
      GITHUB_TOKEN_SOURCE='gh auth token'
      printf '%s\n' "$from_gh"
      return 0
    fi
  fi
  GITHUB_TOKEN_SOURCE=''
  return 1
}

github_api() {
  # github_api METHOD PATH [BODY]
  # PATH is /repos/... or a full https://api.github.com/... URL.
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local url
  if [[ "$path" == https://* ]]; then
    url="$path"
  else
    url="https://api.github.com${path}"
  fi
  local args=(
    -sS
    --fail-with-body
    -H "Authorization: token ${GITHUB_TOKEN}"
    -H "Accept: application/vnd.github+json"
    -H "User-Agent: openmuse-ci"
    -H "X-GitHub-Api-Version: 2022-11-28"
    -X "$method"
  )
  if [[ -n "$body" ]]; then
    args+=(-H "Content-Type: application/json" --data "$body")
  fi
  curl "${args[@]}" "$url"
}

github_api_code() {
  # Like github_api but prints HTTP status to stdout and body to GH_API_BODY.
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local url
  if [[ "$path" == https://* ]]; then
    url="$path"
  else
    url="https://api.github.com${path}"
  fi
  local tmp
  tmp="$(mktemp)"
  local args=(
    -sS
    -o "$tmp"
    -w '%{http_code}'
    -H "Authorization: token ${GITHUB_TOKEN}"
    -H "Accept: application/vnd.github+json"
    -H "User-Agent: openmuse-ci"
    -H "X-GitHub-Api-Version: 2022-11-28"
    -X "$method"
  )
  if [[ -n "$body" ]]; then
    args+=(-H "Content-Type: application/json" --data "$body")
  fi
  local code
  code="$(curl "${args[@]}" "$url")"
  GH_API_BODY="$(cat "$tmp")"
  rm -f "$tmp"
  printf '%s\n' "$code"
}

github_download_artifact() {
  # The artifact endpoint 302s to signed blob storage. Forwarding Authorization
  # to that host makes the storage service reject the request, so follow the
  # redirect without the token.
  local uri="$1"
  local dest="$2"
  local headers
  headers="$(mktemp)"
  curl -sS -D "$headers" -o /dev/null \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "User-Agent: openmuse-ci" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$uri"
  local location
  location="$(awk 'tolower($1)=="location:" {print $2; exit}' "$headers" | tr -d '\r')"
  rm -f "$headers"
  if [[ -n "$location" ]]; then
    curl -sS --fail -L -o "$dest" "$location"
    return
  fi
  curl -sS --fail -L \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "User-Agent: openmuse-ci" \
    -o "$dest" "$uri"
}

github_sha256sums_check() {
  local directory="$1"
  local sums="${directory}/SHA256SUMS.txt"
  if [[ ! -f "$sums" ]]; then
    return 2
  fi
  local failures=0
  local checked=0
  local skipped=0
  local line hash name path actual
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^([0-9a-fA-F]{64})[[:space:]]+\*?(.+)$ ]] || continue
    hash="${BASH_REMATCH[1]}"
    hash="$(printf '%s' "$hash" | tr 'A-F' 'a-f')"
    name="${BASH_REMATCH[2]}"
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    path="${directory}/${name}"
    if [[ ! -f "$path" ]]; then
      printf '    [skip] %s\n' "$name"
      skipped=$((skipped + 1))
      continue
    fi
    actual="$(shasum -a 256 "$path" | awk '{print $1}')"
    if [[ "$actual" == "$hash" ]]; then
      printf '    [ok  ] %s\n' "$name"
      checked=$((checked + 1))
    else
      printf '    [FAIL] %s\n' "$name"
      failures=$((failures + 1))
    fi
  done < "$sums"
  printf '    %s listed, %s verified, %s not part of the artifact' \
    "$((checked + skipped + failures))" "$checked" "$skipped"
  if [[ "$failures" -gt 0 ]]; then
    printf ', %s mismatched\n' "$failures"
    return 1
  fi
  printf '\n'
  return 0
}
