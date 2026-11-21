# How it works, and what went wrong on the way

There are two backends (`DEVKIT_BACKEND`, [configuration.md](configuration.md#backends)). The **hyprland** backend is the picture below: a nested Hyprland that is a window of your compositor, the only one that can run a plugin (the Omarchy shell needs Hyprland). The **headless** backend, the default for a standalone app, is [at the end of this page](#why-a-headless-backend): same sandbox, guard, input path and ledger, a different compositor.

```
dev ──► lib/session.sh ──► Hyprland (nested) ──► quickshell: the Omarchy shell + your plugin
 │        (sandbox, guard, start, stop)    │ a window of your compositor, moved to a virtual monitor
 │                                         │   at x = 20000, which a real pointer cannot reach
 ├─ click, move, rclick, scroll ► lib/vptr (a virtual-pointer client) on the session's socket
 ├─ type, key ───────────► wtype (virtual keyboard), on the session's socket
 ├─ shot ────────────────► grim, on the session's socket
 ├─ ipc, dev_cmd_* ──────► omarchy-shell, on the session's socket (the plugin's IPC)
 └─ errors ──────────────► the session's shell log, filtered
```

- **`lib/session.sh`** builds the sandbox home (Omarchy's themes copied, a `shell.json` that keeps your bar layout but only Omarchy's own widgets, with the plugin's entry holding `TOUR_PLUGIN_ENTRY`, the plugin linked to the checkout), builds the guard, starts the nested Hyprland under its own D-Bus that starts nothing, and stops everything it started. `dev` and `tour` both source it.
- **App mode** (`DEVKIT_APP_CMD`) swaps the shell for the app: the nested Hyprland's start hook runs `app-launch`, a script `lib/session.sh` writes into the session's folder (sandbox XDG dirs, `QT_QPA_PLATFORM=wayland`, `TOUR_APP_ENV`, the working directory, stdout and stderr to `app.log`, the exit status to `app.exit`). No `shell.json` and no plugin link are built, the guard and the input path are the same, and "the window is up" means a mapped client matching `DEVKIT_APP_CLASS` or `DEVKIT_APP_TITLE` instead of a layer-shell namespace. Like the shell, the app starts only once the session's window has its final size.
- **Input.** `lib/vptr.c` is a tiny client of the `wlr-virtual-pointer` protocol (built on first use into the session's folder; it can move, click, right-click, scroll and drag). Keys use `wtype`. Both talk to the nested compositor's socket, so nothing reaches your real seat. The virtual pointer produces real motion, so a hover opens a popup the way a real mouse's does.
- **`DEV_WINDOW=1` skips the far monitor and the view window.** It floats the session's window at the session's size in the middle of your screen. Your input cannot reach it (next item), so only the cursor image is left to the nested compositor: it hides the pointer while it is over the window. Opt in; the default stays the far monitor, which has no such effect. Unlike the far-monitor window, this one is not marked `no_focus`, so you can move it with your usual binding (Omarchy's Super+drag); `no_follow_mouse` stays, so hovering never gives it the focus.
- **Your mouse and keyboard are switched off inside the session.** The host seat gives the nested compositor two devices, `wl_pointer` and `wl_keyboard`; its config disables both (`hl.device({ name = ..., enabled = false })`). The virtual devices are separate and keep working.
- **The far monitor.** `up` creates a headless monitor 20,000 px to the right and moves the window there. Sliding a mouse off the edge of your screen stops at the edge, so the window cannot be reached. `down` removes the monitor (which warps your cursor, see below).
- **The window is floated with `action = "on"`, then checked.** Hyprland's toggle parser knows only toggle, on, enable, off and disable, so `"set"` fell through to toggle and tiled a window that floated already; Omarchy's workspace-modes hook then re-floated it at 64% x 68% of the work area (819x492). `dev up` now fails, before it writes its state, unless the window floats at the asked size and the nested monitor has it too, and `bin/lint` flags `action = "set"`.
- **The shell starts last.** Hyprland starts the session's shell only once the window has its final size (`nested_send_away` creates a file the start waits for). Started earlier, the shell keeps reporting the window's first size as its screen's, and a plugin that works out where things are from its screen then answers with pixels that are wrong by the difference.
- **The noise filter.** `dev errors` and `dev reload` count only lines that name the plugin (`TOUR_PLUGIN_ID`) and carry a warning or error, minus known noise (layout "recursive rearrange", "Local plugin changed", qmlscanner, portal, `qt.svg`, and `DEVKIT_NOISE`). Omarchy's own errors are not the plugin's and are not counted.
- **The recorder** (`bin/tour`) films the same session: a `grim` frame over and over, each stamped with its time, joined with `ffmpeg`'s concat demuxer so the video plays at the speed things really happened, captions drawn with `drawtext`, the result an animated AVIF or a GIF. A red strip (`lib/tour-banner.qml`) with a Cancel button sits on your screen while it films, and the run's frames (about 1.5 GB) are removed when it ends.

## What a host window cannot avoid

The session's window is a window of your compositor, so it cannot be made free of effects on your desktop:

- Its window opens (map, focus and workspace events), and `up` and `down` create and remove a monitor.
- **Removing the far monitor always warps the real cursor.** Hyprland's `Monitor::onDisconnect` force-warps it and nothing turns that off. `down` therefore moves your cursor once.
- `up` keeps the rest quiet: the window is moved to the far monitor with `follow = false` (the silent path; the default move focuses the window and warps the cursor to it), and focus is no longer handed back (that warped it again). The view window is off unless `DEV_WATCH=1` (it took the focus).
- Only a headless backend, a compositor that is not a window of the host's, avoids all of this: it is [built](#why-a-headless-backend), for apps. On this backend "your mouse and keyboard cannot reach it" means the session cannot be *driven* by them, not that starting and ending it leaves them alone.
- The session's input never goes to your compositor: `vptr` (and `wtype`, through `vptr probe`) refuse a Wayland socket unless every output on it is named `HEADLESS-n` or `WAYLAND-n`, and refuse your own socket. `bin/pointer` (your real pointer, for the live shell) refuses under `dev`, `tour` and the tests (`DEVKIT_NO_REAL_INPUT=1`).

## Why a headless backend

An investigation of why the host-window session moved the owner's real pointer found a floor under everything the nested Hyprland does: **a window of your compositor can never be made event-free.** Its window maps and takes focus events; moving it to the far monitor and giving focus back each warped the cursor (`window.move` without `follow = false`, then `hl.dsp.focus`); and removing the far monitor force-warps in `Monitor::onDisconnect` whatever `cursor:no_warps` says. About three warps per `dev up` and `dev down`, and an agent that restarts the session in a loop gets dozens. The warps could be reduced, not removed.

So for an app the session has no window of yours at all. It runs in **sway** (the wlroots compositor, 1.12 here) with `WLR_BACKENDS=headless`: one virtual output and no input device, created inside sway, with no connection to your compositor, your seat or your GPU:

```
dev ──► lib/session.sh ──► lib/headless.sh ──► dbus-run-session ─► sway -c nest/sway.conf   (private XDG_RUNTIME_DIR, HEADLESS-1)
 │                                                                  └─ app-launch ─► your app (sandbox home, software GL)
 ├─ click, move, rclick, scroll ► lib/vptr (wlr-virtual-pointer) on the session's socket
 ├─ type, key ───────────► wtype (virtual-keyboard), on the session's socket
 ├─ shot, tour frames ───► grim (wlr-screencopy), on the session's socket
 └─ status, windows ─────► swaymsg -s the session's sway socket (get_tree, get_outputs)
```

- **Nothing of your desktop is in its environment.** sway is started with `env -u` for `WAYLAND_DISPLAY`, `DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE`, `HYPRLAND_CMD`, `SWAYSOCK` and the rest, `WLR_BACKENDS=headless`, `WLR_LIBINPUT_NO_DEVICES=1`, `WLR_RENDERER=pixman` and a private 0700 `XDG_RUNTIME_DIR` (`nest/rt` under the session's folder); `headless_assert_clean` checks the result and the session is not started otherwise. Its Wayland socket (`wayland-1`) and its IPC socket are in that folder, not in yours.
- **Every client is given that socket by absolute path and the private runtime folder** (`nest_client`), so a socket that vanished is an error, never a fall back to yours. `vptr` also refuses (exit 3) unless `WAYLAND_DISPLAY` is inside the folder it is told (`DEVKIT_ONLY_SOCKET_UNDER`) and every output is named `HEADLESS-n` or `WAYLAND-n`. `swaymsg` is always given `-s` with the session's socket.
- **sway implements what the input path needs unchanged:** `wlr-virtual-pointer`, `virtual-keyboard` and `wlr-screencopy`, so `vptr`, `wtype` and `grim` are the same programs as on the other backend. With no input device of its own the seat has a pointer or keyboard only while a `vptr` or `wtype` command runs, so the first key of `dev type` is held back 300 ms and a client may log that its pointer or keyboard left without entering (foot does; `dev errors` leaves that line out).
- **Qt needs software GL.** The pixman renderer exports no dmabuf, so a GL client cannot use the GPU's driver; `LIBGL_ALWAYS_SOFTWARE=1` and the Mesa EGL vendor file make Mesa's llvmpipe draw into shared memory. It is slow but exact.
- **The app starts once the screen has its size** (`swaymsg exec`, after the output is checked to be `HEADLESS-1` at `WxH`; a wrong size fails `dev up` before it writes its state), and is a child of sway with the sandbox home and the guard. A single tiled window with no borders or gaps fills the screen.
- **The ledger** writes down the sway process (`sway PID`, ended only if the pid is still a sway) and the private runtime folder (`dir`), as it creates them; `dev down`, a failed start, Ctrl+C and the next run undo the list. There is no monitor and no instance folder to remove.
- **The view window is not part of it**: it is a window on your desktop, so it is refused (`DEVKIT_BACKEND=hyprland`, or look with `dev shot`). The recorder draws no strip either.
- **`dev selfcheck`** is the canary ([testing.md](testing.md#proving-your-desktop-sees-nothing-dev-selfcheck)).

A plugin still needs the other backend: running Hyprland itself headless is not possible (aquamarine's headless backend has no allocator), and the Omarchy shell is Hyprland's.

## The guard

The session shares your user's systemd, login session and system bus. So it runs with a guard first on its `PATH` (`sandbox_guard` in `lib/session.sh`):

- **Refused whatever the arguments:** `omarchy-system`, `omarchy-system-lock`, `-sleep-lock`, `-sleep-monitor`, `-lid-close`, `-lid-inhibit`, `-wake`, `-factory-reset`, `-factory-reset-finish`, `poweroff`, `reboot`, `shutdown`, `halt`, `hyprlock`, `uwsm`, and whatever `DEVKIT_GUARD_EXTRA` adds. (`omarchy-system-lock` also kills the screensaver and locks 1Password, whichever session runs it.)
- **Refused for the verbs that act on the machine or the login session, passed on for anything else:** `systemctl` (`poweroff`, `reboot`, `suspend`, `hibernate`, `hybrid-sleep`, `halt`, `kexec`, `rescue`, `emergency`, `exit`, `isolate` ...) and `loginctl` (`lock-session`, `terminate-*`, `kill-*`, `poweroff`, `reboot`, `suspend` ...). The shell reads unit states, so the rest must work.
- **Each refusal is written to `guard.log`** in the session's folder, and `dev status` counts them.
- **The session is not started unless the guard works** (`guard_check`). A login shell (which a plugin's `bash -lc` is, and which reads `/etc/profile`, and can rebuild `PATH`) is asked where each of the commands is, and the check stops if one is not the guard's. Then five commands are run in *probe mode*: the `systemctl` and `loginctl` stand-ins never pass a command on, so a verb the guard fails to refuse is reported and **not run**: a wrong list cannot suspend the machine the check runs on. This was caught by breaking the list on purpose.
- **`GUARD_SYSTEMCTL` and `GUARD_LOGINCTL`** name the real programs, so a test can put a stand-in there (`tests/guard.test.sh` does).

## What went wrong on the way, and the rule it left

Each of these cost a round of testing; they are why the design is what it is.

- **Never put the nested compositor's window under a real pointer.** While a pointer is over it, the nested compositor chooses the cursor image: it hid the pointer, showed a hand, and left the pointer behaving oddly after a window drag. A transparent *shield* over the window cured the input but showed a "block" cursor and stopped the window being dragged. Hence the far monitor for the session and the separate view window for watching.
- **Do not change the nested compositor's cursor options at runtime** (`hl.config({ cursor = ... })` through `hyprctl eval`): it crashed the nested Hyprland.
- **A reused socket name hid the session.** The nested compositor's socket is `wayland-N` and the number is reused, so finding "the new socket" by a name that was absent before failed after an aborted cleanup left a stale file. It is found by being created after the start, and `down` removes its own socket and instance folder.
- **`pgrep -f` matches its own shell.** Find processes by an environment marker (`procs_with`) or use a `[x]` bracket pattern.
- **Plugin reload does not load QML.** Only a full shell restart does; `dev reload` does that restart, in the session.
- **A background process that keeps the caller's output open makes `dev up | tail` hang.** Every detached launch ends in `>/dev/null 2>&1 </dev/null`; `bin/lint` fails on one that does not.
- **A shell that starts before its window has its final size reports the wrong screen.** A plugin's `layout` put things 188 px left and 38 px high of where they were. The shell now starts after the resize.
- **A window moved off the workspace in view is still the "active window".** A plugin that puts focus back to the window that had it after a hover then switches to that window's workspace, and a film stays on the wrong workspace for good. After posing windows on other workspaces, switch to them and back (`hyprctl dispatch 'hl.dsp.focus({ workspace = "N" })'`), which clears it.
- **A recording left 1.5 GB in `/tmp`, and `/tmp` is memory.** A few runs filled it, and then everything that writes there failed, the session included (a recording that took 92 seconds took 153 and showed the wallpaper for a minute). `tour` removes its folder when it ends; `TOUR_KEEP_TMP=1` keeps it for a run that went wrong.
- **A `[[ x ]] && cmd` as the last line of a loop or function kills a `set -e` script** when the test is false. `sandbox_enter` did, and `dev up` exited with no message. Use `if`.
- **A recorder must never walk a cloud mount.** `TOUR_REAL_UNCHANGED` fingerprints its paths recursively (`find -xdev`); one that named a live drive spent minutes walking it and looked hung.
- **ffprobe reads one frame of an AVIF.** It shows the still cover image first; the animation is the second video stream (`-f mov -map 0:v:1`). `bin/sheet` does this for you.
- **A popup that closes itself a moment after it opens** (a plugin's, found in StartBar). A popup with a compositor grab (`grabFocus`) is sent a pointer enter at its corner the moment it opens, before the compositor has placed it, whether or not the pointer is near. Hover handling that treats that as "the pointer entered the menu" and the next motion as "left" closes the popup 300 ms later. It showed on a bar at the top or left edge, where the popup opens next to the pointer (probably why not on the others). The Wayland log shows it: run the session's shell with `WAYLAND_DEBUG=1` and read the `wl_pointer.leave`, `wl_pointer.enter` (at -0.0078,-0.0078) and `xdg_popup.configure` lines. The fix is in the plugin: ignore hover changes for the first quarter second after a popup opens.
- **A plugin that keeps state in a file of `$XDG_RUNTIME_DIR`** (a lock, a saved focus) shares it with your real shell: the session uses the same runtime directory, because the nested compositor needs your compositor's socket there. StartBar's Peek did, and a Peek in the session could restore the wrong workspace on the real desktop. Name such files for `$HYPRLAND_INSTANCE_SIGNATURE`.

## Limits

- **Hyprland only, and a newer Hyprland than 0.56 may change the Lua API** (`hl.dsp.window.move`, `hl.device`, `hl.monitor`) that `lib/session.sh` uses.
- **One session at a time** (a fixed state folder per app and monitor name). A `tour` and `dev` use different monitors but would race for the nested compositor's socket: do not run both.
- **One monitor.** A plugin with something per monitor needs the real desktop to try a second one.
- **The view window is a picture, not the session**: five frames a second, so a fast animation looks choppy.
- **`dev` has no drag** (`vptr` can; the recorder's `drag` uses it).
