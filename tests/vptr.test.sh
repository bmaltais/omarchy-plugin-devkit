#!/usr/bin/env bash
# lib/vptr.c refuses a socket that is not a nested compositor's. Only the refusals that need no compositor are tested here (an empty or
# the host's WAYLAND_DISPLAY, a socket that does not exist); the output-name check needs a compositor, and the only one around is the real one.
source "$(dirname "$0")/lib.sh"

for t in gcc wayland-scanner pkg-config; do command -v "$t" >/dev/null || { echo "vptr.test.sh: skipped ($t is not installed)"; finish; exit; }; done
pkg-config --exists wayland-client || { echo "vptr.test.sh: skipped (no wayland-client)"; finish; exit; }
"$KIT/lib/build-vptr.sh" "$WORK/bin" >/dev/null 2>&1 || { echo "FAILED: vptr does not build"; exit 1; }
v=$WORK/bin/vptr
rc() { env XDG_RUNTIME_DIR="$WORK" "$@" >/dev/null 2>&1; echo $?; }   # the runtime dir is empty: no socket of the real session can be reached

check "vptr: no WAYLAND_DISPLAY is refused (3)" test "$(rc env -u WAYLAND_DISPLAY "$v" probe)" = 3
check "vptr: an empty WAYLAND_DISPLAY is refused (3)" test "$(rc WAYLAND_DISPLAY= "$v" click 1 1 100 100)" = 3
check "vptr: the host's own socket is refused (3)" test "$(rc WAYLAND_DISPLAY=wayland-9 DEVKIT_HOST_WAYLAND_DISPLAY=wayland-9 "$v" click 1 1 100 100)" = 3
check "vptr: a socket that is not there is an error, not a success" test "$(rc WAYLAND_DISPLAY=wayland-77 "$v" probe)" = 1
check "vptr: wrong arguments are usage (2)" test "$(rc WAYLAND_DISPLAY=wayland-77 "$v" click 1)" = 2
finish
