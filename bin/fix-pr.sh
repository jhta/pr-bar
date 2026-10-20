#!/bin/zsh
# fix-pr.sh <ci|conflicts|comments> <owner/repo> <pr-number> <branch>
# Runs Claude Code headless in a git worktree of the PR branch and streams its steps live.
source "${0:A:h}/lib.sh"
mode=$1; repo=$2; pr=$3; branch=$4
[ -n "$PRBAR_REPO_CHECKOUT" ] || { echo "Set PRBAR_REPO_CHECKOUT in $PRBAR_STATE/config"; exit 1; }
MAIN="$PRBAR_REPO_CHECKOUT"
lock="$PRBAR_STATE/running/$pr"
log="$PRBAR_STATE/logs/pr-$pr-$mode.log"
raw="$PRBAR_STATE/logs/pr-$pr-$mode.jsonl"
report="$PRBAR_STATE/reports/pr-$pr-comments.md"

[ -e "$lock" ] && exit 0
echo "$mode" > "$lock"
trap 'rm -f "$lock"' EXIT HUP INT TERM

notify() { terminal-notifier -title "PR #$pr ($mode)" -message "$1" ${2:+-open "$2"} -group "pr-bar-$pr" >/dev/null 2>&1 }

# Work only in a separate git worktree, never in the main checkout.
wt=$(git -C "$MAIN" worktree list --porcelain | awk -v b="refs/heads/$branch" '/^worktree /{p=$2} $1=="branch" && $2==b {print p}')
if [ -z "$wt" ]; then
  wt="$MAIN-pr$pr"
  git -C "$MAIN" fetch origin "$branch" >>"$log" 2>&1
  if git -C "$MAIN" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$MAIN" worktree add "$wt" "$branch" >>"$log" 2>&1 && git -C "$wt" merge --ff-only "origin/$branch" >>"$log" 2>&1
  else
    git -C "$MAIN" worktree add --track -b "$branch" "$wt" "origin/$branch" >>"$log" 2>&1
  fi || { notify "Could not create worktree (see log)" "$log"; exit 1; }
fi
cd "$wt" || exit 1
if [ "$(git rev-parse --show-toplevel)" = "${MAIN:A}" ]; then
  echo "✖ $branch is checked out in your main checkout; switch it to another branch first so fixes stay out of it."
  notify "Refused: $branch is checked out in the main checkout" ; exit 1
fi
if [ "$mode" != comments ] && [ -n "$(git status --porcelain)" ]; then
  echo "✖ $wt has uncommitted changes (yours?); commit or stash them first."
  notify "Refused: $wt has uncommitted changes" ; exit 1
fi
echo "▶ $mode · PR #$pr · $branch\n  worktree: $wt\n"
if [ -n "$PRBAR_SETUP_CMD" ] && [ ! -d node_modules ]; then
  echo "→ $PRBAR_SETUP_CMD"; eval "$PRBAR_SETUP_CMD" 2>&1 | tee -a "$log"
fi

common="Work only in this worktree (PR #$pr, branch $branch, repo $repo). Never force-push and never use --no-verify. $PRBAR_EXTRA_RULES Finish with a 2-3 sentence summary of what you did and whether you pushed."

case $mode in
  ci) prompt="CI is failing on PR #$pr. Use 'gh pr checks $pr' and 'gh run view --log-failed' to find the failing checks and their root cause. Ignore failures of these non-blocking checks: ${PRBAR_IGNORE_CHECKS:-none}. Fix it with the smallest change, then run the relevant local checks (tests, typecheck, lint). If local checks pass, commit with $PRBAR_COMMIT_HINT and run 'git push origin HEAD'. If the failure is flaky/infra or you cannot fix it confidently, do NOT push; explain why. $common" ;;
  conflicts) prompt="PR #$pr conflicts with its base branch. Run 'git fetch origin' and merge the base branch into this branch (merge, not rebase). Resolve the conflicts preserving the intent of both sides, run typecheck and the affected tests, then commit the merge and 'git push origin HEAD'. If a resolution is ambiguous or checks fail because of your merge, do NOT push; explain. $common" ;;
  comments) prompt="Triage the unresolved review comments on PR #$pr (use 'gh api graphql' on reviewThreads, or 'gh pr view $pr --comments'). For each: say if it is valid, what the fix would be, and effort. Write the result as markdown to $report. Do NOT modify any code, do NOT commit, do NOT push; the author handles comments personally. $common" ;;
  *) exit 2 ;;
esac

# The rtk hook (if installed) rewrites git/grep/ls/tsc to "rtk …", so both forms are allowed.
# rtk run / proxy / err (arbitrary commands) are deliberately not.
read_tools=(Read Grep Glob "Bash(gh:*)" "Bash(rtk gh:*)" "Bash(rtk git log:*)" "Bash(rtk git diff:*)" "Bash(git log:*)" "Bash(git diff:*)"
  "Bash(rtk grep:*)" "Bash(rtk ls:*)" "Bash(rtk find:*)" "Bash(rtk read:*)" "Bash(grep:*)" "Bash(ls:*)" "Bash(pwd)" "Bash(head:*)" "Bash(tail:*)" "Bash(wc:*)" "Bash(cat:*)")
case $mode in
  comments) tools=($read_tools Write) ;;
  *)        tools=($read_tools Edit Write "Bash(git:*)" "Bash(rtk git:*)" "Bash(yarn:*)" "Bash(npm:*)" "Bash(rtk npm:*)" "Bash(npx:*)" "Bash(rtk npx:*)"
              "Bash(rtk tsc:*)" "Bash(rtk lint:*)" "Bash(rtk jest:*)" "Bash(rtk diff:*)" "Bash(rtk wc:*)" "Bash(rtk prettier:*)" "Bash(echo:*)") ;;
esac
denied=("Bash(*--force*)" "Bash(*--no-verify*)" "Bash(* -f *)")

filter='if .type=="assistant" then (.message.content[]? | if .type=="text" then "\n💭 "+.text elif .type=="tool_use" then "🔧 "+.name+" "+((.input.command // .input.file_path // .input.pattern // .input.description // "")|tostring|.[0:200]) else empty end)
  elif .type=="user" then (.message.content[]? | select(.type=="tool_result") | "   ↳ "+((.content // "")|if type=="array" then map(.text // "")|join(" ") else tostring end|gsub("\n";" ")|.[0:160]))
  else empty end'
echo "→ claude is working (live)…\n"
claude -p "$prompt" --verbose --output-format stream-json --permission-mode acceptEdits --allowedTools "${tools[@]}" --disallowedTools "${denied[@]}" 2>>"$log" | tee "$raw" | jq -rR --unbuffered "fromjson? | $filter"
rc=${pipestatus[1]}
out=$(jq -r 'select(.type=="result").result // empty' "$raw")
print -r -- "$out" >> "$log"
echo "\n━━━ result ━━━\n$out\n"

if [ $rc -ne 0 ]; then notify "Claude failed (exit $rc). See log." "$log"; exit $rc; fi
summary=$(print -r -- "$out" | tail -n 4 | tr '\n' ' ' | cut -c1-220)
if [ "$mode" = comments ]; then notify "Triage ready: $summary" "$report"; else notify "$summary" "https://github.com/$repo/pull/$pr"; fi

rm -f "$lock"   # release the ⏳ marker before waiting on the keypress
if [ -t 1 ]; then read -k1 "?Press any key to close…"; fi
