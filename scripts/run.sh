#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CACHE_DIR="$ROOT_DIR/.cache"
SDK_PATH="${CSMATCH_SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"

if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" && -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
    SDK_PATH="${CSMATCH_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
fi

mkdir -p "$CACHE_DIR/clang" "$CACHE_DIR/swiftpm"
cd "$ROOT_DIR"
SDKROOT="$SDK_PATH" \
CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_DIR/clang" \
swift run --disable-sandbox --cache-path "$CACHE_DIR/swiftpm" CSMatchBar
