#!/bin/sh
# Local development (docker-compose.override.yml): re-exports the web game
# whenever the repository (mounted read-only on /repo) changes, into /out,
# which the server serves under /godot. A refresh (F5) loads the new export.
#
# The repository is mirrored into /src so Godot's import cache (.godot,
# *.import) stays in the container and never touches the host's.
# ponytail: polls with rsync every second, fine for this repo's size.
mkdir -p /out
first=yes
while :; do
  changes=$first$(rsync -a --delete -i \
    --exclude=/.git --exclude=/.godot --exclude='*.import' --exclude=/export \
    --exclude=/backend --exclude=/web/godot --exclude=node_modules --exclude=__pycache__ \
    /repo/ /src/)
  if [ -n "$changes" ]; then
    echo "change seen, exporting..."
    godot --headless --import >/dev/null 2>&1
    rm -rf /tmp/web && mkdir -p /tmp/web
    if godot --headless --export-release Web /tmp/web/index.html >/tmp/export.log 2>&1 \
      && [ -f /tmp/web/index.pck ]; then
      cp /tmp/web/* /out/ && echo "exported: refresh the game (F5)"
    else
      tail -n 30 /tmp/export.log; echo "export failed, the previous one stays"
    fi
  fi
  first=
  sleep 1
done
