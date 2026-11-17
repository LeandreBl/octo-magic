#!/bin/sh
# Project test command. GODOT can point to the Godot 4 binary.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1 || true
code=0
for t in tests/test_*.gd; do
	# Godot keeps running after a compile error: bound each script in time.
	out=$(timeout 300 "$GODOT" --headless --script "$t" 2>&1) || code=1
	echo "$out"
	# Godot keeps running after script errors: treat any as a failure.
	if echo "$out" | grep -q "SCRIPT ERROR"; then code=1; fi
done
python3 -m unittest discover -s server -p "test_*.py" -q
exit $code
