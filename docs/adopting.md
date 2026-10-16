# Adopting the devkit in a plugin

For a new plugin: steps 1 to 4. For one of the three Start apps, which carry a copy of these scripts: all of it, one app at a time, checking against what it did before.

## 1. Add the kit as a submodule

```sh
git submodule add https://github.com/OWNER/omarchy-plugin-devkit scripts/devkit
git -C scripts/devkit checkout v0.2.2 && git add scripts/devkit
git commit -m "Add scripts/devkit: omarchy-plugin-devkit v0.2.2"
# later, to update: git -C scripts/devkit fetch --tags && git -C scripts/devkit checkout vX.Y.Z && git add scripts/devkit && git commit
```

**Why a submodule.** The kit is development tooling: the plugin does not need it to run, and a user should not receive it. `omarchy plugin add` is a plain `git clone`, without `--recurse-submodules`, and `omarchy plugin update` only fast-forwards, so an installed plugin gets an empty `scripts/devkit` folder; and the marketplace's review reads the files of the repository's tree, where a submodule is a pointer, not files. What ships and is reviewed is then the plugin and the app's own scripts, not a copy of the kit in every plugin. An update is a one-line pointer change: no merge commits (a subtree's break GitHub's "Rebase and merge"), no conflicts, and the version is pinned in the commit. Where it costs: a contributor clones with `--recurse-submodules` (or runs `git submodule update --init`), and CI's checkout needs `submodules: true`. Do not edit the files in `scripts/devkit`: fix them in the kit's repository, release, and move the pointer.

## 2. Write `devkit.conf` ([configuration.md](configuration.md))

At least `TOUR_PLUGIN_ID`. Add `DEVKIT_LAYERS` (the layer-shell names of the plugin's windows), `TOUR_PLUGIN_WIDGET=0` for a service, `TOUR_PLUGIN_ENTRY` for the settings the session starts from, and the commands that open its windows (`dev_cmd_*`).

## 3. Two-line wrappers, so `scripts/dev` is what people type

```bash
#!/usr/bin/env bash
export DEVKIT_APP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
kit=$DEVKIT_APP_ROOT/scripts/devkit/bin/dev
[[ -x $kit ]] || { echo "scripts/devkit is empty: git submodule update --init scripts/devkit" >&2; exit 1; }
exec "$kit" "$@"
```

The same for `tour` (often `scripts/tour.sh`), `sheet`, `check` (`scripts/check.sh`), `reload`, `pointer` and `qmllint`. A wrapper that finds the submodule empty says so and exits, so a clone without it fails with the fix in the message. Run from the plugin's checkout, the kit finds it without `DEVKIT_APP_ROOT`; the wrapper makes it work from anywhere, and from a script.

## 4. Add the checks

The app's check is `scripts/devkit/bin/check`: it runs shellcheck on the app's own scripts (never the kit's), `lint`, `qmllint` and the manifest check, then the app's `devkit_check` hook for its own tests. Do not glob `scripts/devkit/bin/*` into an app's own shellcheck list: `qmllint` is Python. If the plugin's tests exercise the guard, point them at `scripts/devkit/lib/session.sh`.

## Moving a Start app off its copy

What changes in an app's files:

| Was (the copy) | Is (the kit) |
|---|---|
| `scripts/nested/session.sh`, `vptr.c`, `build.sh`, the Wayland XML | `scripts/devkit/lib/session.sh`, `vptr.c`, `build-vptr.sh`, the XML |
| `scripts/dev`, `scripts/tour.sh`, `scripts/sheet` | wrappers of `scripts/devkit/bin/dev`, `tour`, `sheet` |
| `scripts/dev-view.qml`, `scripts/tour-banner.qml` | `scripts/devkit/lib/…` (the view window's title comes from `DEVKIT_NAME`) |
| `TOUR_PLUGIN_ID`, `TOUR_SANDBOX_*`, `TOUR_REAL_UNCHANGED` set in `scripts/dev` and each tour | set once in `devkit.conf`; a tour may still override |
| `dev open`, `setup`, `settings ID`, `close` (`cmd_window`) | `dev_cmd_open` and the rest, in `devkit.conf`, using `dev_window` |
| `overlay_up` with the app's layer name written in | `DEVKIT_LAYERS`, or `devkit_window_up` |
| `ID`, the state folder `NAME-dev`, `QS_APP_ID=NAME-test-viewer` | `TOUR_PLUGIN_ID`, `DEVKIT_NAME` (set it to the old `NAME` and they are unchanged) |
| `sandbox_repoint` (demo mode, or rewriting copied manifests) | the `devkit_sandbox DIR` hook, and `DEVKIT_ENV=(STARTDRIVE_DEMO=1)` for the demo switch |
| tours that `source "$HERE/tours/common.sh"` | `source "$TOUR_DIR/common.sh"` (`HERE` is not set for a tour any more) |
| `scripts/lint-rules.sh` | `bin/lint` (the same rules, found by content and not by a list of paths) |
| (nothing) | the guard: the session refuses the plugin's power commands. StartDrive's demo mode already refuses every tool that could reach the machine; the guard is a second wall |
| a recording's frames left in `/tmp` | removed when the run ends (`TOUR_KEEP_TMP=1` keeps them) |

### StartDrive

A sketch from reading its copy, **not yet tried against the app**; step 5 below is how to find out.

```bash
TOUR_PLUGIN_ID=io.github.bmaltais.startdrive
DEVKIT_NAME=startdrive
DEVKIT_LAYERS=(omarchy-startdrive)
DEVKIT_ENV=(STARTDRIVE_DEMO=1)           # the CLI serves fixture drives and runs no systemd, rclone or keyring command
TOUR_SANDBOX_LINK=(.local/share/icons)
TOUR_REAL_UNCHANGED=(.config/omarchy/shell.json .config/startdrive .config/systemd/user .config/rclone .local/share/applications/startdrive.desktop .local/bin/startdrive)

devkit_sandbox() {                       # the sandbox is in demo mode, and the first-run offer is answered
  local h=$1
  mkdir -p "$h/.config/startdrive/demo"; : >"$h/.config/startdrive/demo/ENABLED"
  [[ -f $h/.config/startdrive/demo/ENABLED ]] || { echo "the sandbox could not be put in demo mode" >&2; return 1; }
  printf 'SETUP_DONE=1\n' >"$h/.config/startdrive/config"
}
DEVKIT_USAGE='  dev open | setup | settings DRIVE_ID | close'
dev_cmd_open() { nenv omarchy-shell -q "$ID" close 2>/dev/null || true; sleep 0.4; dev_window open "$ID" open; }
dev_cmd_setup() { dev_window setup "$ID" setup; }
dev_cmd_settings() { dev_window settings "$ID" settings "${1:?settings needs a drive id}"; }
dev_cmd_close() { nenv omarchy-shell "$ID" close; echo "dev close: closed"; }
```

It also has a bar widget (leave `TOUR_PLUGIN_WIDGET` at 1), keeps `dev move` (the kit has it), and its `tests/cli.sh` stays its own. Its tours' `TOUR_LAYER` is `DEVKIT_LAYERS`.

### StartAppImage

Also not yet tried. Its `devkit_sandbox` is the part that copies each AppImage a manifest names into the sandbox and points the `EXEC=`, `DESKTOP=` and `Exec=` paths at the copies (today `sandbox_repoint` in its `session.sh`), with `TOUR_SANDBOX_COPY=(.local/share/startappimage .local/share/applications)`. Keep that function as it is, in `devkit.conf`.

### The commands that came later

| Was (a script in each app) | Is |
|---|---|
| `scripts/pointer.sh` | `bin/pointer`. `click`, `move` and `pos` use the pixels of a screenshot of the focused monitor (StartDrive's, StartAppImage's). StartBar's `move X Y` took global layout coordinates: that is now `warp X Y`. `reveal`, `left`, `right`, `shot` are as StartBar's; `key` is allowed only into the classes in `DEVKIT_KEY_CLASSES` (StartBar: `(startbar-screenshot spare-test)`) |
| `scripts/reload` | `bin/reload`. Link (StartBar), copy (StartDrive) and clone (StartAppImage) are found from the installed folder. The window names and what opens them are `reload_open` in `devkit.conf`; `DEVKIT_RELOAD_READY=state` for StartDrive |
| `scripts/lint-qml.py`, `qmllint-check.js` (`npm run lint:qml`) | `bin/qmllint`, with the same baseline file. StartBar's JS version had no list of warnings that can never be baselined; this has |
| `scripts/check.sh`, `lint-sh.sh`, `lint-rules.sh` | `bin/check`, with the app's own tests in `devkit_check` |

| `.githooks/pre-commit` | a two-line hook calling `bin/pre-commit` (`pre-commit --install` writes it). StartBar sets `DEVKIT_PROTECT_BRANCHES=()` and `DEVKIT_CHECK_CMD=(npm run --silent check)` to keep what it does now |
| `.github/workflows/check.yml` | the triggers stay in the app (StartBar also builds `release/**`); the job is `uses: …/app-check.yml@vX.Y.Z` |
| `scripts/open-release.sh` | `bin/release-branch` |
| `scripts/try-setting.sh` | `bin/try-setting`; StartBar's default command (`omarchy-shell ID layout`) becomes `try_default` in its `devkit.conf` |
| `scripts/spare.sh`, `scripts/hypr-events.sh` | `bin/spare`, `bin/hypr-events`. The spare window's class is still `spare-test`, which `pointer key` allows by default |

Not moved: `screenshots.sh`, `preview.sh`, `make-preview.sh`, `clips.sh` and `hero.sh`. What they do is mostly the app's own (which windows, in which order, at which pixels, composed how), and the part that is common is a few lines of ImageMagick.

## Checking nothing broke

Per app, before deleting the copy: on a branch, add the kit and the conf, remove the copied files, and compare.

1. The app's own check (`scripts/check.sh`, `npm run check`) passes.
2. `scripts/dev up`, open each window with the app's commands, `dev shot` each, `dev errors` is 0, `dev down`.
3. Its smoke test and screenshots script give images of the same sizes as before (StartBar's did: 790×72, 276×209, 512×253 ...).
4. One tour, with the same crop, comes out the same length and size (StartBar's start-menu clip: 220 KB before, 224 KB after), and "your real files are unchanged" is printed.
5. The guard did its work: click the plugin's power buttons if it has any, and see `dev status` count the refusals.

StartBar's was done this way in a scratch checkout before the kit was published; the result is above. When the kit changes, update the three apps one at a time with moving the submodule's pointer, and run the same list.
