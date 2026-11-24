# Security and privacy

Use [GitHub private vulnerability reporting](https://github.com/smmmsmo/omarchy-habits/security/advisories/new) if enabled. Otherwise contact the maintainer privately before sharing technical details. Do not post personal habit names, questions, messages, history, exports, shell configuration, or unreviewed logs in a public issue.

- The widget is offline. It has no telemetry, account, remote dependency at runtime, or separately installed service. Omarchy plugins are unsandboxed and run as the current user.
- The Python helper receives check-in operations on standard input. The state file, backups, and exports are written locally with `0600` permissions. They are not encrypted. Treat them as private and review them before sharing.
- The normal install, update, and removal commands use Omarchy's plugin manager. The plugin does not install packages, request privileges, or overwrite Omarchy configuration. Archive and export are explicit user actions.
- Marketplace compatibility and the Automated Security Baseline apply to a specific commit. Neither is a security audit, endorsement, or guarantee.

## Permanent local removal

Uninstall the widget first. The plugin manager does not delete history. If you choose to erase it, review the widget's local files, then use the interactive removal commands below. These commands only target Habit Tracker data.

```sh
state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
rm -i -- "$state/habits.json" "$state/habits.json.bak" \
  "$state/habits.json.v1.bak" "$state/habits.json.v2.bak" "$state/habits.json.lock"
rm -ri -- "$state/habits-exports"
```

Files or directories that were never created can be absent. Keep any export or backup you want to retain before confirming removal.
