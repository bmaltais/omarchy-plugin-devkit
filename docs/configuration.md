# Configuring the devkit for a plugin

An app says what is its own in one file, `devkit.conf`, at the root of its checkout. It is plain bash: variables, and (if it wants) functions. `dev` and `tour` both source it, with defaults set first, so a conf only lists what differs. `lib/config.sh` loads it and tells you what is wrong with it.

Which checkout is "the app"? The one named by `DEVKIT_APP_ROOT` (the app's own wrapper scripts set it, see [adopting.md](adopting.md)), else the git root of the folder the command is run in. `DEVKIT_CONF` names another conf file.

```bash
# shellcheck shell=bash
TOUR_PLUGIN_ID=io.github.me.myplugin
TOUR_PLUGIN_WIDGET=0
TOUR_PLUGIN_ENTRY='{"colorScheme":"dark"}'
DEVKIT_LAYERS=(omarchy-myplugin)
```

## Variables

| Variable | Meaning | Default |
|---|---|---|
| `TOUR_PLUGIN_ID` | **Required** (unless `DEVKIT_APP_CMD` is set: [Standalone app](#standalone-app)). The plugin's id (its `manifest.json` `id`). The checkout is linked into the session's plugins folder under it | |
| `DEVKIT_NAME` | A short lower-case name: the session's state folder (`$XDG_RUNTIME_DIR/NAME-dev`) and its view window (`NAME-test-viewer`, "NAME test session") | the checkout's folder name |
| `TOUR_TITLE` | The app's name for the recorder's strip and notifications | `DEVKIT_NAME` |
| `TOUR_PLUGIN_ENTRY` | A JSON object merged into the plugin's entry in the sandbox's `shell.json`: the settings the session starts with | `{}` |
| `TOUR_PLUGIN_WIDGET` | `0` for a plugin with no bar widget (a service): it is loaded, but not put on the Omarchy bar. `1` adds its id to the bar's right side if your bar layout lacks it | `1` |
| `DEVKIT_LAYERS=(ns …)` | Layer-shell namespaces of the plugin's windows. `dev` calls the window up when one is mapped (for `dev status`, the notes on input, `dev_window`), and `tour` sends keys (`typed`, `esc`, `pressed`) only while one is | none |
| `TOUR_SANDBOX_COPY=(path …)` | Paths under `$HOME` to *copy* into the sandbox: data the session changes | none |
| `TOUR_SANDBOX_LINK=(path …)` | Paths under `$HOME` to *link* read-only (icons) | none |
| `TOUR_REAL_UNCHANGED=(path …)` | Paths under your real `$HOME` that a recording must not change: fingerprinted before and after, and the run fails if one changed. Never name a mount (it would be walked) | none |
| `DEVKIT_ENV=(NAME=value …)` | Environment for everything in the session: a demo-mode switch, say | none |
| `DEVKIT_GUARD_EXTRA=(name …)` | Commands to refuse as well as the built-in list ([how-it-works.md](how-it-works.md#the-guard)): your own plugin's power or lock command, a tool that would touch real data | none |
| `DEVKIT_NOISE` | An extra regular expression: log lines matching it are not counted as the plugin's errors | none |
| `DEVKIT_USAGE` | Text added to `dev --help`, for the commands the conf defines | none |

| `DEVKIT_RELOAD_MODE` | How `reload` puts the checkout in the shell: `link`, `copy`, `clone` or `auto` (found from `~/.config/omarchy/plugins/ID`) | `auto` |
| `DEVKIT_RELOAD_EXCLUDE=(path …)` | `reload` in `copy` mode leaves these out as well as `.git`, `tests`, `screenshots`, `node_modules`, `preview.png`, `docs`, `*.md`, `scripts/devkit` | none |
| `DEVKIT_RELOAD_READY` | The plugin's IPC method that answers once its service is loaded (`state`): `reload` waits for it before opening a window | none |
| `DEVKIT_KEY_CLASSES=(class …)` | Window classes `pointer key` may send keys to (throwaway test windows). Keys are refused to anything else | `(spare-test)`, the window `spare open` starts |
| `DEVKIT_SH_FILES=(path …)` | Shell files `check` lints besides `scripts/`, `tests/` and `.githooks/` | none |

| `DEVKIT_PROTECT_BRANCHES=(name …)` | Branches `pre-commit` refuses a commit on (`ALLOW_MAIN=1` overrides) | `(main)` |
| `DEVKIT_CHECK_CMD=(cmd …)` | What `pre-commit` runs as the check | the kit's `bin/check` |

`try-setting` reads the shell config named by `DEVKIT_SHELL_JSON` (default `~/.config/omarchy/shell.json`).

`qmllint` reads two environment variables, as it is Python: `DEVKIT_APP_ROOT` and `DEVKIT_QML_BASELINE` (default `scripts/qmllint-baseline.txt`).

## Standalone app

A standalone Wayland app (a Qt Quick binary, a terminal, anything that opens a window) is tested and recorded in the same session, with its own command in place of the Omarchy shell and plugin. Set `DEVKIT_APP_CMD` and leave out `TOUR_PLUGIN_ID` (setting both is an error). Nothing of plugin mode changes when `DEVKIT_APP_CMD` is not set.

```bash
# shellcheck shell=bash
DEVKIT_NAME=fugue
DEVKIT_APP_CMD=(build/fugue)
DEVKIT_APP_CLASS='^fugue$'
TOUR_REAL_UNCHANGED=(.config/fugue .local/share/fugue)
```

| Variable | Meaning | Default |
|---|---|---|
| `DEVKIT_APP_CMD=(prog arg …)` | The app: this command is the session's only client. A bare name is looked up on `PATH`, a relative path is from the checkout | |
| `DEVKIT_APP_CLASS` | Regular expression for the app's window class (or initial class): the window counts as up when a mapped one matches | any window |
| `DEVKIT_APP_TITLE` | The same for the window title | any title |
| `DEVKIT_APP_CWD` | The app's working directory, relative to the checkout | the checkout |
| `TOUR_APP_ENV=(NAME=value …)` | Environment for the app only, applied last, so it may override anything below. `DEVKIT_ENV` reaches it as well | none |

What the app runs with:

- **A sandbox home.** `HOME` and `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` and `XDG_CACHE_HOME` are the session's, so the app's settings, data and state are not yours and start empty. Your fonts and fontconfig are linked in read-only, and Omarchy's theme files are copied, as in plugin mode. To give it data on purpose use `TOUR_SANDBOX_COPY` (a copy) or `TOUR_SANDBOX_LINK` (read-only); to point it at a real folder, say so with `TOUR_APP_ENV=(XDG_CONFIG_HOME="$HOME/.config")` (the conf is read with your real `HOME`). Name what a recording must not change in `TOUR_REAL_UNCHANGED`.
- **`QT_QPA_PLATFORM=wayland`** (and `GDK_BACKEND=wayland`), `WAYLAND_DISPLAY` of the session's socket (Hyprland sets it), the session's own D-Bus, and the guard first on `PATH`.
- **The size of the session's screen** (`DEV_SIZE`, `TOUR_SIZE`). The session has no bar or other windows, so a single window fills it; a dialog the app opens floats over it.
- **Its output in a log.** stdout and stderr go to `$XDG_RUNTIME_DIR/NAME-dev/nest/app.log`, and `dev errors` lists the lines that look like a problem (`warn`, `error`, `critical`, `fatal`, QML type errors, and "app exited with status N", which counts as an error); `DEVKIT_NOISE` hides lines. `dev status` says whether the app is running or exited, and whether its window is open.

What `dev` does in app mode: `up` (fails, leaving the session up for `dev errors`, when the app has no window or has exited), `down`, `status`, `reload` (ends the app and starts it again, so a rebuilt binary is picked up), `run`, `windows`, `env`, `click`, `rclick`, `scroll`, `move`, `type`, `key`, `shot`, `errors`, `watch`/`unwatch`, and an app's own `dev_cmd_NAME`. `ipc` and `set` need the shell and refuse. `layer_mapped` and `DEVKIT_LAYERS` are not used; a `devkit_window_up` hook, if defined, still replaces the window check. A tour needs no `TOUR_LAYER`: `typed`, `esc` and `pressed` send keys while the app has a window, and `app_window_up` is there for `wait_until`.

## Hooks (functions in `devkit.conf`)

| Hook | Called | Use it to |
|---|---|---|
| `devkit_sandbox DIR` | while the sandbox home DIR is built, after the copies and links and the guard | make the sandbox safe for your plugin: a demo-mode marker file, rewrite paths in copied files so a change cannot reach a real one. Return non-zero to refuse to start |
| `devkit_window_up` | by `dev`, to ask whether the plugin's window is up | replace the `DEVKIT_LAYERS` check, for a window that is not a layer of its own. Helpers: `layer_mapped NS`, `nenv CMD…` (run a command in the session), `$ID` |
| `tour_keys_ok` | by `tour`, before each key | the same, for the recorder: say whether the window is up so `typed`/`esc`/`pressed` may send keys. May call `layer_up NS` (the recorder's) or `hyprctl` |
| `dev_cmd_NAME ARGS…` | `dev NAME ARGS…`, with the session known to be up | add a command: open a window, call the plugin's IPC. Helpers: `dev_window LABEL ARGS…` (calls `omarchy-shell ARGS` in the session, checks the window opened, says so), `nenv`, `$ID` |
| `reload_open WINDOW ARG…` | by `reload`, to open a window of the plugin in the real shell | replace `omarchy-shell ID WINDOW ARG…` (close it first so a toggle cannot hide it, refuse an argument that is missing) |
| `devkit_check` | by `check`, after its own steps | run the app's own tests with `step NAME COMMAND…` |
| `try_default` | by `try-setting`, when no command is given | print what the app shows for the setting (StartBar: its Dock layout) |
| `tour_requires` | first, by `tour`, with your real home | check what the tour needs; print a reason and return non-zero if it is missing |

In a hook running in `dev`: `nenv COMMAND…` runs a command in the session's environment (its home, its guard, its compositor), `$ID` is the plugin id, `$NEST_HOME` the session's home, `$NSIG`/`$NWD` its Hyprland signature and Wayland socket, `shell_up` asks whether its shell answers.

## Commands `dev` has without any configuration

`up`, `down`, `status`, `reload`, `watch`, `unwatch`, `ipc TARGET METHOD [ARGS]` (the plugin's IPC, in the session), `run CMD…`, `windows`, `set JSON`, `env`, `click`, `rclick`, `scroll`, `move`, `type`, `key`, `shot`, `errors`. `dev --help` lists them with your own.

Environment: `DEV_SIZE=WxH` (the session's screen, default 1280x800), `DEV_WATCH=1` (open the view window with the session; default: none), `DEV_WINDOW=1` (the session's own window stays on your screen; no far monitor, no view window), `DEV_TTL=SECONDS` (it closes itself, default 1800), `DEV_QUIET=1` (no notes when the window is not up), `NEST_HOST_INPUT=1` (keep your mouse and keyboard on, for debugging the session by hand).

## What a tour file sets

A tour file is sourced by `tour` after `devkit.conf`, so it can override it (a tour can start the plugin from other settings than `dev` does). It sets `TOUR_OUT`, `TOUR_STEPS`, `TOUR_SIZE`, `TOUR_CROP`, `TOUR_MAX_SECONDS` and the rest of the table in [recording-tours.md](recording-tours.md#reference), and defines `tour_play`. `TOUR_DIR` is the folder the tour file is in, so a tour can `source "$TOUR_DIR/common.sh"` for what the app's tours share.

## Test session differences from Omarchy

- The session's `omarchy-bar` layer covers the whole 1280x800 output (`y 0, h 800`); on a real Omarchy desktop it is sized by its
  exclusive zone. A plugin that finds the bar's edge from `hyprctl -j layers` must not rely on it in a test session.
- dwindle's `preserve_split` is on, as in Omarchy, so `togglesplit` is not undone.
