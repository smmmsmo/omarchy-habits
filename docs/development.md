# Development guide

Start with [AGENTS.md](../AGENTS.md) for the file map and behavior to preserve. See the [README](../README.md) for user instructions and [SUBMISSION.md](../SUBMISSION.md) for publication.

## How a check-in reaches the bar

1. Quattro loads the single `bar-widget` entry in `manifest.json`. `BarWidget.qml` owns the bar, popup lifecycle, clock, and the helper process. `HabitPanel.qml` owns the currently selected habit, date, tab, and unsaved settings.
2. When a user records an answer, updates settings, or requests an export, the widget passes one JSON line over stdin to `store.py`. Only the state path is on the command line. There is no network or shell interpolation.
3. The helper rereads the state under an exclusive lock, validates the operation, and commits changes atomically. V1 and V2 history can migrate to V3, with a separate backup of the original. The helper returns `{ "ok": true, "data": … }` and optional operation details, or `{ "ok": false, "error": … }`.
4. `Model.js` projects the reply into the UI and calculates local-day status, date windows, calendars, streaks, and recovery. `HabitPanel.qml` uses the Quattro UI kit; user text is rendered as plain text.

## Check a change

```sh
./test/all
```

This needs Python 3.11+ and Node.js 22 (the CI version). It runs offline, uses disposable data, and additionally validates the manifest if Omarchy is installed.

For a real Quattro UI smoke test, use a disposable Wayland session:

```sh
./test/demo /path/to/empty/output-directory
```

This developer-only harness needs Quickshell, the Omarchy 4.5 UI modules, Python, and ImageMagick. It creates an isolated state directory, seeds fictional habits, loads the actual widget, and verifies switching habits, the stdin check-in path, undo, Week, Year, and Archive navigation. It does not install the plugin, read personal history, or change the live shell configuration. The separate test process exits after the run; the installed widget never starts a second shell.

For UI changes, also check what the automated smoke test does not cover:

| Area | Verify |
| --- | --- |
| Fresh install | Install with Omarchy's standard command in a test profile; enable and choose placement; first run offers **New habit**. Test disable, re-enable, and remove without losing history. |
| Navigation | Sidebar and narrow picker both open the selected habit's Today. Check light/dark themes, keyboard focus, Escape, short window heights, and horizontal/vertical bars. |
| History | Check Build and Quit scoring, zero versus pending for numeric habits, past-day correction, inclusive deadlines, midnight rollover, and archive/restore with history intact. |
| Data | Review defaults and migration with fixture files. Export CSV and JSON to a disposable state directory; verify the presented path and file modes. |

## Refresh screenshots

Use the `test/demo` command above. It captures the actual QML items with fictional data, composites the bar button into the main image, and strips metadata. It never captures the desktop background, notifications, or other windows.

1. Open the demo's `preview.png`, `week.png`, and `year.png`; check that they match the real controls and are legible.
2. Copy the reviewed `preview.png` to the repository root and the other two to `docs/screenshots/`. Keep screenshot alt text in the [README](../README.md#screenshots) current.
3. Never use personal check-ins, exported data, logs, shell configuration, or unreviewed desktop captures as fixtures or preview assets. Older release screenshots are historical, not installation instructions.
