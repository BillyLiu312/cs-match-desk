#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CACHE_DIR="$ROOT_DIR/.cache"
SDK_PATH="${CSMATCH_SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"

if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" && -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
    SDK_PATH="${CSMATCH_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
fi

mkdir -p "$CACHE_DIR/clang"
swiftc \
    -sdk "$SDK_PATH" \
    -module-cache-path "$CACHE_DIR/clang" \
    "$ROOT_DIR/Sources/CSMatchBar/Match.swift" \
    "$ROOT_DIR/Tests/MatchChecks.swift" \
    -o "$CACHE_DIR/MatchChecks"
"$CACHE_DIR/MatchChecks"

swiftc \
    -sdk "$SDK_PATH" \
    -module-cache-path "$CACHE_DIR/clang" \
    "$ROOT_DIR/Sources/CSMatchBar/DouyuRoomStatus.swift" \
    "$ROOT_DIR/Sources/CSMatchBar/DouyuLiveStore.swift" \
    "$ROOT_DIR/Tests/DouyuLiveChecks.swift" \
    -o "$CACHE_DIR/DouyuLiveChecks"
"$CACHE_DIR/DouyuLiveChecks"

swiftc \
    -sdk "$SDK_PATH" \
    -module-cache-path "$CACHE_DIR/clang" \
    "$ROOT_DIR/Sources/CSMatchBar/Match.swift" \
    "$ROOT_DIR/Sources/CSMatchBar/MatchNotifications.swift" \
    "$ROOT_DIR/Sources/CSMatchBar/FollowedMatchesStore.swift" \
    "$ROOT_DIR/Tests/FollowedMatchesChecks.swift" \
    -o "$CACHE_DIR/FollowedMatchesChecks"
"$CACHE_DIR/FollowedMatchesChecks"
