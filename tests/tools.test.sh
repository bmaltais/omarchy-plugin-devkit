#!/usr/bin/env bash
# bin/qmllint, bin/check, bin/reload and bin/pointer, run against stand-ins for qmllint, hyprctl, ydotool and omarchy-shell: no Hyprland is needed.
source "$(dirname "$0")/lib.sh"

mkapp() { # NAME CONF-BODY: an app checkout with a devkit.conf, as a git repo
  local d=$WORK/$1; mkdir -p "$d/scripts"
  printf '# shellcheck shell=bash\nTOUR_PLUGIN_ID=io.example.%s\n%s\n' "$1" "${2:-}" >"$d/devkit.conf"
  git -C "$d" init -q 2>/dev/null; git -C "$d" -c user.email=a@b -c user.name=n commit -q --allow-empty -m init
  echo "$d"
}
stubs=$WORK/stubs; mkdir -p "$stubs"
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$stubs/$1"; chmod +x "$stubs/$1"; }

# --- qmllint: a stand-in that reports what a file holds, so the baseline logic is what is tested
stub qmllint 'if [[ ${1:-} == --version ]]; then exit 0; fi
printf "{\"files\":[{\"filename\":\"A.qml\",\"warnings\":[%s]}]}" "$(cat "$QML_WARNINGS")"; exit 1'
q=$(mkapp q); : >"$q/A.qml"; mkdir -p "$q/scripts"
w='{"id":"unqualified","charOffset":0,"length":3,"message":"m"}'
printf 'abc' >"$q/A.qml"
export QML_WARNINGS=$WORK/warnings; printf '%s' "$w" >"$QML_WARNINGS"
ql() { PATH=$stubs:$PATH DEVKIT_APP_ROOT=$q "$KIT/bin/qmllint" "$@" >/dev/null 2>&1; }
check "qmllint: no baseline is an error" bash -c "! PATH='$stubs':\$PATH DEVKIT_APP_ROOT='$q' '$KIT/bin/qmllint' >/dev/null 2>&1"
check "qmllint: --update writes the baseline" ql --update
check "qmllint: a known warning passes" ql
printf '%s,{"id":"unqualified","charOffset":1,"length":2,"message":"m"}' "$w" >"$QML_WARNINGS"
check "qmllint: a new warning fails" bash -c "! PATH='$stubs':\$PATH DEVKIT_APP_ROOT='$q' '$KIT/bin/qmllint' >/dev/null 2>&1"
printf '{"id":"property-override","charOffset":0,"length":1,"message":"data"}' >"$QML_WARNINGS"
check "qmllint: a bug category fails and cannot be baselined" bash -c "! PATH='$stubs':\$PATH DEVKIT_APP_ROOT='$q' '$KIT/bin/qmllint' --update >/dev/null 2>&1"

# --- check: scripts are linted, the app's own steps run, a failure fails
c=$(mkapp c 'devkit_check() { step "mine" test -f ok.txt; }')
printf '#!/usr/bin/env bash\necho hi\n' >"$c/scripts/a.sh"
cl() { DEVKIT_APP_ROOT=$c "$KIT/bin/check" 2>&1; }
check "check: the app's own step fails when its command does" bash -c "! DEVKIT_APP_ROOT='$c' '$KIT/bin/check' >/dev/null 2>&1"
touch "$c/ok.txt"
check "check: passes when every step does" bash -c "DEVKIT_APP_ROOT='$c' '$KIT/bin/check' >/dev/null 2>&1"
check "check: the app's step is reported" bash -c "'$KIT/bin/check' --help >/dev/null && [[ \$(DEVKIT_APP_ROOT='$c' '$KIT/bin/check' 2>&1) == *mine* ]]"
printf '#!/usr/bin/env bash\nif then\n' >"$c/scripts/bad.sh"
check "check: a shell script with a syntax error fails" bash -c "! DEVKIT_APP_ROOT='$c' '$KIT/bin/check' >/dev/null 2>&1"
rm "$c/scripts/bad.sh"
mkdir -p "$c/scripts/devkit"; printf '#!/usr/bin/env bash\nif then\n' >"$c/scripts/devkit/bad.sh"
check "check: the submodule's files are not the app's to lint" bash -c "DEVKIT_APP_ROOT='$c' '$KIT/bin/check' >/dev/null 2>&1"

# --- reload --check: link, copy and clone modes say whether the installed plugin is this checkout
for t in jq omarchy-shell journalctl hyprctl; do command -v "$t" >/dev/null && [[ $t == jq ]] || stub "$t" 'exit 0'; done
home=$WORK/home; mkdir -p "$home/.config/omarchy/plugins"
r=$(mkapp r); rl() { PATH=$stubs:$PATH HOME=$home DEVKIT_APP_ROOT=$r "$KIT/bin/reload" "$@" 2>&1; }
check "reload: a link to this checkout is in sync" bash -c "ln -sfn '$r' '$home/.config/omarchy/plugins/io.example.r'; PATH='$stubs':\$PATH HOME='$home' DEVKIT_APP_ROOT='$r' '$KIT/bin/reload' --check | grep -q 'in sync (link)'"
check "reload: a link elsewhere is refused" bash -c "ln -sfn '$WORK' '$home/.config/omarchy/plugins/io.example.r'; ! PATH='$stubs':\$PATH HOME='$home' DEVKIT_APP_ROOT='$r' '$KIT/bin/reload' >/dev/null 2>&1"
rm "$home/.config/omarchy/plugins/io.example.r"
check "reload: a plain copy that differs is reported" bash -c "mkdir -p '$home/.config/omarchy/plugins/io.example.r'; echo x >'$home/.config/omarchy/plugins/io.example.r/f'; ! PATH='$stubs':\$PATH HOME='$home' DEVKIT_APP_ROOT='$r' '$KIT/bin/reload' --check | grep -q 'in sync'"
check "reload: a plain copy that matches (docs, tests and the kit left out) is in sync" bash -c "rm -rf '$home/.config/omarchy/plugins/io.example.r'; mkdir -p '$r/docs' '$r/tests'; cp -r '$r/devkit.conf' '$r/scripts' '$home/.config/omarchy/plugins/' 2>/dev/null; mkdir -p '$home/.config/omarchy/plugins/io.example.r'; cp -r '$r/devkit.conf' '$r/scripts' '$home/.config/omarchy/plugins/io.example.r/'; PATH='$stubs':\$PATH HOME='$home' DEVKIT_APP_ROOT='$r' '$KIT/bin/reload' --check | grep -q 'in sync (copy)'"

# --- pointer: keys only go to the windows the app allows
stub hyprctl 'case "$*" in *monitors*) echo "[{\"focused\":true,\"x\":0,\"y\":0,\"scale\":1,\"width\":100,\"height\":100,\"name\":\"M\"}]" ;; *activewindow*) echo "{\"class\":\"$FOCUS\"}" ;; *cursorpos*) echo "{\"x\":1,\"y\":1}" ;; esac'
stub ydotool 'echo "$*" >>"$YD_LOG"'
mkdir -p "$WORK/run"; touch "$WORK/run/.ydotool_socket"
p=$(mkapp p 'DEVKIT_KEY_CLASSES=(throwaway)')
export YD_LOG=$WORK/yd.log; : >"$YD_LOG"
pt() { PATH=$stubs:$PATH XDG_RUNTIME_DIR=$WORK/run DEVKIT_APP_ROOT=$p "$KIT/bin/pointer" "$@" 2>&1; }
check "pointer: no arguments prints usage and fails" bash -c "! PATH='$stubs':\$PATH DEVKIT_APP_ROOT='$p' '$KIT/bin/pointer' >/dev/null 2>&1"
check "pointer: keys are refused to a window that is not listed" bash -c "export FOCUS=firefox YD_LOG='$YD_LOG'; ! PATH='$stubs':\$PATH XDG_RUNTIME_DIR='$WORK/run' DEVKIT_APP_ROOT='$p' '$KIT/bin/pointer' key 30:1 >/dev/null 2>&1 && ! grep -q 'key' '$YD_LOG'"
check "pointer: keys go to a listed throwaway window" bash -c "export FOCUS=throwaway YD_LOG='$YD_LOG'; PATH='$stubs':\$PATH XDG_RUNTIME_DIR='$WORK/run' DEVKIT_APP_ROOT='$p' '$KIT/bin/pointer' key 30:1 >/dev/null 2>&1 && grep -q 'key 30:1' '$YD_LOG'"
check "pointer: click moves, nudges and clicks" bash -c "export FOCUS=x YD_LOG='$YD_LOG'; : >'$YD_LOG'; PATH='$stubs':\$PATH XDG_RUNTIME_DIR='$WORK/run' DEVKIT_APP_ROOT='$p' '$KIT/bin/pointer' click 10 20 >/dev/null 2>&1 && grep -q 'click 0xC0' '$YD_LOG'"
check "pointer: a right click is 0xC1" bash -c "export FOCUS=x YD_LOG='$YD_LOG'; : >'$YD_LOG'; PATH='$stubs':\$PATH XDG_RUNTIME_DIR='$WORK/run' DEVKIT_APP_ROOT='$p' '$KIT/bin/pointer' click 10 20 right >/dev/null 2>&1 && grep -q 'click 0xC1' '$YD_LOG'"
finish
