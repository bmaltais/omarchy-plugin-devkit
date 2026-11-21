#!/usr/bin/env bash
# Runs every tests/*.test.sh and says which failed. No Hyprland is needed: these test the guard, the config and the lint rules.
#
#   tests/run.sh [NAME...]     NAME selects tests whose file name contains it
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
# Tests never touch real input: bin/pointer refuses, and a test that calls a host tool it did not stub fails (the tripwire in lib.sh).
export DEVKIT_NO_REAL_INPUT=1
daemons() { pgrep -u "$UID" -x ydotoold | wc -l; }
before=$(daemons)
fail=0; n=0
for t in *.test.sh; do
  [[ $# -eq 0 ]] || { m=0; for w in "$@"; do [[ $t == *"$w"* ]] && m=1; done; ((m)) || continue; }
  n=$((n + 1))
  if out=$(bash "$t" 2>&1); then echo "  ok    $t"; else echo "  FAIL  $t"; printf '        %s\n' "${out//$'\n'/$'\n        '}"; fail=1; fi
done
after=$(daemons)
if ((after > before)); then echo "  FAIL  a test left a ydotoold running ($before before, $after after)"; fail=1; fi
echo "tests: $n files, $([[ $fail -eq 0 ]] && echo all passed || echo FAILED)"
exit $fail
