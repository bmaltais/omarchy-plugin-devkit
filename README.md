# omarchy-plugin-devkit

Test and record an [Omarchy](https://omarchy.org) shell plugin in a **second desktop that your mouse and keyboard cannot reach**, with a guard that keeps a click inside it from acting on your machine.

- **`dev`**: start a nested Hyprland and Omarchy shell running your plugin from your checkout, then drive it: click, right-click, scroll, hover, type, screenshot, read what the plugin logged, reload after an edit. Nothing of yours is restarted, moved or changed.
- **`tour`**: record a short animation (AVIF or GIF) of the plugin being used, with captions and a human-looking pointer, for a README or a marketplace page. The same session, filmed.
- **`sheet`**: turn a recording into one contact sheet image, so you can check the whole of it at once.
- **`reload`**: put your checkout in your REAL shell (a link, a copy or a git clone, whichever the plugin is installed as), restart it, open a window, and report what the plugin logged. For after `dev`.
- **`pointer`**: click, hover and screenshot by the pixels of a screenshot, with your real pointer. For the live shell; `dev click` is the nested session's.
- **`check`**: one command for the pre-commit hook: shell scripts (bash -n, shellcheck), `lint`, `qmllint`, the manifest, and the app's own steps.
- **`qmllint`**: fail on any QML warning the app's baseline does not list (qmllint cannot see the shell's types, so hundreds are standing noise; a new one is a misspelt name).
- **`pre-commit`**: the git hook: refuse a commit on `main`, run `check`. `bin/pre-commit --install` writes `.githooks/pre-commit` and points git at it.
- **`try-setting`**: try a setting on your real shell, run a command, put your `shell.json` back.
- **`spare`**, **`hypr-events`**, **`release-branch`**: a throwaway window to test Hyprland calls on; a timestamped log of focus and window events; the open `release/<version>` branch.
- **`.github/workflows/app-check.yml`**: a reusable GitHub workflow that runs `check` for an app (`uses: …/app-check.yml@v0.2.0`).
- **`lint`**: project rules for the scripts that drive it, each one a mistake that cost a session.

It came out of three Omarchy plugins ([StartBar](https://github.com/bmaltais/StartBar), [StartDrive](https://github.com/bmaltais/StartDrive), [StartAppImage](https://github.com/bmaltais/StartAppImage)), which each had a copy and were tired of restarting their own shell, taking over their own pointer and filming a screen that had their windows on it.

```
you ── dev up ──► a nested Hyprland (a window of yours, parked on a virtual monitor 20,000 px to the right)
                    └─ quickshell: the Omarchy shell + your plugin, linked from your checkout
                    └─ a home of its own, and a guard in front of PATH
you ── dev click / type / shot / ipc ... ──► the session's own Wayland socket (a virtual pointer, wtype, grim)
you ── tour tours/hero.sh ──► the same session, filmed, with captions ──► screenshots/hero.avif
```

## Why it is safe to click in it

The nested session shares your user's systemd, your login session and your system bus. A plugin with a Shut down, Sleep, Lock or Sign out button would, when clicked in the session, run the real command. So the session runs with a **guard** first on its `PATH`: a stand-in for each of those commands (`omarchy-system*`, `poweroff`, `reboot`, `shutdown`, `hyprlock`, `uwsm`, and the power verbs of `systemctl` and `loginctl`) that refuses and writes the attempt to a log. The session is not started unless a login shell finds the guard first, and a probe proves it refuses, without ever passing a command to the real tool. `tests/guard.test.sh` holds it to that. Your pointer and keyboard are switched off inside the session, and the session's window is never put under your pointer.

## Use it

1. Add the kit to your plugin's repository as a **submodule** (`git submodule add <url> scripts/devkit`, then check out a tag): development tooling does not ship to users who install the plugin, and a marketplace review sees the plugin, not the kit ([docs/adopting.md](docs/adopting.md)). Or clone it beside the plugin.
2. Add a `devkit.conf` at the root of your plugin: at least its id.

   ```bash
   TOUR_PLUGIN_ID=io.example.hello
   TOUR_PLUGIN_WIDGET=0          # a service, not a bar widget
   DEVKIT_LAYERS=(omarchy-hello) # the layer-shell name of your window, so keys go only where it is up
   ```

3. Run it:

   ```sh
   export DEVKIT_APP_ROOT=$PWD          # or run it from the plugin's checkout, or add a two-line wrapper (docs/adopting.md)
   scripts/devkit/bin/dev up            # a session, and a view-only window of it on your screen
   scripts/devkit/bin/dev ipc io.example.hello open
   scripts/devkit/bin/dev shot /tmp/a.png
   scripts/devkit/bin/dev errors        # 0 = the plugin logged nothing
   scripts/devkit/bin/dev down
   ```

`examples/hello` is a complete small plugin with a `devkit.conf`, wrappers and a tour: `cd examples/hello && ./dev up && ./dev open && ./tour tours/hello.sh`.

## Needs

Hyprland (the 0.56 Lua API: `hl.dsp.*`, `hl.monitor`, `hl.device`) on Omarchy, run from inside your Hyprland session. `hyprctl`, `jq`, `grim`, `wtype`, `quickshell`, `dbus-run-session`, `perl`; and for the pointer client, built on first use: `gcc`, `wayland-scanner`, `pkg-config` with `wayland-client` (Arch: `wayland`, `wayland-protocols`, `gcc`). `reload` also needs `omarchy-shell` and `journalctl`; `pointer` needs `ydotool` and a writable `/dev/uinput`; `qmllint` needs `qt6-declarative`. For `tour` and `sheet`: `ffmpeg` (with `drawtext`, and `libaom-av1` for AVIF), ImageMagick, `notify-send`. Each command checks and says what is missing.

## Documents

- [docs/configuration.md](docs/configuration.md): every variable and hook of `devkit.conf`, and what a tour file sets.
- [docs/testing.md](docs/testing.md): the test session, its commands, and how a plugin's own scripts (smoke tests, screenshots) use it.
- [docs/recording-tours.md](docs/recording-tours.md): writing and recording tours.
- [docs/how-it-works.md](docs/how-it-works.md): the design, and what went wrong on the way to it.
- [docs/adopting.md](docs/adopting.md): moving a plugin onto the kit, and what changed against the copies the three Start apps carry.

## Limits

One session at a time, one monitor, Hyprland only (a different Hyprland Lua API will need changes in `lib/session.sh`), and an Omarchy shell is assumed (`omarchy-shell`, its config layout).

## Status

0.2.0: adds `reload`, `pointer`, `check`, `qmllint`, `pre-commit`, `try-setting`, `release-branch`, `spare`, `hypr-events` and a reusable `app-check` workflow, the scripts the three Start apps each carried. 0.1.x: the test session, recorder and guard, extracted from StartBar's copy; StartBar is on it, StartDrive and StartAppImage are next (docs/adopting.md).

MIT licensed.
