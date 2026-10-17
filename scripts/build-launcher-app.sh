#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
build_path="$repo_root/.build"
dist_dir="$repo_root/dist"
app_bundle="$dist_dir/Inlay.app"
info_plist_source="$repo_root/Resources/EarPodsLauncher/Info.plist"
config_source="$repo_root/config/launcher.example.json"
codex_home="${TMPDIR:-/tmp}/earpods-launcher-build-home"
clang_module_cache="${TMPDIR:-/tmp}/earpods-launcher-clang-module-cache"

mkdir -p "$codex_home" "$clang_module_cache"
export HOME="$codex_home"
export CLANG_MODULE_CACHE_PATH="$clang_module_cache"

if [[ ! -f "$info_plist_source" ]]; then
  echo "Missing Info.plist template at $info_plist_source" >&2
  exit 1
fi

if [[ ! -f "$config_source" ]]; then
  echo "Missing launcher config at $config_source" >&2
  exit 1
fi

swift build \
  --configuration release \
  --product earpods-launcher \
  --build-path "$build_path"

bin_dir="$(swift build --configuration release --show-bin-path --build-path "$build_path")"
binary_source="$bin_dir/earpods-launcher"

if [[ ! -x "$binary_source" ]]; then
  echo "Built launcher binary not found at $binary_source" >&2
  exit 1
fi

rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"

cp "$info_plist_source" "$app_bundle/Contents/Info.plist"
cp "$binary_source" "$app_bundle/Contents/MacOS/earpods-launcher"
cp "$config_source" "$app_bundle/Contents/Resources/launcher.example.json"
chmod +x "$app_bundle/Contents/MacOS/earpods-launcher"

echo "Built $app_bundle"
