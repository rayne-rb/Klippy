#!/usr/bin/env bash
# Verifies the Companion without a display.
#
# Two passes, because neither catches everything on its own:
#   1. a real headless run, which compiles every reachable script and executes
#      _ready on all of them, so wiring mistakes show up
#   2. a resource pass, which reloads the scripts the first pass may not reach and
#      confirms the scene, autoload and asset paths still resolve
set -uo pipefail

GODOT="${GODOT:-$HOME/Programs/godot-4.7.1/Godot_v4.7.1-stable_linux.x86_64}"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -x "$GODOT" ]]; then
  echo "Godot not found at $GODOT. Set GODOT to the binary." >&2
  exit 2
fi

echo "==> Importing"
"$GODOT" --headless --path "$PROJECT" --import >/dev/null 2>&1

echo "==> Running headless"
run_output="$("$GODOT" --headless --path "$PROJECT" --quit-after 120 2>&1 | grep -v 'ObjectDB instances')"
if grep -qE 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load' <<<"$run_output"; then
  echo "$run_output"
  echo "FAILED: errors during the headless run" >&2
  exit 1
fi
echo "    clean"

echo "==> Checking resources"
check_output="$("$GODOT" --headless --path "$PROJECT" --script tools/validate.gd 2>&1 | grep -v 'ObjectDB instances')"
echo "$check_output" | grep -vE '^\s*$'
if ! grep -q 'VALIDATION PASSED' <<<"$check_output"; then
  exit 1
fi

echo
echo "Companion OK"
