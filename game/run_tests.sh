#!/usr/bin/env bash
# Runs every headless check and FAILS (exit 1) unless all of these hold:
#   - no "SCRIPT ERROR" / "ERROR:" / "Parse Error" in any log (Godot exits 0 even on script errors)
#   - every test suite printed its "N pass / M fail" summary line, and M is 0
#   - every Godot process exited 0 and finished inside SUITE_TIMEOUT seconds
# Usage: bash game/run_tests.sh   (from anywhere)
cd "$(dirname "$0")"
G="${GODOT:-../engine/Godot_v4.7.2-stable_win64_console.exe}"
LOG="${TMPDIR:-/tmp}/aether_sigil_tests"; mkdir -p "$LOG"
status=0
total_pass=0
total_fail=0
run() { # name, needs_summary(yes|no), godot args...
  local name=$1 needs=$2; shift 2
  timeout "${SUITE_TIMEOUT:-590}" "$G" --headless --path . "$@" > "$LOG/$name.txt" 2>&1
  local code=$?
  local errs; errs=$(grep -cE "SCRIPT ERROR|^ERROR|Parse Error" "$LOG/$name.txt")
  local summary; summary=$(grep -E "^[0-9]+ pass / [0-9]+ fail" "$LOG/$name.txt" | tail -1)
  local verdict=ok
  if [ "$errs" != "0" ]; then verdict="FAIL(script errors)"; fi
  if [ "$code" != "0" ]; then verdict="FAIL(exit $code)"; fi
  if [ "$needs" = yes ]; then
    if [ -z "$summary" ]; then
      verdict="FAIL(no summary line)"
    else
      local p f
      p=$(echo "$summary" | sed -E 's/^([0-9]+) pass.*/\1/')
      f=$(echo "$summary" | sed -E 's/.* ([0-9]+) fail.*/\1/')
      total_pass=$((total_pass + p)); total_fail=$((total_fail + f))
      if [ "$f" != "0" ]; then verdict="FAIL($f failing)"; fi
    fi
  fi
  printf "%-7s %-22s exit=%s script_errors=%s  %s\n" "$name" "$verdict" "$code" "$errs" "$summary"
  if [ "$verdict" != ok ]; then
    status=1
    grep -E "SCRIPT ERROR|^ERROR|Parse Error|^  FAIL" "$LOG/$name.txt" | head -8
  fi
}
run import no  --import
run data   yes --script res://tests/test_data.gd
run rules  yes --script res://tests/test_rules.gd
run prog   yes --script res://tests/test_progression.gd
run story  yes --script res://tests/test_story.gd
run ui     yes --script res://tests/test_ui_smoke.gd
run sim    yes --script res://tests/test_sim.gd
run main   no  --quit-after 120
echo "TOTAL: $total_pass pass / $total_fail fail  ->  $([ $status = 0 ] && echo GREEN || echo RED)   (logs: $LOG)"
exit $status
