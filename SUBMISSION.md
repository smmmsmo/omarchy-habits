# Marketplace handoff

Submit Habit Tracker as a **community plugin**, not as a change to Omarchy core. Read the Marketplace's [publishing guide](https://omarchyplugins.com/publish.html), [submission instructions](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md), and [security baseline](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SECURITY.md#automated-security-baseline) before posting. The [Quattro plugin reference](https://github.com/omacom/omarchy/blob/quattro/shell/plugins/README.md) governs runtime integration.

## Before submitting

1. Run `./test/all` and follow the [Quattro smoke checklist](docs/development.md). Review the preview and confirm the rights to the code and preview assets.
2. Review what would become public: commit author and committer metadata, every branch and tag, old screenshots, and all repository contents and history. Set a GitHub no-reply email for future commits if desired; setting it now does not change old commits. If earlier history should remain private, keep the original repository private and publish a reviewed source snapshot to a separate public repository. Update the README install URL, security link, and issue draft if the public repository URL changes.
3. Only submit once the GitHub repository root is public and its default branch contains the exact version you want reviewed. It must have one root `manifest.json`, a root README with installation/removal/dependencies, and a root license. The optional root preview here is `preview.png`; the current limit is 50 MB and 40 megapixels, and the Marketplace optimizes it.
4. Recheck [the Marketplace catalog](https://omarchyplugins.com/#catalog) and [registry](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/registry.json) for the repository URL, `mo.habits`, and retired IDs. The ID is permanent and outside `omarchy.*`; keep it stable for existing installs.
5. Open the [plugin submission form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml), or use the draft body and the current CLI submission instructions. Review and explicitly approve every checklist item before any agent files it on your behalf.

The closest current alternatives found were [HabitGrid](https://github.com/Blizl/Omarchy-HabitGrid) (numeric goals, Markdown and a contribution grid) and [LifeOS](https://github.com/staruxian/lifeos) (a broader daily planner with habits). [Goal Tracker](https://github.com/adriansalvadorekomo/omarchy-goal-tracker) and [TickTick](https://github.com/SotoAugusto/omarchy-ticktick) overlap as well. This listing is for the focused, offline Build/Quit workflow with explicit outcomes, historical corrections, and recovery after setbacks, not for first-party inclusion.

## Review lifecycle

The bot validates the public default-branch commit and runs its static security baseline without executing the plugin. A maintainer must apply `approved-and-verified` to the eligible exact snapshot. A local check is not a listing, security audit, or maintainer approval. If validation fails, fix the source and edit the same submission rather than opening a duplicate. After listing, use the [verification/update form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=verify-plugin.yml) to request promotion of a new commit; a normal Git push does not carry verification forward.

## Issue draft

**Title:** `[Plugin]: Habit Tracker`

Copy only the body inside the block. It is a draft: check the boxes only once each statement is true. An agent may post it only after the plugin owner confirms all five statements and explicitly approves this exact title and body.

```markdown
### Repository URL

https://github.com/smmmsmo/omarchy-habits

### Category

Productivity

### Tags

bar, quickshell

### Suggest a missing tag

_No response_

### Maintainer notes

Habit Tracker is an optional Quattro bar widget for building and quitting habits. The focused check-in shows current and best streaks, and Analysis provides week, month and year views, editable history and per-habit recovery. It also supports numeric targets, optional end dates, archive/restore and local CSV or JSON export. It makes no network requests, uses Python's standard library, and needs no separate setup. The preview uses fictional data.

### Submission checklist

- [ ] The repository is public and contains installation and removal instructions.
- [ ] I have documented the plugin license and any external dependencies.
- [ ] I confirm that I own or have permission to submit this plugin and its preview assets.
- [ ] The plugin does not overwrite user configuration without explicit consent.
- [ ] I understand that approval is for listing and is not a security review.
```
