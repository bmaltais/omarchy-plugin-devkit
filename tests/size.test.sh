#!/usr/bin/env bash
# nested_send_away: the window is floated with "on" (never the toggling "set"), and the session is refused unless the window is floating at
# WxH and the nested monitor is WxH. A stand-in hyprctl answers for both compositors; no Hyprland is needed.
source "$(dirname "$0")/lib.sh"

stubs=$WORK/stubs; mkdir -p "$stubs"
cat >"$stubs/hyprctl" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *dispatch*) echo "$*" >>"$HYPR_LOG" ;;
  *clients*) printf '[{"address":"0xabc","floating":%s,"size":[%s,%s]}]' "$FLOATING" "$WIN_W" "$WIN_H" ;;
  *monitors*) printf '[{"name":"WAYLAND-1","width":%s,"height":%s}]' "$MON_W" "$MON_H" ;;
esac
STUB
chmod +x "$stubs/hyprctl"

# shellcheck disable=SC2034 # read by lib/session.sh
{ TMP=$WORK/t; REPO=$WORK; W=1280; H=800; }
export HYPR_LOG=$WORK/hypr.log DEVKIT_SIZE_TRIES=2 DEV_WINDOW=1 PATH=$stubs:$PATH
# shellcheck source=../lib/session.sh
source "$KIT/lib/session.sh"
NEST=$WORK/nest; mkdir -p "$NEST"; NEST_ADDR=0xabc; NSIG=sig

try() { # FLOATING WIN_W WIN_H MON_W MON_H
  : >"$HYPR_LOG"; export FLOATING=$1 WIN_W=$2 WIN_H=$3 MON_W=$4 MON_H=$5
  nested_send_away 2>"$WORK/err"
}
check "size: floating at WxH on a WxH monitor is accepted" try true 1280 800 1280 800
check "size: ... and the monitor size is recorded" test "$NW x $NH" = "1280 x 800"
check "size: one pixel over is accepted, as before" try true 1280 801 1280 801
check "size: the window is floated with action on" grep -q 'float({ action = "on"' "$HYPR_LOG"
check "size: action set is never sent" bash -c '! grep -q "action = \"set\"" "$1"' _ "$HYPR_LOG"
check "size: exact is not sent (not a Hyprland field)" bash -c '! grep -q "exact" "$1"' _ "$HYPR_LOG"
check "size: the go file is made only on success" test -e "$NEST/go"
rm -f "$NEST/go"
# floating? window size, monitor size: a tiled window, the 819x492 re-float, a wrong monitor, a window two pixels over
for c in "false 1280 800 1280 800" "true 819 492 1280 800" "true 1280 800 819 492" "true 1280 802 1280 802"; do
  # shellcheck disable=SC2086 # the words are the arguments
  if try $c; then echo "FAILED: size: accepted ($c)"; fails=$((fails + 1)); fi  # floating, window WxH, monitor WxH
  check "size: the refusal says what it found ($c)" grep -q 'not the size asked for' "$WORK/err"
  check "size: no go file after a refusal ($c)" test ! -e "$NEST/go"
done
# Off the far monitor path (the default): the move is the silent one, and focus is not handed back.
DEV_WINDOW=0 FAR_MON=DEVTEST try true 1280 800 1280 800
check "size: the move to the far monitor is silent (follow = false)" grep -q 'window.move({ monitor = "DEVTEST", follow = false' "$HYPR_LOG"
check "size: focus is not handed back (it would warp the cursor)" bash -c '! grep -q "hl.dsp.focus" "$1"' _ "$HYPR_LOG"
finish
