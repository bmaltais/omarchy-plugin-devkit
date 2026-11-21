#!/usr/bin/env bash
# lib/vptr.c refuses a socket that is not a nested compositor's. Only the refusals that need no compositor are tested here (an empty or
# the host's WAYLAND_DISPLAY, a socket that does not exist); the output-name check needs a compositor, and the only one around is the real one.
source "$(dirname "$0")/lib.sh"

for t in gcc wayland-scanner pkg-config; do command -v "$t" >/dev/null || { echo "vptr.test.sh: skipped ($t is not installed)"; # The output names a nested compositor has: HEADLESS-n (the headless backend's sway) and WAYLAND-n are accepted, a real output is not.
check "vptr: HEADLESS-1 and HEADLESS-12 are nested outputs" test "$(rc "$v" names HEADLESS-1 HEADLESS-12)" = 0
check "vptr: WAYLAND-1 is a nested output" test "$(rc "$v" names WAYLAND-1)" = 0
for n in eDP-1 DP-2 HDMI-A-1 HEADLESS- HEADLESS-1x headless-1 ""; do
  check "vptr: '$n' is not a nested output (3)" test "$(rc "$v" names HEADLESS-1 "$n")" = 3
done
# The headless backend gives vptr the folder the socket must be in.
only=$WORK/private; mkdir -p "$only"
check "vptr: a socket by name is refused when it must be under a folder (3)" test "$(rc WAYLAND_DISPLAY=wayland-1 DEVKIT_ONLY_SOCKET_UNDER="$only" "$v" probe)" = 3
check "vptr: a socket in another folder is refused (3)" test "$(rc WAYLAND_DISPLAY=/run/user/1000/wayland-1 DEVKIT_ONLY_SOCKET_UNDER="$only" "$v" probe)" = 3
check "vptr: a path that climbs out of the folder is refused (3)" test "$(rc WAYLAND_DISPLAY="$only/../wayland-1" DEVKIT_ONLY_SOCKET_UNDER="$only" "$v" probe)" = 3
check "vptr: a socket inside the folder is let through to the connection (1: nothing there)" test "$(rc WAYLAND_DISPLAY="$only/wayland-1" DEVKIT_ONLY_SOCKET_UNDER="$only" "$v" probe)" = 1
finish; exit; }; done
pkg-config --exists wayland-client || { echo "vptr.test.sh: skipped (no wayland-client)"; # The output names a nested compositor has: HEADLESS-n (the headless backend's sway) and WAYLAND-n are accepted, a real output is not.
check "vptr: HEADLESS-1 and HEADLESS-12 are nested outputs" test "$(rc "$v" names HEADLESS-1 HEADLESS-12)" = 0
check "vptr: WAYLAND-1 is a nested output" test "$(rc "$v" names WAYLAND-1)" = 0
for n in eDP-1 DP-2 HDMI-A-1 HEADLESS- HEADLESS-1x headless-1 ""; do
  check "vptr: '$n' is not a nested output (3)" test "$(rc "$v" names HEADLESS-1 "$n")" = 3
done
# The headless backend gives vptr the folder the socket must be in.
only=$WORK/private; mkdir -p "$only"
check "vptr: a socket by name is refused when it must be under a folder (3)" test "$(rc WAYLAND_DISPLAY=wayland-1 DEVKIT_ONLY_SOCKET_UNDER="$only" "$v" probe)" = 3
check "vptr: a socket in another folder is refused (3)" test "$(rc WAYLAND_DISPLAY=/run/user/1000/wayland-1 DEVKIT_ONLY_SOCKET_UNDER="$only" "$v" probe)" = 3
check "vptr: a path that climbs out of the folder is refused (3)" test "$(rc WAYLAND_DISPLAY="$only/../wayland-1" DEVKIT_ONLY_SOCKET_UNDER="$only" "$v" probe)" = 3
check "vptr: a socket inside the folder is let through to the connection (1: nothing there)" test "$(rc WAYLAND_DISPLAY="$only/wayland-1" DEVKIT_ONLY_SOCKET_UNDER="$only" "$v" probe)" = 1
finish; exit; }
"$KIT/lib/build-vptr.sh" "$WORK/bin" >/dev/null 2>&1 || { echo "FAILED: vptr does not build"; exit 1; }
v=$WORK/bin/vptr
rc() { env XDG_RUNTIME_DIR="$WORK" "$@" >/dev/null 2>&1; echo $?; }   # the runtime dir is empty: no socket of the real session can be reached

check "vptr: no WAYLAND_DISPLAY is refused (3)" test "$(rc env -u WAYLAND_DISPLAY "$v" probe)" = 3
check "vptr: an empty WAYLAND_DISPLAY is refused (3)" test "$(rc WAYLAND_DISPLAY= "$v" click 1 1 100 100)" = 3
check "vptr: the host's own socket is refused (3)" test "$(rc WAYLAND_DISPLAY=wayland-9 DEVKIT_HOST_WAYLAND_DISPLAY=wayland-9 "$v" click 1 1 100 100)" = 3
check "vptr: a socket that is not there is an error, not a success" test "$(rc WAYLAND_DISPLAY=wayland-77 "$v" probe)" = 1
check "vptr: wrong arguments are usage (2)" test "$(rc WAYLAND_DISPLAY=wayland-77 "$v" click 1)" = 2
# The output names a nested compositor has: HEADLESS-n (the headless backend's sway) and WAYLAND-n are accepted, a real output is not.
check "vptr: HEADLESS-1 and HEADLESS-12 are nested outputs" test "$(rc "$v" names HEADLESS-1 HEADLESS-12)" = 0
check "vptr: WAYLAND-1 is a nested output" test "$(rc "$v" names WAYLAND-1)" = 0
for n in eDP-1 DP-2 HDMI-A-1 HEADLESS- HEADLESS-1x headless-1 ""; do
  check "vptr: '$n' is not a nested output (3)" test "$(rc "$v" names HEADLESS-1 "$n")" = 3
done
# The headless backend gives vptr the folder the socket must be in.
only=$WORK/private; mkdir -p "$only"
check "vptr: a socket by name is refused when it must be under a folder (3)" test "$(rc WAYLAND_DISPLAY=wayland-1 DEVKIT_ONLY_SOCKET_UNDER="$only" "$v" probe)" = 3
check "vptr: a socket in another folder is refused (3)" test "$(rc WAYLAND_DISPLAY=/run/user/1000/wayland-1 DEVKIT_ONLY_SOCKET_UNDER="$only" "$v" probe)" = 3
check "vptr: a path that climbs out of the folder is refused (3)" test "$(rc WAYLAND_DISPLAY="$only/../wayland-1" DEVKIT_ONLY_SOCKET_UNDER="$only" "$v" probe)" = 3
check "vptr: a socket inside the folder is let through to the connection (1: nothing there)" test "$(rc WAYLAND_DISPLAY="$only/wayland-1" DEVKIT_ONLY_SOCKET_UNDER="$only" "$v" probe)" = 1
finish
