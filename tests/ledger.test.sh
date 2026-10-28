#!/usr/bin/env bash
# lib/ledger.sh undoes what a session created, from the list written as each thing was made. No Hyprland is needed: hyprctl is a stand-in
# that writes what it was asked to a file.
source "$(dirname "$0")/lib.sh"

export XDG_RUNTIME_DIR=$WORK/run LEDGER_DIR=$WORK/ledgers
mkdir -p "$XDG_RUNTIME_DIR/hypr" "$WORK/bin"
printf '#!/bin/bash\necho "${HYPRLAND_INSTANCE_SIGNATURE:-none}: $*" >>%q\n' "$WORK/hyprctl.log" >"$WORK/bin/hyprctl"
chmod +x "$WORK/bin/hyprctl"
export PATH="$WORK/bin:$PATH"
# shellcheck source=../lib/ledger.sh
source "$KIT/lib/ledger.sh"

# A session's leftovers, as nested_start and sandbox_build leave them.
make_session() { # SIG SOCKET HOME
  mkdir -p "$XDG_RUNTIME_DIR/hypr/$1" "$3" "$WORK/nest-$1"
  : >"$XDG_RUNTIME_DIR/$2"; : >"$XDG_RUNTIME_DIR/$2.lock"
}
gone() { [[ ! -e $1 ]]; }

REAL_SIG=real_sig
make_session sig1 wayland-7 "$WORK/home1"
ledger_start
ledger_add dir "$WORK/nest-sig1"
ledger_add monitor DEVTEST
ledger_add hypr sig1
ledger_add wl wayland-7
ledger_add sandbox "$WORK/home1"
check "the ledger starts with its owner" grep -qx "owner $$" "$LEDGER"
ledger_release
check "the instance folder is removed" gone "$XDG_RUNTIME_DIR/hypr/sig1"
check "the Wayland socket and its lock are removed" gone "$XDG_RUNTIME_DIR/wayland-7"
check "the lock too" gone "$XDG_RUNTIME_DIR/wayland-7.lock"
check "the session's folder is removed" gone "$WORK/nest-sig1"
check "the far monitor is removed" grep -q "output remove DEVTEST" "$WORK/hyprctl.log"
check "the ledger itself is deleted" gone "${LEDGER:?}"
check "releasing twice, with nothing left, is harmless" ledger_release

# Your own compositor is never touched, whatever the ledger says.
mkdir -p "$XDG_RUNTIME_DIR/hypr/real_sig"
: >"$WORK/hyprctl.log"
ledger_start
ledger_add hypr real_sig
ledger_release
check "your own instance folder is left alone" test -d "$XDG_RUNTIME_DIR/hypr/real_sig"
check "and is not sent exit" bash -c "! grep -q exit '$WORK/hyprctl.log'"

# A start that dies before it knows the session's name still leaves the monitor and the folder to undo.
ledger_start
ledger_add dir "$WORK/nest-early"; mkdir -p "$WORK/nest-early"
ledger_add hypr ""
ledger_release
check "an empty value is skipped, the rest is undone" gone "$WORK/nest-early"

# Reaping: a dead owner is released; a live one is not; "none" only when asked.
make_session dead wayland-8 "$WORK/h8"; make_session live wayland-9 "$WORK/h9"; make_session free wayland-10 "$WORK/h10"
mk() { LEDGER=""; ledger_start "$1"; ledger_add hypr "$2"; ledger_add wl "$3"; }
( exit 0 ) & dead_pid=$!; wait "$dead_pid"
mk "$dead_pid" dead wayland-8
mk "$$" live wayland-9
mk none free wayland-10
LEDGER=""
ledger_reap
check "a session whose script died is released" gone "$XDG_RUNTIME_DIR/hypr/dead"
check "a session whose script is alive is kept" test -d "$XDG_RUNTIME_DIR/hypr/live"
check "a session with no owner is kept by a plain reap" test -d "$XDG_RUNTIME_DIR/hypr/free"
ledger_reap none
check "and released when no session of that kind is running" gone "$XDG_RUNTIME_DIR/hypr/free"
check "the live one is still kept" test -d "$XDG_RUNTIME_DIR/hypr/live"

finish
