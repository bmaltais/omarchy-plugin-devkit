# shellcheck shell=bash
# Helpers for the tests: a tiny assertion set, a throwaway folder removed at the end, and a tripwire.
#
# The tripwire: a folder first on PATH holds a stand-in for every tool that reaches the host (input, compositor, shell, notifications). Each one
# logs its call and exits 97, and finish() fails if anything was logged. A test that means to use one of these tools puts its own stub
# ahead of the tripwire (PATH=$stubs:$PATH) and so can never fall through to the real one: a test run must not move your real pointer.
KIT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export DEVKIT_NO_REAL_INPUT=1
TRIPWIRE=$WORK/tripwire; TRIPWIRE_LOG=$WORK/tripwire.log
export TRIPWIRE_LOG
mkdir -p "$TRIPWIRE"; : >"$TRIPWIRE_LOG"
for t in ydotool ydotoold hyprctl wtype grim Hyprland quickshell omarchy-shell notify-send sway swaymsg; do
  printf '#!/bin/sh\necho "%s $*" >>"$TRIPWIRE_LOG"\necho "tripwire: a test called the real %s" >&2\nexit 97\n' "$t" "$t" >"$TRIPWIRE/$t"
  chmod +x "$TRIPWIRE/$t"
done
export PATH=$TRIPWIRE:$PATH
fails=0
ok() { :; }
check() { # DESCRIPTION CONDITION-COMMAND...
  local what=$1; shift
  if "$@"; then ok; else echo "FAILED: $what"; fails=$((fails + 1)); fi
}
finish() {
  if [[ -s $TRIPWIRE_LOG ]]; then
    echo "FAILED: the test called tools that reach the host (stub them in the test):"
    sed 's/^/    /' "$TRIPWIRE_LOG"
    fails=$((fails + 1))
  fi
  ((fails == 0))
}
