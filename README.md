# pr-bar

A macOS menu bar dashboard for your open GitHub pull requests, where every red icon has a one-click AI fix.

It shows your PRs with live status, and lets Claude Code fix what's broken in a git worktree, streaming each step into a Terminal window so you can watch it work.

```
PR 3 ❌1
 🟢 💬2 #412 feat: add export          → 🚀 Merge · Open PR
 ❌     #409 fix: flaky retry          → 🔧 Fix CI (push) · Open PR
 ✅ ⚠️  #401 chore: bump deps          → 🔀 Resolve conflicts (push)
```

## What it shows

| Icon | Meaning |
|---|---|
| 🟢 | GitHub says it can merge right now (checks green, approvals in place, not a draft) |
| ✅ / ❌ / 🟡 / ⚪️ | CI passing / failing / pending / none |
| 💬N | N unresolved review threads (shown alongside any CI icon) |
| ⚠️ | Merge conflicts with the base branch |
| ⏳ | A fix run is in progress for this PR |

## Actions

- **🔧 Fix CI**: Claude reads the failed logs, fixes the cause, runs local checks and **pushes** if they pass. Flaky or unclear failures are not pushed.
- **🔀 Resolve conflicts**: merges the base branch in (merge, not rebase), resolves, verifies, and **pushes** if everything passes.
- **💬 Triage comments**: read-only. Writes a report (valid? what fix? how much effort?) to `~/.pr-bar/reports/`. It never edits code or pushes, because review comments are yours to handle.
- **🚀 Merge**: shown only when GitHub reports the PR as mergeable. Asks a **Yes / No** dialog (default No) before running `gh pr merge --squash`.

Fix actions run Claude headless (`claude -p`) with `acceptEdits` and a tool allowlist, inside a separate worktree, so your working checkout is untouched. Output streams live (reasoning, each tool call, result previews) and is saved under `~/.pr-bar/logs/`. Force-push and `--no-verify` are forbidden in every prompt.

## Requirements

[SwiftBar](https://github.com/swiftbar/SwiftBar) · [`gh`](https://cli.github.com) (authenticated) · `jq` · [`claude`](https://claude.com/claude-code) · `terminal-notifier`

```bash
brew install --cask swiftbar && brew install gh jq terminal-notifier
```

## 🪄 Magic mode

Opt-in autopilot. When on, pr-bar fixes your PRs' merge conflicts and failing CI **by itself**, one PR at a time, until they pass, and **pushes** the fixes. Turn it on from the menu (**🪄 Enable magic mode**, confirmed with a Yes / No dialog). It is never on by default.

- **One at a time:** a global lock means a single PR is being worked on at any moment, and it waits if you started a manual fix.
- **Until green:** it picks conflicts first, then failing CI. After a push it waits for CI, and if CI fails again it tries again. A PR that turns clean resets its budget.
- **Bounded:** at most 3 attempts per PR (`PRBAR_MAGIC_MAX_ATTEMPTS`). If Claude decides a fix isn't safe (flaky, ambiguous), it does not push, remembers that commit, and notifies you instead of retrying forever.
- **Never touches comments:** review feedback stays yours.
- **Skips drafts** and only works on the configured `PRBAR_FIX_REPO`.
- **Self-expiring:** turns itself off after 8 hours (`PRBAR_MAGIC_HOURS`) and doesn't survive being disabled. Turn it off any time from the menu.
- **Watchable:** the menu shows the current status (`🪄 fixing #123 (ci), attempt 1/3`), and **Watch magic log** tails what it is doing. Each run is saved in `~/.pr-bar/logs/`.

It runs as a per-user LaunchAgent (`com.pr-bar.magic`, checks every 2 min), created when you enable it and removed when you disable it, so it keeps working when the menu bar app is closed.

## Install

One line (needs [`gh`](https://cli.github.com) logged in; it installs SwiftBar, `jq` and `terminal-notifier` via Homebrew, wires everything up and starts SwiftBar):

```bash
gh api repos/jhta/pr-bar/contents/install.sh -H "Accept: application/vnd.github.raw" | zsh
```

Then edit `~/.pr-bar/config` (see below) and click **Refresh** in the menu bar.

**Update:** run the same line again. It pulls the latest version and keeps your config.

**Refresh rate:** the list refreshes **every 2 minutes**, and a manual **Refresh** item sits at the bottom of the menu. The interval comes from the plugin filename (`prs.2m.sh`); rename the symlink in `~/SwiftBar` to `prs.30s.sh`, `prs.5m.sh`, etc. to change it. Mind the GitHub API rate limit if you go very low.

<details><summary>Manual install</summary>

```bash
git clone https://github.com/jhta/pr-bar ~/.pr-bar/src && ~/.pr-bar/src/install.sh
```
</details>

## Configuration

Everything personal lives in `~/.pr-bar/config`, outside the repo (see [`config.example`](config.example)): which orgs to search, which repo gets fix actions and where its checkout lives, an optional worktree setup command, and extra rules for Claude. No tokens are stored: auth comes from your existing `gh` login.

## Notes and limits

- Fix actions work for one configured repo (they need a local checkout to branch worktrees from). Other repos still get status and Merge.
- The headless run can't ask you questions, so you watch rather than steer.
- Merge uses squash. Change it in `bin/merge-pr.sh` if your repo disallows that.
- Treat it like a teammate with push access: start with 💬 Triage, then Fix CI on a low-risk PR.

## License

MIT
