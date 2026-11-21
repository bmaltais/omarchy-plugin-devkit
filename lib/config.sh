# shellcheck shell=bash
# Finds the app a devkit command is run for and loads its devkit.conf (docs/configuration.md). Sourced by bin/dev and bin/tour.
#
# The app is the checkout the command is run in, or the one DEVKIT_APP_ROOT names (the app's own wrapper scripts set it). Its devkit.conf
# is plain bash: variables and, if it wants, functions (hooks). Defaults are set first, so a conf only says what differs.
#
# Sets: REPO (the app's root), DEVKIT (this kit's root), DEVKIT_NAME, and every variable the conf sets.

DEVKIT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# DEVKIT_BACKEND from the environment, read once when this file is sourced: it beats the conf's (a run can ask for the other backend).
DEVKIT_BACKEND_FROM_ENV=${DEVKIT_BACKEND:-}

# Is this session on the headless backend (lib/headless.sh)? Set by devkit_load_config; false before it.
devkit_headless() { [[ ${DEVKIT_BACKEND_RESOLVED:-hyprland} == headless ]]; }

devkit_load_config() {
  REPO=${DEVKIT_APP_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
  DEVKIT_CONF=${DEVKIT_CONF:-$REPO/devkit.conf}
  [[ -f $DEVKIT_CONF ]] || { echo "devkit: no devkit.conf in $REPO (see $DEVKIT/docs/configuration.md; run from the app's checkout or set DEVKIT_APP_ROOT)" >&2; return 1; }
  # Defaults: what an app that sets nothing gets.
  TOUR_PLUGIN_ID=""
  # App mode (docs/configuration.md#standalone-app): DEVKIT_APP_CMD set means the session runs this command, not the Omarchy shell.
  DEVKIT_APP_CMD=()
  DEVKIT_APP_CLASS=""
  DEVKIT_APP_TITLE=""
  DEVKIT_APP_CWD=""
  TOUR_APP_ENV=()
  DEVKIT_APP_MODE=0
  DEVKIT_BACKEND=""
  DEVKIT_SOFTWARE_GL=1
  TOUR_PLUGIN_ENTRY='{}'
  TOUR_PLUGIN_WIDGET=1
  TOUR_SANDBOX_COPY=()
  TOUR_SANDBOX_LINK=()
  TOUR_REAL_UNCHANGED=()
  DEVKIT_ENV=()
  DEVKIT_GUARD_EXTRA=()
  DEVKIT_LAYERS=()
  DEVKIT_NOISE=""
  DEVKIT_KEY_CLASSES=(spare-test)
  DEVKIT_PROTECT_BRANCHES=(main)
  DEVKIT_CHECK_CMD=()
  DEVKIT_SH_FILES=()
  DEVKIT_RELOAD_MODE=auto
  DEVKIT_RELOAD_READY=""
  DEVKIT_RELOAD_EXCLUDE=()
  DEVKIT_USAGE=""
  DEVKIT_NAME=""
  TOUR_TITLE=""
  # shellcheck disable=SC1090
  source "$DEVKIT_CONF"
  [[ -z $DEVKIT_BACKEND_FROM_ENV ]] || DEVKIT_BACKEND=$DEVKIT_BACKEND_FROM_ENV
  if ((${#DEVKIT_APP_CMD[@]} > 0)); then
    [[ -n ${DEVKIT_APP_CMD[0]} ]] || { echo "devkit: DEVKIT_APP_CMD in $DEVKIT_CONF starts with an empty word" >&2; return 1; }
    [[ -z $TOUR_PLUGIN_ID ]] || { echo "devkit: $DEVKIT_CONF sets both DEVKIT_APP_CMD (a standalone app) and TOUR_PLUGIN_ID (a plugin): pick one" >&2; return 1; }
    DEVKIT_APP_MODE=1
  else
    [[ -n $TOUR_PLUGIN_ID ]] || { echo "devkit: $DEVKIT_CONF must set TOUR_PLUGIN_ID (the plugin's id), or DEVKIT_APP_CMD for a standalone app" >&2; return 1; }
  fi
  # The backend the session runs on: headless (a sway with no output on your desktop: lib/headless.sh) or hyprland (a nested Hyprland that is
  # a window of yours). An app's default is headless; a plugin needs the Omarchy shell, which needs Hyprland.
  case ${DEVKIT_BACKEND:-} in
    "") if ((DEVKIT_APP_MODE)); then DEVKIT_BACKEND_RESOLVED=headless; else DEVKIT_BACKEND_RESOLVED=hyprland; fi ;;
    headless | hyprland) DEVKIT_BACKEND_RESOLVED=$DEVKIT_BACKEND ;;
    *) echo "devkit: DEVKIT_BACKEND must be headless or hyprland, not '$DEVKIT_BACKEND'" >&2; return 1 ;;
  esac
  if [[ $DEVKIT_BACKEND_RESOLVED == headless ]] && ((! DEVKIT_APP_MODE)); then
    echo "devkit: DEVKIT_BACKEND=headless is for a standalone app (DEVKIT_APP_CMD); a plugin needs the Omarchy shell, which needs the hyprland backend" >&2; return 1
  fi
  : "${DEVKIT_NAME:=$(basename "$REPO" | tr '[:upper:]' '[:lower:]')}"
  : "${TOUR_TITLE:=$DEVKIT_NAME}"
  jq -e 'type == "object"' <<<"$TOUR_PLUGIN_ENTRY" >/dev/null 2>&1 || { echo "devkit: TOUR_PLUGIN_ENTRY in $DEVKIT_CONF is not a JSON object" >&2; return 1; }
}

# For a command that works without an app (pointer, spare): load the conf when there is one, else keep the defaults it sets.
devkit_load_config_optional() {
  local root=${DEVKIT_APP_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
  if [[ -f ${DEVKIT_CONF:-$root/devkit.conf} ]]; then devkit_load_config; fi
}
