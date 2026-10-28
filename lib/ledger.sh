# shellcheck shell=bash
# The ledger: everything a session creates on your machine, written down the moment it is created, and undone from that list.
#
# The scripts that start a session (bin/dev, bin/tour) own its cleanup, but cleanup that relies on remembering what was made leaks the
# moment a step fails before it is remembered, or the script is killed. So each thing is added to a file as it is created, outside the
# session's own folder. A normal stop, a failed start, Ctrl+C and the next run after a crash all end in the same ledger_release.
#
# One file per session in $LEDGER_DIR, one line each: "KIND VALUE". The first line is "owner PID": the script that made it, or "none"
# for a session that outlives its script (dev up), which dev up and dev down release. Kinds:
#   monitor NAME     a headless monitor on your compositor           -> hyprctl output remove
#   hypr SIGNATURE   a nested compositor's instance folder           -> exit it (never yours), delete the folder
#   wl NAME          its Wayland socket in the runtime folder        -> delete the socket and its lock
#   sandbox PATH     a sandbox home; what runs with it as its config -> terminate, then kill
#   dir PATH         a folder made for the session                   -> delete
LEDGER_DIR=${LEDGER_DIR:-${XDG_RUNTIME_DIR:-/run/user/$UID}/${DEVKIT_NAME:-devkit}-ledger}
LEDGER=""

# ledger_start [OWNER_PID|none]: a new ledger for this session. Sets LEDGER.
ledger_start() {
  mkdir -p "$LEDGER_DIR"
  LEDGER=$(mktemp "$LEDGER_DIR/session.XXXXXX")
  echo "owner ${1:-$$}" >"$LEDGER"
}
ledger_add() { # KIND VALUE
  [[ -n $LEDGER && -n ${2:-} ]] && echo "$1 $2" >>"$LEDGER"
  return 0
}

_ledger_sandbox_procs() { # PATH SIGNAL
  local p
  for p in /proc/[0-9]*; do
    p=${p#/proc/}
    [[ $p != "$$" && -r /proc/$p/environ ]] || continue
    if tr '\0' '\n' </proc/"$p"/environ 2>/dev/null | grep -qx "XDG_CONFIG_HOME=$1/.config"; then kill "-$2" "$p" 2>/dev/null; fi
  done 2>/dev/null
  return 0
}

# ledger_release [FILE]: undo what the ledger lists, newest first, then delete it. Safe to run twice, and when part of it is already gone.
ledger_release() {
  local file=${1:-$LEDGER} rt=${XDG_RUNTIME_DIR:-/run/user/$UID} kind value line lines=() i
  [[ -f $file ]] || return 0
  # Read whole first: a child still running while the sandbox's processes are killed (they are found by environment) could be one of them.
  mapfile -t lines <"$file"
  for ((i = ${#lines[@]} - 1; i >= 0; i--)); do
    line=${lines[i]}; kind=${line%% *}; value=${line#* }
    [[ -n $value ]] || continue
    case $kind in
      monitor) hyprctl output remove "$value" >/dev/null 2>&1 ;;
      hypr)
        # Never your own compositor: hyprctl with no signature, or yours, would act on it.
        if [[ $value != "${REAL_SIG:-${HYPRLAND_INSTANCE_SIGNATURE:-}}" ]]; then
          [[ -S $rt/hypr/$value/.socket.sock ]] && env HYPRLAND_INSTANCE_SIGNATURE="$value" hyprctl dispatch "hl.dsp.exit()" >/dev/null 2>&1
          rm -rf "${rt:?}/hypr/$value"
        fi ;;
      wl) rm -f "${rt:?}/$value" "${rt:?}/$value.lock" ;;
      sandbox) _ledger_sandbox_procs "$value" TERM; sleep 0.5; _ledger_sandbox_procs "$value" KILL ;;
      dir) [[ -n $value && $value != / ]] && rm -rf "$value" ;;
    esac
  done
  rm -f "$file"
  return 0
}

# ledger_reap: release the ledgers of sessions whose script is gone (killed, crashed): a dead owner, or "none" when no session of that kind
# is running (the caller says so by calling it only then). Run at the start of every session and by dev down.
ledger_reap() { # [none]  with "none", sessions without an owner are released too
  local f owner
  [[ -d $LEDGER_DIR ]] || return 0
  for f in "$LEDGER_DIR"/session.*; do
    [[ -f $f && $f != "$LEDGER" ]] || continue
    owner=$(sed -n '1s/^owner //p' "$f")
    if [[ $owner == none ]]; then [[ ${1:-} == none ]] && ledger_release "$f"
    elif [[ ! -d /proc/$owner ]]; then ledger_release "$f"; fi
  done
  return 0
}
