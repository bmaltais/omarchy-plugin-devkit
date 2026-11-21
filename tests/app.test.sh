#!/usr/bin/env bash
# App mode (DEVKIT_APP_CMD): the config, the sandbox the app gets, its launcher, window matching and `dev errors`/`status`, with a stand-in
# app and a stand-in hyprctl. No Hyprland is needed.
source "$(dirname "$0")/lib.sh"
# shellcheck source=../lib/config.sh
source "$KIT/lib/config.sh"

app=$WORK/MyApp; mkdir -p "$app/bin" "$app/work"
# --- config
conf() { printf '# shellcheck shell=bash\n%s\n' "$1" >"$app/devkit.conf"; }
loads() { ( DEVKIT_APP_ROOT=$app; devkit_load_config >/dev/null 2>&1 && eval "$1" ); }
conf 'DEVKIT_APP_CMD=(bin/myapp --flag "two words")'
check "app mode: DEVKIT_APP_CMD without TOUR_PLUGIN_ID is a valid conf" loads '[[ $DEVKIT_APP_MODE == 1 && ${#DEVKIT_APP_CMD[@]} == 3 && -z $TOUR_PLUGIN_ID ]]'
check "app mode: a plugin conf stays in plugin mode" bash -c "printf 'TOUR_PLUGIN_ID=io.x.y\n' >'$app/devkit.conf'; ( DEVKIT_APP_ROOT='$app'; source '$KIT/lib/config.sh'; devkit_load_config && [[ \$DEVKIT_APP_MODE == 0 ]] ) 2>/dev/null"
conf 'DEVKIT_APP_CMD=(bin/myapp)
TOUR_PLUGIN_ID=io.x.y'
check "app mode: DEVKIT_APP_CMD together with TOUR_PLUGIN_ID is an error" bash -c "! ( DEVKIT_APP_ROOT='$app'; source '$KIT/lib/config.sh'; devkit_load_config ) 2>/dev/null"
conf 'DEVKIT_APP_CMD=("")'
check "app mode: an empty program word is an error" bash -c "! ( DEVKIT_APP_ROOT='$app'; source '$KIT/lib/config.sh'; devkit_load_config ) 2>/dev/null"

_not() { ! ( "$@" ) >/dev/null 2>&1; }
# --- the launcher
cat >"$app/bin/myapp" <<'APP'
#!/usr/bin/env bash
echo "args: $*"
echo "pwd: $PWD"
echo "home: $HOME cfg: $XDG_CONFIG_HOME"
echo "qpa: $QT_QPA_PLATFORM mine: ${MYVAR:-unset} demo: ${DEMO:-unset}"
echo "WARN: something is off" >&2
exit "${APP_EXIT:-0}"
APP
chmod +x "$app/bin/myapp"
conf 'DEVKIT_APP_CMD=(bin/myapp --flag "two words")
DEVKIT_APP_CWD=work
DEVKIT_ENV=(DEMO=1)
TOUR_APP_ENV=(MYVAR=x)'
TMP=$WORK/tmp; mkdir -p "$TMP"
# shellcheck source=../lib/session.sh
source "$KIT/lib/session.sh"
DEVKIT_APP_ROOT=$app devkit_load_config
mkdir -p "$NEST" "$NEST_HOME" "$NEST_BIN"
check "app mode: the command is found relative to the app's checkout" test "$(app_command_path)" = "$app/bin/myapp"
check "app mode: the working directory is relative to the checkout" test "$(app_cwd)" = "$app/work"
app_launcher_write
check "app mode: the launcher exists and is executable" test -x "$NEST_BIN/app-launch"
env -i PATH="$PATH" HOME=/real/home XDG_CONFIG_HOME=/real/cfg "$NEST_BIN/app-launch"
log=$(<"$NEST/app.log")
check "app mode: the app gets its arguments (a word with a space stays one)" grep -q 'args: --flag two words' <<<"$log"
check "app mode: it runs in DEVKIT_APP_CWD" grep -q "pwd: $app/work" <<<"$log"
check "app mode: HOME and XDG dirs are the sandbox's, not the real ones" grep -q "home: $NEST_HOME cfg: $NEST_HOME/.config" <<<"$log"
check "app mode: QT_QPA_PLATFORM=wayland, TOUR_APP_ENV and DEVKIT_ENV reach the app" grep -q 'qpa: wayland mine: x demo: 1' <<<"$log"
check "app mode: stderr is in the log too" grep -q 'WARN: something is off' <<<"$log"
check "app mode: a clean exit is recorded" test "$(<"$NEST/app.exit")" = 0
conf 'DEVKIT_APP_CMD=(bin/myapp)
TOUR_APP_ENV=(APP_EXIT=3 XDG_CONFIG_HOME=/chosen/cfg)'
DEVKIT_APP_ROOT=$app devkit_load_config
app_launcher_write
env -i PATH="$PATH" "$NEST_BIN/app-launch"
check "app mode: a failing exit status is recorded in app.exit and the log" bash -c "[[ \$(<'$NEST/app.exit') == 3 ]] && grep -q 'app exited with status 3' '$NEST/app.log'"
check "app mode: TOUR_APP_ENV can point the app at a real folder on purpose" grep -q 'cfg: /chosen/cfg' "$NEST/app.log"
conf 'DEVKIT_APP_CMD=(bin/myapp)
TOUR_APP_ENV=(notanassignment)'
DEVKIT_APP_ROOT=$app devkit_load_config
check "app mode: a TOUR_APP_ENV entry that is not NAME=value is refused" _not app_launcher_write
conf 'DEVKIT_APP_CMD=(bin/missing)'
DEVKIT_APP_ROOT=$app devkit_load_config
check "app mode: a program that does not exist is refused" _not app_command_path

# --- the sandbox: no shell config, no plugin link, the guard in place
conf 'DEVKIT_APP_CMD=(bin/myapp)'
DEVKIT_APP_ROOT=$app devkit_load_config
vptr_build() { :; }
rm -rf "$NEST"; mkdir -p "$NEST"
( HOME=$WORK/realhome; mkdir -p "$HOME/.local/share/fonts"; sandbox_build ) >/dev/null 2>&1
check "app mode: sandbox_build writes no shell.json and no plugin link" test ! -e "$NEST_HOME/.config/omarchy/shell.json" -a -z "$(ls -A "$NEST_HOME/.config/omarchy/plugins")"
check "app mode: sandbox_build builds the guard" test -x "$GUARD/poweroff"
check "app mode: sandbox_build writes the launcher" test -x "$NEST_BIN/app-launch"
check "app mode: the user's fonts are linked read-only into the sandbox" test -L "$NEST_HOME/.local/share/fonts"

# --- window matching, with a stand-in hyprctl
stubs=$WORK/stubs; mkdir -p "$stubs"
printf '#!/usr/bin/env bash\ncat "$CLIENTS"\n' >"$stubs/hyprctl"; chmod +x "$stubs/hyprctl"
export CLIENTS=$WORK/clients.json
printf '[{"mapped":true,"class":"fugue","initialClass":"fugue","title":"Fugue - demo"},{"mapped":false,"class":"other","initialClass":"other","title":"x"}]' >"$CLIENTS"
# (These are the hyprland backend's: hyprctl lists the windows. The headless backend's are in headless.test.sh.)
win() { ( DEVKIT_BACKEND_RESOLVED=hyprland; PATH=$stubs:$PATH; DEVKIT_APP_CLASS=$1; DEVKIT_APP_TITLE=$2; app_window_up ); }
check "app mode: no class or title set matches any mapped window" win "" ""
check "app mode: DEVKIT_APP_CLASS matches the window class" win "^fugue$" ""
check "app mode: DEVKIT_APP_TITLE matches the title" win "" "demo"
check "app mode: only a mapped window counts" bash -c "$(declare -f app_window_up win devkit_headless); PATH='$stubs':\$PATH; CLIENTS='$CLIENTS'; ! win '^other\$' ''"
check "app mode: the wrong class is not up" bash -c "$(declare -f app_window_up win devkit_headless); PATH='$stubs':\$PATH; CLIENTS='$CLIENTS'; ! win '^nothere\$' ''"
finish
