#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-release}"
if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
    echo "Usage: $0 [debug|release]" >&2
    exit 1
fi

BUILD_DIR="$ROOT_DIR/build"
if [[ "$CONFIGURATION" == "debug" ]]; then
    BUILD_DIR="$BUILD_DIR/debug"
fi
APP_DIR="$BUILD_DIR/CS Match Desk.app"
CONTENTS_DIR="$APP_DIR/Contents"
CACHE_DIR="$ROOT_DIR/.cache"

SDK_PATH="${CSMATCH_SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" && -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
    SDK_PATH="${CSMATCH_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
fi

cd "$ROOT_DIR"
mkdir -p "$CACHE_DIR/clang" "$CACHE_DIR/swiftpm"
SDKROOT="$SDK_PATH" \
CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_DIR/clang" \
swift build -c "$CONFIGURATION" --disable-sandbox --cache-path "$CACHE_DIR/swiftpm"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$ROOT_DIR/.build/$CONFIGURATION/CSMatchBar" "$CONTENTS_DIR/MacOS/CSMatchBar"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/MenuBarIcon@2x.png" "$CONTENTS_DIR/Resources/MenuBarIcon@2x.png"
cp "$ROOT_DIR/Resources/HeaderIcon@2x.jpg" "$CONTENTS_DIR/Resources/HeaderIcon@2x.jpg"
ditto "$ROOT_DIR/Resources/OriginalTeamLogos" "$CONTENTS_DIR/Resources/TeamLogos"
ditto "$ROOT_DIR/Resources/DarkTeamLogos" "$CONTENTS_DIR/Resources/TeamLogosDark"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
