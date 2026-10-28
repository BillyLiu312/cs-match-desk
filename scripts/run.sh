#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"

# Bundle.main must point to the single canonical app bundle containing the icons
# and team logos. Debug builds reuse this path instead of creating a second app.
cd "$ROOT_DIR"
"$ROOT_DIR/scripts/build-app.sh" debug
exec "$ROOT_DIR/build/CS Match Desk.app/Contents/MacOS/CSMatchBar"
