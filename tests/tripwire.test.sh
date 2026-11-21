#!/usr/bin/env bash
# The tripwire in lib.sh: a test that calls a host tool it did not stub fails, and one that stubs it does not.
source "$(dirname "$0")/lib.sh"

# Each case is a throwaway test script run on its own; its own finish() decides, as in a real test.
case_test() { printf '#!/usr/bin/env bash\nsource %q\n%s\nfinish\n' "$KIT/tests/lib.sh" "$1" >"$WORK/case.test.sh"; bash "$WORK/case.test.sh" 2>&1; }
for tool in ydotool ydotoold hyprctl wtype grim Hyprland quickshell omarchy-shell notify-send sway swaymsg; do
  out=$(case_test "$tool --arg >/dev/null 2>&1 || true"); rc=$?
  check "tripwire: a call to $tool fails the test" test "$rc" -ne 0
  check "tripwire: ... and names $tool" bash -c "[[ \$1 == *'$tool --arg'* ]]" _ "$out"
done
check "tripwire: a tool called directly exits 97" bash -c "PATH='$TRIPWIRE':\$PATH TRIPWIRE_LOG='$WORK/direct.log' ydotool x >/dev/null 2>&1; [[ \$? == 97 ]]"
check "tripwire: a test that stubs the tool ahead of it passes" case_test 'mkdir "$WORK/s"; printf "#!/bin/sh\nexit 0\n" >"$WORK/s/hyprctl"; chmod +x "$WORK/s/hyprctl"; PATH=$WORK/s:$PATH hyprctl monitors'
check "tripwire: a test that calls nothing passes" case_test 'true'
check "tripwire: the tests run with DEVKIT_NO_REAL_INPUT=1" test "$DEVKIT_NO_REAL_INPUT" = 1
finish
