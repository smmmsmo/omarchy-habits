# Working on Habit Tracker

`mo.habits` is an optional Quattro bar widget for Omarchy 4.5. It is not an Omarchy core component or a standalone desktop app. The runtime is QML, JavaScript, and Python 3.11+ standard library. Node.js is only for tests.

## Where to start

| Change | Start here |
| --- | --- |
| Identity, entry point, and default placement | `manifest.json`, `BarWidget.qml` |
| Bar status, popup lifecycle, and helper orchestration | `BarWidget.qml` |
| Habit tabs, check-ins, calendars, archive, and settings | `HabitPanel.qml`, `StartDatePicker.qml`, `i18n/en.json` |
| Civil dates, scoring, streaks, and recovery | `Model.js`, `tests/model.test.cjs` |
| Transactions, privacy, migration, and export | `store.py`, `tests/test_store.py` |
| Build checks, UI test, and sample screenshots | `test/all`, `test/demo`, `test/demo.qml`, `test/seed_demo.py` |
| User and Marketplace documentation | `README.md`, `SECURITY.md`, `SUBMISSION.md`, `docs/` |

## Contracts to preserve

- Keep `mo.habits` and its state path stable. Do not adopt `omarchy.*`, change the ID, or move the state file without an explicit migration plan. For Marketplace compatibility, keep the manifest's `defaultSection` to `left`, `center`, or `right`.
- The bar opens the selected habit's **Today** tab. **Today**, **Analysis**, and **Settings** belong to that habit. Do not add a second all-habits check-in or repeat streaks and archive controls on unrelated screens.
- `BarWidget.qml` passes one bounded JSON line on standard input to `python3 -B store.py STATE_PATH`. The helper validates and emits one JSON reply. Update the Qt caller, Python helper, and tests together if this contract changes.
- Keep local date semantics, the inclusive ending date, and the distinction between manual answers, automatic answers, archived gaps, numeric zero, and pending days. Preserve saved data on migration and always update model and store tests together when rules change.
- No network access, telemetry, accounts, privileged actions, setup scripts, or separate runtime services. Keep state and exports private; do not write stock Omarchy files. Tests must use disposable state and fictional data.
- Use the Quattro UI kit and plain-text labels for user strings. Do not send habit names or questions to a shared tooltip that can render markup. Keep whole translation strings and preserve `%1`-style placeholders.

## Before handing off

1. Run `./test/all`; it is offline and validates the manifest if Omarchy is installed.
2. For UI or helper integration changes, run `./test/demo` in a disposable Quattro/Wayland session. Check the real controls and inspect the captures. See [docs/development.md](docs/development.md).
3. Update README and release notes for user-facing changes. Read [SUBMISSION.md](SUBMISSION.md) before preparing a publication handoff.
4. Do not inspect or alter the user's saved history or live install, push, change repository visibility, or open a public issue unless the user has asked. The Marketplace also requires explicit owner approval of the exact submission and checklist.
