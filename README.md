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

## Install

```bash
git clone https://github.com/jhta/pr-bar && cd pr-bar
./install.sh              # symlinks the plugin into ~/SwiftBar, creates ~/.pr-bar/config
$EDITOR ~/.pr-bar/config  # point it at your org and repo checkout
```

Then open SwiftBar and set its plugin folder to `~/SwiftBar`. The list refreshes every 2 minutes (rename `prs.2m.sh` to change that).

## Configuration

Everything personal lives in `~/.pr-bar/config`, outside the repo (see [`config.example`](config.example)): which orgs to search, which repo gets fix actions and where its checkout lives, an optional worktree setup command, and extra rules for Claude. No tokens are stored: auth comes from your existing `gh` login.

## Notes and limits

- Fix actions work for one configured repo (they need a local checkout to branch worktrees from). Other repos still get status and Merge.
- The headless run can't ask you questions, so you watch rather than steer.
- Merge uses squash. Change it in `bin/merge-pr.sh` if your repo disallows that.
- Treat it like a teammate with push access: start with 💬 Triage, then Fix CI on a low-risk PR.

## License

MIT
