#!/bin/sh
# Build the web version into web/godot (not in git), served by the backend
# on /game (`cd backend && npm run start:dev`).
set -e
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
mkdir -p web/godot
"$GODOT" --headless --export-release Web web/godot/index.html
