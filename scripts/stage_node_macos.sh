#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_root="$repo_root/third_party/node/v22.19.0"
output_root="$repo_root/target/node-v22.19.0-universal"
checksums="$source_root/SHASUMS256.txt"

test -f "$checksums"
for arch in arm64 x64; do
  filename="node-v22.19.0-darwin-$arch.tar.gz"
  archive="$source_root/$filename"
  test -f "$archive"
  expected="$(awk -v filename="$filename" '$2 == filename { print $1 }' "$checksums")"
  test -n "$expected"
  actual="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
  if [[ "$actual" != "$expected" ]]; then
    echo "Node archive checksum mismatch: $archive" >&2
    exit 1
  fi
done

mkdir -p "$output_root/extracted"
tar -xzf "$source_root/node-v22.19.0-darwin-arm64.tar.gz" -C "$output_root/extracted"
tar -xzf "$source_root/node-v22.19.0-darwin-x64.tar.gz" -C "$output_root/extracted"
/usr/bin/lipo -create \
  "$output_root/extracted/node-v22.19.0-darwin-x64/bin/node" \
  "$output_root/extracted/node-v22.19.0-darwin-arm64/bin/node" \
  -output "$output_root/node"
cp "$output_root/extracted/node-v22.19.0-darwin-arm64/LICENSE" "$output_root/LICENSE"
test "$(/usr/bin/lipo -archs "$output_root/node")" = "x86_64 arm64"
"$output_root/node" --version
