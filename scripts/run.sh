#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"

# Bundle.main must point to an app bundle containing the icons and team logos.
cd "$ROOT_DIR"
"$ROOT_DIR/scripts/build-app.sh" debug
exec "$ROOT_DIR/build/debug/CS Match Desk.app/Contents/MacOS/CSMatchBar"
