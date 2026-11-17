#!/bin/sh
# Build the web version and serve it on http://localhost:8000
set -e
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
mkdir -p export/web
"$GODOT" --headless --export-release Web export/web/index.html
exec python3 -m http.server -d export/web 8000
