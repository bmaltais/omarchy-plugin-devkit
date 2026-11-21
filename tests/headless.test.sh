#!/usr/bin/env bash
# The headless backend (lib/headless.sh), with stand-ins for sway, swaymsg and dbus-run-session (all three are tripwired): the backend
# choice, sway's generated config, the environment sway is started with (none of your compositor's variables), the start and stop
# sequence, the window check, the ledger's sway entry, and the canary's comparison. No compositor is needed.
source "$(dirname "$0")/lib.sh"
# shellcheck source=../lib/config.sh
source "$KIT/lib/config.sh"

app=$WORK/MyApp; mkdir -p "$app/bin"
printf '#!/bin/sh\nexit 0\n' >"$app/bin/myapp"; chmod +x "$app/bin/myapp"
conf() { printf '# shellcheck shell=bash\n%s\n' "$1" >"$app/devkit.conf"; }
backend() { ( DEVKIT_APP_ROOT=$app; devkit_load_config >/dev/null 2>&1 && echo "$DEVKIT_BACKEND_RESOLVED" ) ; }
fails_to_load() { ! ( DEVKIT_APP_ROOT=$app; devkit_load_config ) >/dev/null 2>&1; }

# --- which backend
conf 'DEVKIT_APP_CMD=(bin/myapp)'
check "an app is headless by default" test "$(backend)" = headless
conf 'DEVKIT_APP_CMD=(bin/myapp)
DEVKIT_BACKEND=hyprland'
check "the conf can ask for hyprland" test "$(backend)" = hyprland
check "the environment beats the conf" bash -c "DEVKIT_BACKEND=headless; source '$KIT/lib/config.sh'; DEVKIT_APP_ROOT='$app'; devkit_load_config >/dev/null 2>&1 && [[ \$DEVKIT_BACKEND_RESOLVED == headless ]]"
conf 'TOUR_PLUGIN_ID=io.x.y'
check "a plugin is hyprland by default" test "$(backend)" = hyprland
conf 'TOUR_PLUGIN_ID=io.x.y
DEVKIT_BACKEND=headless'
check "a plugin cannot use the headless backend" fails_to_load
conf 'DEVKIT_APP_CMD=(bin/myapp)
DEVKIT_BACKEND=weston'
check "an unknown backend is refused" fails_to_load

# --- the session, as lib/session.sh sets it up
conf 'DEVKIT_APP_CMD=(bin/myapp)
DEVKIT_NAME=hltest'
TMP=$WORK/tmp; mkdir -p "$TMP"
W=1280; H=800
export XDG_RUNTIME_DIR=$WORK/run LEDGER_DIR=$WORK/ledgers
mkdir -p "$XDG_RUNTIME_DIR"
# shellcheck source=../lib/session.sh
source "$KIT/lib/session.sh"
DEVKIT_APP_ROOT=$app devkit_load_config
REPO=$app
mkdir -p "$NEST" "$NEST_HOME" "$NEST_BIN"
check "headless is on for the app" devkit_headless

# --- sway's config
headless_conf_write
conf_text=$(<"$NEST/sway.conf")
check "config: one HEADLESS-1 output at the size asked for" grep -qx 'output HEADLESS-1 mode 1280x800' <<<"$conf_text"
check "config: no borders, no gaps, no Xwayland" bash -c 'f=$1; grep -qx "default_border none" "$f" && grep -qx "gaps inner 0" "$f" && grep -qx "xwayland disable" "$f"' _ "$NEST/sway.conf"
check "config: no bar" bash -c '! grep -q "^bar" "$1"' _ "$NEST/sway.conf"
check "config: a plain background" grep -q '^output \* bg #262a36 solid_color' <<<"$conf_text"
W=1920; H=1080; headless_conf_write
check "config: another size" grep -qx 'output HEADLESS-1 mode 1920x1080' "$NEST/sway.conf"
W=1280; H=800

# --- the environment sway gets: your compositor's variables are gone, the headless backend is on
mkdir -p "$(headless_rt)"; chmod 700 "$(headless_rt)"
host_env=(WAYLAND_DISPLAY=wayland-1 DISPLAY=:0 HYPRLAND_INSTANCE_SIGNATURE=abc HYPRLAND_CMD=Hyprland SWAYSOCK=/x I3SOCK=/x DBUS_SESSION_BUS_ADDRESS=unix:path=/x WAYLAND_SOCKET=3)
envs() { ( export "${host_env[@]}"; headless_env_build; "${HEADLESS_ENV[@]}" env ); }
out=$(envs)
for v in WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE HYPRLAND_CMD SWAYSOCK I3SOCK DBUS_SESSION_BUS_ADDRESS WAYLAND_SOCKET; do
  check "env: $v is unset in sway's environment" bash -c "! grep -q '^$v=' <<<\"\$1\"" _ "$out"
done
check "env: WLR_BACKENDS=headless" grep -qx 'WLR_BACKENDS=headless' <<<"$out"
check "env: no libinput devices, the pixman renderer" bash -c "grep -qx 'WLR_LIBINPUT_NO_DEVICES=1' <<<\"\$1\" && grep -qx 'WLR_RENDERER=pixman' <<<\"\$1\"" _ "$out"
check "env: a private runtime dir" grep -qx "XDG_RUNTIME_DIR=$(headless_rt)" <<<"$out"
check "assert: a clean environment passes" bash -c "$(declare -f headless_assert_clean headless_env_build headless_rt); HEADLESS_UNSET=(${HEADLESS_UNSET[*]}); NEST='$NEST'; export ${host_env[*]}; headless_assert_clean"
# A build that forgets to remove one is refused, and so is a runtime dir that is not 0700.
check "assert: a variable that is still set is refused" bash -c "$(declare -f headless_assert_clean headless_rt); headless_env_build() { HEADLESS_ENV=(env XDG_RUNTIME_DIR='$(headless_rt)' WLR_BACKENDS=headless); }; HEADLESS_UNSET=(HYPRLAND_INSTANCE_SIGNATURE); NEST='$NEST'; export HYPRLAND_INSTANCE_SIGNATURE=abc; ! headless_assert_clean 2>/dev/null"
chmod 755 "$(headless_rt)"
check "assert: a runtime dir that is not 0700 is refused" bash -c "$(declare -f headless_assert_clean headless_env_build headless_rt); HEADLESS_UNSET=(${HEADLESS_UNSET[*]}); NEST='$NEST'; ! headless_assert_clean 2>/dev/null"
rm -rf "$(headless_rt)"

# --- start and stop, against stand-ins
stubs=$WORK/stubs; mkdir -p "$stubs"
cat >"$stubs/dbus-run-session" <<'STUB'
#!/usr/bin/env bash
# What a session manager does for sway here: records its environment and arguments, and leaves the two sockets sway would make.
env >"$STUB_LOG.env"; echo "$@" >"$STUB_LOG.args"
python3 -c '
import socket, sys, os
rt = os.environ["XDG_RUNTIME_DIR"]
for n in ("sway-ipc.1000.4242.sock", "wayland-1"):
    s = socket.socket(socket.AF_UNIX); s.bind(os.path.join(rt, n)); s.close()
'
STUB
cat >"$stubs/swaymsg" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$STUB_LOG.swaymsg"
case "$*" in
  *get_version*) echo '{}' ;;
  *get_outputs*) echo "[{\"name\":\"HEADLESS-1\",\"active\":true,\"current_mode\":{\"width\":${STUB_W:-1280},\"height\":${STUB_H:-800}}}]" ;;
  *get_tree*) cat "$STUB_TREE" ;;
esac
STUB
chmod +x "$stubs/dbus-run-session" "$stubs/swaymsg"
export STUB_LOG=$WORK/stub STUB_TREE=$WORK/tree.json
printf '#!/bin/sh\nexit 0\n' >"$stubs/sway"; chmod +x "$stubs/sway"
PATH=$stubs:$PATH   # from here the stand-ins are in front of the tripwire
vptr_build() { :; }
ledger_start none
( export "${host_env[@]}"; headless_start ) >/dev/null 2>"$WORK/start.err"
rc=$?
# The state a start leaves is set in its own shell: redo it here from what it made.
check "start: succeeds against the stand-ins" test "$rc" -eq 0
check "start: sway is run under dbus-run-session with the generated config" grep -q -- "-- sway -c $NEST/sway.conf" "$STUB_LOG.args"
check "start: the environment sway was given has none of your compositor's variables" bash -c "! grep -qE '^(WAYLAND_DISPLAY|DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|HYPRLAND_CMD|SWAYSOCK|DBUS_SESSION_BUS_ADDRESS)=' '$STUB_LOG.env'"
check "start: ... and WLR_BACKENDS=headless and a private runtime dir" bash -c "grep -qx WLR_BACKENDS=headless '$STUB_LOG.env' && grep -qx 'XDG_RUNTIME_DIR=$NEST/rt' '$STUB_LOG.env'"
check "start: the private runtime dir is 0700" test "$(stat -c %a "$NEST/rt")" = 700
check "start: swaymsg is always given the session's socket" bash -c "! grep -v -- '^-s $NEST/rt/sway-ipc.1000.4242.sock ' '$STUB_LOG.swaymsg'"
check "start: the app is started through sway, after the size is right" grep -q "exec '$NEST_BIN/app-launch'" "$STUB_LOG.swaymsg"
check "ledger: the sway process and the private runtime dir are written down" bash -c "grep -qx 'sway 4242' '$LEDGER' && grep -qx 'dir $NEST/rt' '$LEDGER'"
# A screen of the wrong size is refused.
( STUB_W=1280 STUB_H=720; export STUB_W STUB_H; NSWAY=$NEST/rt/sway-ipc.1000.4242.sock; DEVKIT_APP_MODE=1; headless_verify_size ) >/dev/null 2>&1
check "a screen of another size is refused" test "$?" -ne 0

# --- socket guard: only the session's own socket, and only by its private path
NWD=$NEST/rt/wayland-1; NSWAY=$NEST/rt/sway-ipc.1000.4242.sock
check "client: runs with the session's socket and runtime dir, without your compositor's variables" bash -c "$(declare -f headless_client headless_rt); NEST='$NEST'; NWD='$NWD'; NSWAY='$NSWAY'; export HYPRLAND_INSTANCE_SIGNATURE=abc DISPLAY=:0; out=\$(headless_client env); grep -qx 'WAYLAND_DISPLAY=$NWD' <<<\"\$out\" && grep -qx 'XDG_RUNTIME_DIR=$NEST/rt' <<<\"\$out\" && ! grep -q '^HYPRLAND_INSTANCE_SIGNATURE=' <<<\"\$out\" && ! grep -q '^DISPLAY=' <<<\"\$out\""
check "client: a socket outside the private dir is refused" bash -c "$(declare -f headless_client headless_rt); NEST='$NEST'; NWD=/run/user/1000/wayland-1; NSWAY=x; ! headless_client true 2>/dev/null"
check "client: no socket is refused" bash -c "$(declare -f headless_client headless_rt); NEST='$NEST'; NWD=''; ! headless_client true 2>/dev/null"

# --- the app's window
cat >"$WORK/tree.json" <<'JSON'
{"type":"root","nodes":[{"type":"output","name":"HEADLESS-1","nodes":[{"type":"workspace","name":"1","nodes":[
 {"type":"con","pid":777,"app_id":"fugue","name":"Fugue - demo","nodes":[],"floating_nodes":[]}],"floating_nodes":[
 {"type":"floating_con","pid":778,"app_id":null,"window_properties":{"class":"Other"},"name":"x","nodes":[],"floating_nodes":[]}]}]}]}
JSON
win() { ( DEVKIT_APP_CLASS=$1; DEVKIT_APP_TITLE=$2; headless_window_up ); }
check "window: no class or title matches any window" win "" ""
check "window: the app id matches" win '^fugue$' ""
check "window: the X11 class of a floating one matches" win '^Other$' ""
check "window: the title matches" win "" "demo"
check "window: the wrong class is not up" bash -c "$(declare -f headless_window_up headless_msg win); PATH='$stubs':\$PATH; NSWAY=x; STUB_TREE='$STUB_TREE'; STUB_LOG='$STUB_LOG'; ! win '^nothere\$' ''"
check "window: the workspace and output are not windows" bash -c "$(declare -f headless_windows headless_msg); PATH='$stubs':\$PATH; NSWAY=x; STUB_TREE='$STUB_TREE'; STUB_LOG='$STUB_LOG'; [[ \$(headless_windows | wc -l) == 2 ]]"

# --- the launcher: software GL for a Qt app on the pixman renderer
mkdir -p "$NEST" "$NEST_HOME" "$NEST_BIN"
app_launcher_write
check "launcher: software GL (llvmpipe) in the headless session" grep -q 'LIBGL_ALWAYS_SOFTWARE=1' "$NEST_BIN/app-launch"
check "launcher: ... through Mesa's EGL vendor file" grep -q '__EGL_VENDOR_LIBRARY_FILENAMES=.*mesa' "$NEST_BIN/app-launch"
DEVKIT_SOFTWARE_GL=0 app_launcher_write
check "launcher: DEVKIT_SOFTWARE_GL=0 leaves it out" bash -c "! grep -q LIBGL_ALWAYS_SOFTWARE '$NEST_BIN/app-launch'"
DEVKIT_BACKEND_RESOLVED=hyprland app_launcher_write
check "launcher: the hyprland backend does not set it" bash -c "! grep -q LIBGL_ALWAYS_SOFTWARE '$NEST_BIN/app-launch'"

# --- stop: the sandbox's processes go, the private runtime dir goes
nest_pid=detached
( NSWAY=$NEST/rt/sway-ipc.1000.4242.sock; headless_stop ) >/dev/null 2>&1
check "stop: the private runtime dir is removed" test ! -e "$NEST/rt"

# --- the ledger's sway entry kills a sway, and only a sway
mkdir -p "$WORK/fake"
cp "$(command -v sleep)" "$WORK/fake/sway"; cp "$(command -v sleep)" "$WORK/fake/notsway"
"$WORK/fake/sway" 60 & swpid=$!
"$WORK/fake/notsway" 60 & otherpid=$!
LEDGER=""; ledger_start none
ledger_add sway "$swpid"; ledger_add sway "$otherpid"; ledger_add sway "not-a-pid"
ledger_release
sleep 0.3
check "ledger: a sway of the session is ended" bash -c "! kill -0 $swpid 2>/dev/null"
check "ledger: a process that is not a sway is left alone" kill -0 "$otherpid"
kill "$otherpid" 2>/dev/null; wait 2>/dev/null

# --- the canary's comparison (lib/selfcheck.sh)
# shellcheck source=../lib/selfcheck.sh
source "$KIT/lib/selfcheck.sh"
selfcheck_session_pids() { :; }
SC_DIR=$WORK/sc; mkdir -p "$SC_DIR"; : >"$SC_DIR/host-events.log"
hl=$WORK/hl; mkdir -p "$hl"
printf '[{"name":"DP-1","id":0,"width":10,"height":10,"x":0,"y":0,"focused":true}]' >"$hl/monitors.json"
printf '[{"address":"0xa","pid":100}]' >"$hl/clients.json"
printf '#!/bin/sh\ncase "$*" in *monitors*) cat "%s/monitors.json" ;; *clients*) cat "%s/clients.json" ;; esac\n' "$hl" "$hl" >"$stubs/hyprctl"; chmod +x "$stubs/hyprctl"
_not() { ! ( "$@" ) >/dev/null 2>&1; }
mapfile -t SC_BASE < <(selfcheck_snapshot)
check "canary: nothing happened passes" selfcheck_compare "stage" 0
echo 'monitoradded>>HEADLESS-2' >>"$SC_DIR/host-events.log"
check "canary: a monitor event of yours is a stop" _not selfcheck_compare stage 0
check "canary: ... but only events after the mark count" selfcheck_compare stage 1
: >"$SC_DIR/host-events.log"
printf '[{"address":"0xa","pid":100},{"address":"0xb","pid":200}]' >"$hl/clients.json"
check "canary: a new client of yours is a stop" _not selfcheck_compare stage 0
printf '[{"address":"0xa","pid":100}]' >"$hl/clients.json"
echo 'focusedmonv2>>DP-1,1' >>"$SC_DIR/host-events.log"
check "canary: a focus event is a stop" _not selfcheck_compare stage 0
check "canary: refuses without DEVKIT_SELFCHECK_OK=1" bash -c "$(declare -f selfcheck_run); unset DEVKIT_SELFCHECK_OK; selfcheck_run >/dev/null 2>&1; [[ \$? == 2 ]]"
conf 'DEVKIT_APP_CMD=(bin/myapp)'
check "canary: dev selfcheck refuses without DEVKIT_SELFCHECK_OK=1 (and starts nothing)" bash -c "unset DEVKIT_SELFCHECK_OK; DEVKIT_APP_ROOT='$app' '$KIT/bin/dev' selfcheck >/dev/null 2>&1; [[ \$? == 2 ]]"
finish
