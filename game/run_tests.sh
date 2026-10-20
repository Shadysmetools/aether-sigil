#!/usr/bin/env bash
# Runs every headless check. Godot exits 0 even on script errors, so each log is grepped.
# Usage: bash game/run_tests.sh   (from the repo root or anywhere)
cd "$(dirname "$0")"
G="${GODOT:-../engine/Godot_v4.7.2-stable_win64_console.exe}"
LOG="${TMPDIR:-/tmp}/aether_sigil_tests"; mkdir -p "$LOG"
status=0
run() { # name, args...
  local name=$1; shift
  "$G" --headless --path . "$@" > "$LOG/$name.txt" 2>&1
  local code=$?
  local errs; errs=$(grep -cE "SCRIPT ERROR|^ERROR|Parse Error" "$LOG/$name.txt")
  local summary; summary=$(grep -E "^[0-9]+ pass / [0-9]+ fail" "$LOG/$name.txt" | tail -1)
  printf "%-10s exit=%s script_errors=%s  %s\n" "$name" "$code" "$errs" "$summary"
  if [ "$errs" != "0" ]; then grep -E "SCRIPT ERROR|^ERROR|Parse Error" "$LOG/$name.txt" | head -5; status=1; fi
  if [ "$code" != "0" ]; then status=1; fi
}
run import --import
run data   --script res://tests/test_data.gd
run rules  --script res://tests/test_rules.gd
run ui     --script res://tests/test_ui_smoke.gd
run sim    --script res://tests/test_sim.gd
run main   --quit-after 120
echo "logs: $LOG"
exit $status
