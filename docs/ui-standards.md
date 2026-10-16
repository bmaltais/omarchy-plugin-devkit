# UI standards for the Start apps

What is true of every Start app (StartBar, StartAppImage, StartDrive): how their windows, settings window and controls look and behave, and why. The goal is that they feel like each other and like Omarchy itself, so a person who knows one knows them all.

Each app keeps its own `docs/ui-standards.md` for what is its own: its windows, its settings tables, its words and its decision log. It starts by pointing here and does not repeat this file. When a decision changes something shared, change it here, then in the apps.

**An app's `docs/ui-standards.md` is the source of truth for its UI, and this file for the shared part.** Read both before you change anything visible. If a change makes a design decision that is not covered, or goes against something that is, update the file in the same change and add a line to that app's decision log. A UI change without a matching update is not finished.

Sizes are written the way the code writes them: `space(n)` is `Style.space(n)`, which follows the user's font and spacing scale. Never hard-code pixels, colours or fonts.

## Principles

1. **Follow the theme, always.** Colours, fonts, corner radius and spacing come from the shell (`Color`, `Style`, `Util.alpha`). Nothing is hard-coded, so the UI follows the Omarchy theme live. Muted text is the foreground at about 55% opacity, hairlines about 14%.
2. **Same as the family where they overlap.** StartBar's settings window is the reference *design* and StartAppImage's `SettingsWindow` the reference *implementation* (see [Shared UI code](#shared-ui-code)). When two apps disagree on a shared part, ask which is right, fix the other one, and fix this file if it is the one that is wrong.
3. **Changes happen when you make them.** No Apply buttons for settings (see [Applying settings](#applying-settings)). A change that cannot be made says so, and goes back.
4. **The window you came from stays.** A window opened from another one floats over it; closing it brings the first back.
5. **Everything in the UI has a command-line equivalent.** The QML never edits files or runs system commands; it asks the app's CLI. A setting that exists in a window exists as an option of the CLI.
6. **Say what will happen.** Every setting has a one-line hint, written as what the setting does, in the present tense.
7. **Quiet by default.** Destructive or rarely used actions are small or soft buttons, never the loudest thing. Colour (accent) is for the one thing to do and for the selected state.

## Windows

**Which apps this covers.** The Manager rows, the sizes and the move-and-resize rules below are for the apps that have a manager window (StartAppImage, StartDrive). StartBar has none: its settings window is the reference *design* (layout, sizes, controls) but it moves by its top strip, centres on open, and does not resize or remember its place.

Every window of the apps with a manager is a card on a full-screen layer-shell overlay with a dimmed scrim. The card has the menu background, a hairline border at 14% foreground, the theme radius and a soft shadow.

- **Dismissing.** Esc closes only the topmost window. In a search box, Esc clears the text first. A click on the scrim closes the topmost window. (StartBar's settings window has no scrim: it is a transparent layer that takes input only on its frame, so a click outside reaches the desktop and you see the Dock change as you adjust it. A window that edits something visible on the desktop should not dim it.)
- **Stacking.** A settings window floats over the manager, which stays visible behind it under a 35% dark veil. Only one settings window is open at a time. Closing it returns the keyboard to the manager.
- **Opening.** The manager opens where the user last left it (see [Remembered state](#remembered-state)).
- **Close button.** A ✕ in the top-right corner of every card, 8 from the edges.

| Card | Width | Height | Moves | Resizes | Closes with |
|---|---|---|---|---|---|
| Manager | 640 (or the user's) | its content, up to 580 and the screen minus 80 | yes | yes | Esc, ✕, click outside |
| Settings window | 760 (or the user's); StartBar 780 | 520 (or the user's); StartBar 620; at most the screen minus 80 | yes | yes | Esc, ✕, click outside or on the dimmed manager |

A settings window for one thing inside the app (one drive's, one AppImage's) has the same size, place and way of closing as the app's own.

### Moving and resizing (manager and settings window)

- **Move** by dragging the top strip of the card, 60 high, whatever is not a control. The pointer is an open hand over it and a closed hand while dragging. Controls in the strip (search box, buttons) keep their own behaviour.
- **Resize** from the bottom-right corner: a 22 square handle with a small two-line grip and the diagonal resize pointer. The top-left corner stays put. Double-click it to go back to the default size and centre.
- **Limits.** The manager is at least 480 by 300, the settings window 560 by 360, both at most the screen minus 40. At least a 60 strip of the card always stays on screen.
- **Maths.** A card is centred plus an offset, so a resize shifts the centre by half the change.

### Remembered state

Size and position of each window are saved in the app's config file (`~/.config/<app>/config`: `WIN_*` for the manager, `SETUP_*` for the settings windows) and restored on the next open, even after a shell restart. Two switches control it, under the **Window** page: *Remember size* and *Remember position*. Switching one off forgets the saved value and opens centred, at the default size. They are read with `<app> window` and written when a drag or resize ends.

## Settings windows

Within an app every settings window is the same component (StartBar's lives in `Service.qml`; the other two share `SettingsWindow.qml`): `SettingsWindow.qml` draws the header, page list, rows and footer; a thin file per window (`SetupView.qml` for the app's, another for one item's) only says what the pages and settings are. A new settings window is a new thin file around `SettingsWindow`, never a new layout.

```
┌──────────────────────────────────────────────────────────┐
│                  ( 🔍 Find a setting )                  ✕ │  header, 60
│ Window name   │ Page name                                 │
│ SETTINGS      │                                           │
│ ▌Page         │ Label                           [●━]      │
│  Page         │ hint…                                     │  rows
│  Page         │ ───────────────────────────────────────── │
│               │ Label                    [A][B][C]        │
│ ───────────────────────────────────────────────────────── │
│ Changes apply instantly · Esc to close        [Pill]     ◢│  footer, 52
└──────────────────────────────────────────────────────────┘
```

- **Header (60).** A centred search pill, "Find a setting", with the magnifier glyph. While there is text, the right side lists matching settings from every page under "Search results", each group headed by its page name. No match says "No setting matches “…”."
- **Page list (190 wide, left).** The window name in bold with a small-caps line under it that says what the window is for ("SETTINGS", with a version or other detail after a "·" where useful): the same title-over-small-caps pattern as the manager's count line. Then one 38 high row per page. The title block and the page heading beside it are 48 high. The current page has a 22% accent fill and a 3 wide accent mark on the left, and bold text. Hover is the shell's hover fill. A click clears any search.
- **Heading.** The page name, body size + 8, bold, on the row of the window name.
- **Body.** Scrolls when the page is taller than the window, with the [scroll bar](#controls) in a gutter that is always reserved, so the width never changes.
- **Setting row.** The label (body size) with its hint under it (caption size, 55% opacity), the control on the right, a hairline at 50% under each row. The row is as tall as its label plus hint, with 6 above and below. A **note** can sit under the control, for what a change or button did: muted for information, accent for a done action, red for an error.
- **Disabled setting.** Dimmed to 40%, not clickable, and the hint says why. An option that depends on another is dimmed while that one is off.
- **Footer (52).** A hairline above it. On the left one muted line: "Changes apply instantly · Esc to close" (the code spaces the separator with three spaces, so the line reads the same in every app). On the right the window's pills, 30 clear of the resize grip.
- **Words.** Page names are sentence case and one word where possible.

A new setting goes on the page it belongs to, or a new page if none fits. Settings that live in the CLI's options are added to the window's `pages` list, to the CLI, and to the app's table of settings in its own `ui-standards.md`.

### Applying settings

- **Instantly.** Each click runs the app's CLI for that one setting. Clicks queue and run one at a time, in order, so a quick second click is never dropped.
- **Read back.** When the queue is empty the window reads the real state back, so a control always shows what the system has.
- **Failure.** A change that fails flips its control back on the read-back and says why: under the setting where the window can show it, otherwise a critical notification ("Setting was not applied" and the reason).
- **Window stays open.** Applying never closes the window.
- **Reset to defaults.** A soft pill. The first click turns it red and asks "Click again to reset everything" for 3 seconds; the second click applies the defaults. The defaults are the CLI's, not written in the QML.
- **First run.** For an app with opt-in setup to offer (StartAppImage, StartDrive), the settings window opens once, a few seconds after the plugin first loads, showing what is on now. The footer has **Not now** and an accent-filled **Enable recommended**. After the first change or **Not now** it never opens by itself again. An app whose defaults already work (StartBar) has no first run.
- **Text.** Esc drops what is typed in a text box and then closes the window: leaving never saves.

## Controls

All are inline components or small files in the app's repo and use only theme tokens. Where one is shared it is the same file in each app.

| Control | Look | Used for |
|---|---|---|
| **Switch** | 42 × 24 pill; accent when on, 25% foreground when off; round knob in the menu background, 3 inset; the knob slides 100 ms, but not while the page is first shown; pulses while busy | on/off settings |
| **Choice** | Row of segments 28 high, 2 apart; selected is accent-filled with menu-background text, others 8% foreground; caption size. With many or long options (`stacked`) the segments wrap across the full width under the label, 6 apart | one of a few or several options |
| **Chip** | Bordered rounded box; selected has a 18% accent fill and an accent border | picking from a few things, such as a folder |
| **Action** | A pill on the right of a row, 32 high, 8% foreground fill, hover fill, caption size | a button in a settings window |
| **Field** | Single-line text box, 34 high, 6% foreground fill, border brightens on focus. In a settings window it sits under its label at full width and commits on Enter or when it loses focus; Esc drops the edit | text input |
| **Pill** | 32 high, 8% foreground fill, hover fill, caption size; `primary` is accent-filled and bold; `danger` is 50% red | footer actions |
| **Button** | The shell's `Button`; bordered for secondary, selected for primary, icon-only on a row with a tooltip | dialogs, rows, header |
| **Scroll bar** (`ScrollTrack`) | 6 wide, soft track at 8%, rounded thumb at 28% that brightens on hover and press; drag the thumb or click the track; shown only when the list overflows | long lists and pages |

StartBar's settings window also has steppers, a slider and a list editor, for numbers and folders; they are specific to the Dock's settings.

Rules of thumb: one accent-filled thing per screen; selected means accent; hover is the shell's hover fill; nothing animates longer than 160 ms (a status dot and a busy switch pulse, which tells you something is running).

## Words

- **Case.** Sentence case for labels and hints.
- **Hints.** One or two short sentences, saying what happens. No "please", no exclamation marks.
- **Errors.** Say what happened and what to do. They appear next to what caused them (under the field), or as a notification when the window is gone.
- **Ellipsis.** A trailing ellipsis only when the action asks for more input (a terminal, a questionnaire, a file).
- **Search box.** "Find a setting" in a settings window.
- **Footer hint.** "Esc to close" appears at the bottom of every card that closes with Esc.
- **Names.** The window with the list is the **manager**; the other is the **settings window**; one item's own is its **settings**.

## The bar icon

Optional, switched in the settings window (whether it is on by default is each app's decision). A glyph at the end of the right section of the bar. Left click opens or closes the manager (the same command as the launcher entry); right click does the app's quick action. It reads its state from a small file under `~/.cache/<app>/` that the service rewrites whenever the state changes, so the icon never asks the app anything.

## Notifications

- **A problem or news.** A system notification, once per problem and again if it returns; not while the manager is open.
- **Setting failed.** A critical notification when the window cannot show it in place.

## Verifying a UI change

A change is done once it has been seen working in the test session: [testing.md](testing.md) (`dev`). Retake the README screenshots when the look changes, and the tour when a step of it changes ([recording-tours.md](recording-tours.md)).

## Shared UI code

The controls above, `SettingsWindow` and the drag-and-resize behaviour are meant to look and behave the same in every Start app. Each app keeps its own copy of the QML: a shared UI repository was considered and set aside, because the files are small, the apps differ in the details, and a change would then need a commit in two places and a version bump in three. The copies are kept alike by hand, so:

- **StartAppImage is the reference implementation.** StartDrive's copies are kept identical to its except for additions that belong upstream when the shared repo exists (they are listed in StartDrive's `ui-standards.md`).
- **StartBar's settings window is the reference design.**

## Recording a design decision

An app's `docs/ui-standards.md` ends with a **Decision log**: a table, newest first, one line per decision, with the date, what was decided and why (what went wrong, or what it is consistent with). Add the line in the same change as the code. Decisions about the test session or the recorder go in `docs/recording-tours.md` (or `testing.md`), not here. A decision that changes something in this file changes this file as well.
