#!/bin/sh
# Project test command. GODOT can point to the Godot 4 binary.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1 || true
out=$("$GODOT" --headless --script tests/test_spell.gd 2>&1) && code=0 || code=$?
echo "$out"
# Godot keeps running after script errors: treat any as a failure.
if echo "$out" | grep -q "SCRIPT ERROR"; then exit 1; fi
python3 -m unittest discover -s server -p "test_*.py" -q
exit $code
