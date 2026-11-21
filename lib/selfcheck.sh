# shellcheck shell=bash
# `dev selfcheck`: the canary for the headless backend. It runs a headless session (up, a screenshot, a click, down) while watching YOUR
# Hyprland read-only, and fails the moment your compositor noticed anything: a window, monitor, focus or workspace event on its event socket,
# a changed monitor or client list, a host client that is one of the session's processes, a ydotoold that was not there before.
#
# It watches by listening to the host's event socket (socat -u, which never sends) and reading `hyprctl -j monitors` and `hyprctl -j clients`
# (read-only queries). It sends your compositor nothing else. It is only meaningful with your hands off the mouse and keyboard (a focus event
# you caused looks the same as one the session caused), so it refuses unless DEVKIT_SELFCHECK_OK=1 is set by you. The headless backend's
# normal runs do not need it.
#
# Sourced by bin/dev, which provides SELF (the dev script), DEV, DEVKIT_NAME and the session functions.

SELFCHECK_EVENTS='^(activewindow|activewindowv2|focusedmon|focusedmonv2|monitoradded|monitoraddedv2|monitorremoved|monitorremovedv2|openwindow|closewindow|workspace|workspacev2|createworkspace|createworkspacev2|destroyworkspace|destroyworkspacev2|movewindow|movewindowv2|windowtitle|windowtitlev2|fullscreen|changefloatingmode|urgent|minimized|activelayout)>>'

# The host as it is now, in a form two moments can be compared: monitors, client addresses, ydotoold count.
selfcheck_snapshot() {
  hyprctl -j monitors | jq -S 'map({name, id, width, height, x, y, focused})' | md5sum | cut -c1-32
  hyprctl -j clients | jq -r '.[].address' | sort | md5sum | cut -c1-32
  pgrep -u "$UID" -x ydotoold | wc -l
}

# selfcheck_compare STAGE MARK: 0 when your compositor saw nothing since the snapshot and the line MARK of its event log.
selfcheck_compare() {
  local stage=$1 mark=$2 bad=0 now ev pid hostpids
  sleep 1   # events arrive a moment after what caused them
  mapfile -t now < <(selfcheck_snapshot)
  ev=$(tail -n "+$((mark + 1))" "$SC_DIR/host-events.log" | grep -E "$SELFCHECK_EVENTS" || true)
  if [[ -n $ev ]]; then echo "selfcheck: STOP at $stage: your Hyprland logged events:" >&2; printf '    %s\n' "${ev//$'\n'/$'\n    '}" >&2; bad=1; fi
  [[ ${now[0]} == "${SC_BASE[0]}" ]] || { echo "selfcheck: STOP at $stage: your monitor list changed" >&2; bad=1; }
  [[ ${now[1]} == "${SC_BASE[1]}" ]] || { echo "selfcheck: STOP at $stage: your client (window) list changed" >&2; bad=1; }
  [[ ${now[2]} == "${SC_BASE[2]}" ]] || { echo "selfcheck: STOP at $stage: ydotoold count went from ${SC_BASE[2]} to ${now[2]}" >&2; bad=1; }
  # None of the session's processes may be a client of your compositor.
  hostpids=$(hyprctl -j clients | jq -r '.[].pid')
  for pid in $(selfcheck_session_pids); do
    ! grep -qx "$pid" <<<"$hostpids" || { echo "selfcheck: STOP at $stage: process $pid of the session is a window of your desktop" >&2; bad=1; }
  done
  ((bad == 0)) || return 1
  echo "selfcheck: $stage: your Hyprland saw nothing ($(wc -l <"$SC_DIR/host-events.log") events in all, none of window, monitor, focus or workspace)"
}
selfcheck_session_pids() { nested_procs _selfcheck_print_pid; }
_selfcheck_print_pid() { echo "$1"; }

selfcheck_run() {
  [[ ${DEVKIT_SELFCHECK_OK:-} == 1 ]] || {
    echo "dev selfcheck: refused. It watches your Hyprland for events the session might cause, which only means something with your hands off the mouse and keyboard: set DEVKIT_SELFCHECK_OK=1 to say you are." >&2
    return 2
  }
  devkit_headless || { echo "dev selfcheck: it checks the headless backend (an app, DEVKIT_APP_CMD, without DEVKIT_BACKEND=hyprland)" >&2; return 2; }
  local rt=${XDG_RUNTIME_DIR:-/run/user/$UID} sig=${HYPRLAND_INSTANCE_SIGNATURE:-} tool sock spid mark rc=0
  for tool in socat hyprctl jq md5sum pgrep; do command -v "$tool" >/dev/null || { echo "dev selfcheck: $tool is needed" >&2; return 2; }; done
  [[ -n $sig ]] || { echo "dev selfcheck: run it from inside your Hyprland session (it watches that one)" >&2; return 2; }
  sock=$rt/hypr/$sig/.socket2.sock
  [[ -S $sock ]] || { echo "dev selfcheck: no event socket at $sock" >&2; return 2; }
  SC_DIR=$rt/$DEVKIT_NAME-selfcheck
  rm -rf "$SC_DIR"; mkdir -p "$SC_DIR"
  [[ ! -s $STATE ]] || { echo "dev selfcheck: a session is already up (dev down first)" >&2; return 2; }
  # Listening only: socat -u copies from the socket to the log and never writes to it.
  socat -u "UNIX-CONNECT:$sock" - >"$SC_DIR/host-events.log" 2>/dev/null &
  spid=$!
  sleep 0.5
  kill -0 "$spid" 2>/dev/null || { echo "dev selfcheck: could not listen to your compositor's event socket" >&2; return 2; }
  mapfile -t SC_BASE < <(selfcheck_snapshot)
  printf '%s\n' "baseline monitors=${SC_BASE[0]} clients=${SC_BASE[1]} ydotoold=${SC_BASE[2]}" >"$SC_DIR/baseline.txt"
  echo "selfcheck: watching your Hyprland read-only (events in $SC_DIR/host-events.log); starting the headless session"
  selfcheck_stage "dev up" "$SELF" up || rc=1
  if ((rc == 0)); then selfcheck_stage "dev shot" "$SELF" shot "$SC_DIR/shot.png" || rc=1; fi
  if ((rc == 0)); then
    # shellcheck disable=SC2086
    selfcheck_stage "dev click" "$SELF" click ${DEVKIT_SELFCHECK_CLICK:-1 1} || rc=1
  fi
  # More of dev's commands under the same watch: DEVKIT_SELFCHECK_EXTRA='status;windows;type hi;key Return;reload' (separated by ;).
  local extra step
  if ((rc == 0)) && [[ -n ${DEVKIT_SELFCHECK_EXTRA:-} ]]; then
    IFS=';' read -ra extra <<<"$DEVKIT_SELFCHECK_EXTRA"
    for step in "${extra[@]}"; do
      # shellcheck disable=SC2086
      selfcheck_stage "dev $step" "$SELF" $step || { rc=1; break; }
    done
  fi
  # Always end the session, whatever happened, by the session's own down (it kills only what the session started).
  "$SELF" down >/dev/null 2>&1 || true
  if ((rc == 0)); then selfcheck_stage "dev down" true || rc=1; fi
  kill "$spid" 2>/dev/null || true
  if ((rc == 0)); then echo "selfcheck: ok, your Hyprland saw nothing of the session (screenshot $SC_DIR/shot.png)"
  else echo "selfcheck: FAILED (the session was ended; log $SC_DIR/host-events.log)" >&2; fi
  return $rc
}

# selfcheck_stage NAME COMMAND...: run one step of the session, then compare. A failed step or a changed host is a stop.
selfcheck_stage() {
  local name=$1 mark; shift
  mark=$(wc -l <"$SC_DIR/host-events.log")
  "$@" || { echo "selfcheck: STOP: $name failed" >&2; return 1; }
  selfcheck_compare "$name" "$mark"
}
