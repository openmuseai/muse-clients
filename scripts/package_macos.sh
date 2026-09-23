#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_root="$repo_root/app/openmuse_host"
dist_root="$repo_root/dist"
app_path="$app_root/build/macos/Build/Products/Release/OpenMuse.app"
archive_path="$dist_root/OpenMuse-macos.zip"
dsh_closure="$repo_root/target/dsh-closure"
node_runtime="$repo_root/target/node-v22.19.0-universal"

cd "$app_root"
"$repo_root/scripts/stage_helix.sh"
"$repo_root/scripts/stage_node_macos.sh"
if [[ ! -f "$dsh_closure/node_modules/@deepseek-ai/dsh/lib/bin.js" ]]; then
  python3 "$repo_root/scripts/build_dsh_closure.py" --out "$dsh_closure"
fi
cmp "$repo_root/third_party/dsh/package.json" "$dsh_closure/package.json"
cmp "$repo_root/third_party/dsh/package-lock.json" "$dsh_closure/package-lock.json"
python3 "$repo_root/scripts/build_dsh_closure.py" --out "$dsh_closure" --validate-only
if [[ "${OPENMUSE_CLEAN_BUILD:-1}" == "1" ]]; then
  flutter clean
fi
flutter pub get
flutter analyze
flutter test
flutter build macos --release

test -d "$app_path"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
test "$bundle_id" = "com.openmuseai.office"

bundled_helix="$app_path/Contents/Frameworks/App.framework/Resources/flutter_assets/packages/openmuse_helix_plugin/assets/engines/helix"
test -f "$bundled_helix/hx"
# Stage only the editor runtime needed by this distribution. Bundling every
# upstream theme would pull unrelated theme licenses into the product.
rsync -a --delete-excluded \
  --include='/languages.toml' \
  --include='/grammars/***' \
  --include='/queries/***' \
  --include='/themes/' \
  --include='/themes/onelight.toml' \
  --include='/themes/openmuse_dark.toml' \
  --exclude='*' \
  "$repo_root/plugins/helix/assets/engines/helix/runtime/" "$bundled_helix/runtime/"
test -f "$bundled_helix/runtime/themes/onelight.toml"
test -f "$bundled_helix/runtime/themes/openmuse_dark.toml"
test -f "$bundled_helix/config.toml"

test -x "$node_runtime/node"
test -f "$node_runtime/LICENSE"
test -f "$repo_root/third_party/dsh/LICENSE"
dsh_dest="$app_path/Contents/Resources/openmuse/dsh"
mkdir -p "$dsh_dest/node_modules" "$dsh_dest/node/bin" "$dsh_dest/licenses"
rsync -a --delete "$dsh_closure/node_modules/" "$dsh_dest/node_modules/"
install -m 755 "$node_runtime/node" "$dsh_dest/node/bin/node"
cp "$repo_root/third_party/dsh/LICENSE" "$dsh_dest/licenses/DSH-LICENSE"
cp "$node_runtime/LICENSE" "$dsh_dest/licenses/NODE-LICENSE"
"$dsh_dest/node/bin/node" "$dsh_dest/node_modules/@deepseek-ai/dsh/lib/bin.js" --version
codesign --force --sign - "$dsh_dest/node/bin/node"

mkdir -p "$dist_root"
# Flutter's incremental macOS build can update App.framework without refreshing
# the outer ad-hoc app seal. Refresh only ad-hoc signatures; never replace a
# Developer ID signature here.
app_framework="$app_path/Contents/Frameworks/App.framework"
if ! codesign --verify --strict "$app_framework" >/dev/null 2>&1; then
  framework_signature="$(codesign -dv "$app_framework" 2>&1)"
  if [[ "$framework_signature" == *'Signature=adhoc'* ]]; then
    codesign --force --sign - "$app_framework"
  fi
fi
if ! codesign --verify --deep --strict "$app_path" >/dev/null 2>&1; then
  signature_details="$(codesign -dv "$app_path" 2>&1)"
  if [[ "$signature_details" == *'Signature=adhoc'* ]]; then
    codesign --force --sign - "$app_path"
  fi
fi
codesign --verify --deep --strict "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
echo "$archive_path"
