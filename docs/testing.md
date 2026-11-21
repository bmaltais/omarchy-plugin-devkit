# Testing a plugin in the session: `dev`

`dev` runs your plugin in a second Hyprland with its own Omarchy shell (or, for a standalone app, the app in a headless sway: [below](#a-standalone-app)), driven over its own Wayland socket. Your plugin is linked from your checkout, so a reload loads what is on disk, uncommitted files too. [how-it-works.md](how-it-works.md) says how it is built and why; [configuration.md](configuration.md) what the plugin tells it. `dev --help` is the reference.

**The rule: try changes here, not on the real desktop.** A restart of your real shell makes the bar blink and closes its popups; a click or key sent to it moves your pointer and types into your windows; the plugin acts on your real windows and files. The session has none of that.

```sh
dev up                       # 10 s. a nested desktop, out of your mouse's reach, and a window showing it live
dev ipc io.example.hello open     # call the plugin's IPC there (omarchy-shell TARGET METHOD ARGS)
dev run foot -a foot sleep 600    # start a program in the session: a window to look at (run it twice for two)
dev shot /tmp/a.png          # screenshot it, then look at the file
dev click 640 446            # click the pixel you saw (rclick for the right button, scroll PX PY N for the wheel)
dev move 78 776              # move the pointer there: hovers fire, as with a real mouse
dev type hello               # type into the window that has the keyboard; key Return presses a key
dev set '{"colorScheme":"light"}'   # change the plugin's settings in the session's shell.json; a plugin that watches it follows at once
dev errors                   # what the plugin logged, noise removed (0 = clean)
# edit a .qml file ...
dev reload                   # 5 s. restarts the nested shell only
dev down                     # always, when done
```

Every command prints one line and exits non-zero when it did not do what it says (`dev reload FAILED ... qml-errors 2`, `dev open: the window did NOT open`).

- **Pixels** are the session's screen, 1280×800 by default (`DEV_SIZE=1920x1200 dev up` for a larger one), 0,0 at the top-left, exactly as in a `dev shot`. Read the pixel off the screenshot and click it; nothing is scaled or offset. A plugin that can report where things are (an IPC `layout` returning pixels) saves finding them in a picture.
- **The session starts from your plugin's defaults**, plus `TOUR_PLUGIN_ENTRY`. It has no windows but the ones you `run`, and no data of yours.
- **No commit or push is needed**, and your real shell is never restarted.
- **It closes itself** after `DEV_TTL` seconds (default 1800), and a stale session is cleaned up by the next `up`. End it yourself with `down`: it holds a virtual monitor and about a dozen processes.
- **`dev env`** prints shell code that puts a script in the session's environment (`eval "$(dev env)"`): its home, its guard first on `PATH`, its compositor. A plugin's own script (a screenshots script, a smoke test) can run `hyprctl`, `omarchy-shell` and `foot` there that way. Do it in a subshell: `( eval "$(dev env)"; hyprctl clients -j )`, so the script keeps your real home for `dev` itself.
- **Watching the session's own window:** `DEV_WINDOW=1 dev up` keeps the session's window on your screen (floating, at the session's size, centred) instead of the far monitor and view window. Hovering, clicking or typing over it does nothing, because the nested compositor ignores your mouse and keyboard; the pointer is hidden while it is over the window, and a drag of the window can leave it odd until it moves again. No view window opens. Use `dev watch` if you want one as well.
- **Watching it:** ``dev watch` opens a view-only window (`lib/dev-view.qml`) showing the session five times a second (`DEV_WATCH=1 dev up` opens it with the session; off by default because a new window takes the keyboard focus and warps your cursor; `dev unwatch` closes it). It is an ordinary window: your pointer is the normal arrow over it, and a click does nothing there. The session's own window is never put on your screen (see [how-it-works.md](how-it-works.md#what-went-wrong-on-the-way-and-the-rule-it-left)).

## A standalone app

With `DEVKIT_APP_CMD` in `devkit.conf` the session runs your app instead of the Omarchy shell, **in a headless sway by default** (`DEVKIT_BACKEND=headless`: no window, monitor, focus or seat on your desktop, nothing for your Hyprland to notice; [configuration.md](configuration.md#backends)), and the commands above work the same way against it (`DEV_WINDOW`, `DEV_WATCH` and `dev watch` are not part of it): `dev up` (starts the session and the app, fails when the app shows no window), `dev shot`, `dev click`, `dev type`, `dev key`, `dev errors` (what the app printed to stdout and stderr, noise removed), `dev reload` (restart the app, to pick up a rebuild), `dev down`. `dev ipc` and `dev set` are plugin-only. The app runs with a sandbox home, `QT_QPA_PLATFORM=wayland` and the session's Wayland socket. [configuration.md](configuration.md#standalone-app) has the variables.

```sh
cmake --build build && dev up       # fugue: DEVKIT_APP_CMD=(build/fugue)
dev shot /tmp/a.png                 # look at it
dev click 25 13                     # the File menu
dev errors                          # 0 = nothing logged
cmake --build build && dev reload   # new binary, same session
dev down
```

A Qt app draws in the headless sway with Mesa's software renderer, so it is slower than on your GPU and `dev up` can take a few seconds more; a screenshot is the same picture. `dev status` says `headless`. The first key of a `dev type` is held back 300 ms so it is not lost (`DEVKIT_HEADLESS_KEY_WAIT`).

## Proving your desktop sees nothing: `dev selfcheck`

The headless backend is built to cause no event on your Hyprland: no window, no monitor, no focus, no seat. `dev selfcheck` checks that on your machine. It listens read-only to your compositor's event socket (`socat -u`, which never sends), takes the monitor list, the window list (addresses and the session's pids) and the `ydotoold` count, runs `dev up`, `dev shot`, `dev click` and `dev down` and compares after each. It fails and ends the session the moment your Hyprland logged an `activewindow`, `focusedmon`, `monitoradded` or `monitorremoved`, `openwindow`, `closewindow` or `workspace` event (and the like), a monitor or window changed, a process of the session is a window of yours, or a `ydotoold` appeared. It only means something with your hands off the mouse and keyboard (a focus event you caused looks like one the session did), so it refuses unless you set `DEVKIT_SELFCHECK_OK=1`. Normal runs of the backend do not need it.

```sh
DEVKIT_SELFCHECK_OK=1 dev selfcheck          # then keep your hands off for ten seconds
DEVKIT_SELFCHECK_OK=1 DEVKIT_SELFCHECK_EXTRA='status;type hi;key Return;reload' dev selfcheck   # more commands under the same watch
```

`DEVKIT_SELFCHECK_CLICK="X Y"` is where it clicks (default `1 1`). The log is in `$XDG_RUNTIME_DIR/NAME-selfcheck/`.

## A plugin's own scripts

The kit has no smoke test or screenshots script, because what they open is the plugin's. They are short, built from `dev`:

- **A smoke test**: `dev up`, `dev run` a window if the plugin shows windows, open each of the plugin's views and `dev shot` it, `dev errors` (fails on anything the plugin logged), `dev down` in a `trap`. Read the screenshots: it only knows the plugin loaded quietly.
- **Retaking README screenshots**: the same, and crop each shot to the rectangle the plugin reports for the thing (`dev shot`, then `magick -crop`); park the pointer off the subject first (`dev move`).
- **Real-desktop checks** (a real mouse drag, a second monitor, your Hyprland configuration) are not what the session is for; keep a script for them in the plugin, and say in its header that it acts on the real desktop.

[StartBar's](https://github.com/bmaltais/StartBar/tree/main/scripts) `smoke.sh` and `screenshots.sh` are examples.

## The checks that need no session

`bin/lint ROOT` checks the scripts of a checkout against the kit's rules (a background launch must redirect its output; a sandbox must not copy or link the real `shell.json`). Run it in the plugin's check script. The kit's own tests are `tests/run.sh` (no Hyprland needed, and none of them can touch your input or your desktop: the tripwire in `tests/lib.sh` stands in for `sway` and `swaymsg` as for `hyprctl`, and the headless tests stub them explicitly: sway's generated config, the environment it is started with, the start and stop, the window check, the ledger and the canary's comparison).
