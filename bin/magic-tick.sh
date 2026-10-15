#!/bin/zsh
# One magic mode pass: pick at most ONE of your PRs that has merge conflicts or failing CI and fix it.
# Dry run: PRBAR_MAGIC_DRY_RUN=1 prints the pick without running anything.
source "${0:A:h}/lib.sh"
M="$PRBAR_STATE/magic"; mkdir -p "$M/attempts"
LOG="$PRBAR_STATE/logs/magic.log"
say() { print -r -- "$(date '+%F %T') $*" >> "$LOG"; [ -n "$PRBAR_MAGIC_DRY_RUN" ] && print -r -- "$*"; }
status() { print -r -- "$*" > "$M/status"; }
notify() { terminal-notifier -title "🪄 Magic mode" -message "$1" ${2:+-open "$2"} -group "pr-bar-magic" >/dev/null 2>&1 }

# Only runs while explicitly enabled, and never past the expiry
[ -f "$M/enabled" ] || exit 0
if [ "$(cat "$M/enabled")" -le "$(date +%s)" ]; then
  say "expired"; notify "Magic mode expired and turned itself off"; "${0:A:h}/magic.sh" off; exit 0
fi
[ -n "$PRBAR_FIX_REPO" ] || { say "PRBAR_FIX_REPO not set"; exit 1; }

# One at a time: atomic lock, with stale-pid recovery
lock="$M/lock"
if ! mkdir "$lock" 2>/dev/null; then
  kill -0 "$(cat "$lock/pid" 2>/dev/null)" 2>/dev/null && exit 0
  rm -rf "$lock"; mkdir "$lock" || exit 0
fi
echo $$ > "$lock/pid"; trap 'rm -rf "$lock"' EXIT HUP INT TERM

# Do not collide with a manual fix already running on any PR
[ -n "$(ls "$PRBAR_STATE/running" 2>/dev/null)" ] && { say "a fix is already running; waiting"; exit 0; }

Q='query { search(query: "is:pr is:open author:@me archived:false repo:'"$PRBAR_FIX_REPO"'", type: ISSUE, first: 50) { nodes { ... on PullRequest {
  number headRefName headRefOid isDraft mergeable
  commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } } } }'
data=$(gh api graphql -f query="$Q" 2>&1) || { say "gh failed: ${data:0:150}"; exit 1; }

pick=""
while IFS=$'\t' read -r n branch sha need; do
  [ -n "$n" ] || continue
  cf="$M/attempts/$n.count"; sf="$M/attempts/$n.nopush"
  if [ "$need" = none ]; then rm -f "$cf" "$sf" "$M/attempts/$n.told"; continue; fi   # healthy again: reset its budget
  count=$(cat "$cf" 2>/dev/null || echo 0)
  [ "$(cat "$sf" 2>/dev/null)" = "$sha" ] && continue            # we already tried this exact commit and chose not to push
  if [ "$count" -ge "$PRBAR_MAGIC_MAX_ATTEMPTS" ]; then          # out of attempts: it needs you (tell once)
    [ -f "$M/attempts/$n.told" ] || { : > "$M/attempts/$n.told"; notify "#$n still failing after $count attempts, needs you" "https://github.com/$PRBAR_FIX_REPO/pull/$n"; }
    continue
  fi
  [ -z "$pick" ] && pick="$n $branch $sha $need $count"
done < <(print -r -- "$data" | jq -r '.data.search.nodes[] | select(.number and (.isDraft|not)) |
  [.number, .headRefName, .headRefOid,
   (if .mergeable=="CONFLICTING" then "conflicts"
    elif (.commits.nodes[0].commit.statusCheckRollup.state // "") | IN("FAILURE","ERROR") then "ci"
    else "none" end)] | @tsv')

if [ -z "$pick" ]; then status "🪄 all clear $(date +%H:%M)"; say "nothing to do"; exit 0; fi
set -- ${=pick}; n=$1; branch=$2; sha=$3; need=$4; count=$5
say "picked #$n ($need), attempt $((count+1))/$PRBAR_MAGIC_MAX_ATTEMPTS, head ${sha:0:8}"
[ -n "$PRBAR_MAGIC_DRY_RUN" ] && exit 0

status "🪄 fixing #$n ($need), attempt $((count+1))/$PRBAR_MAGIC_MAX_ATTEMPTS"
"${0:A:h}/fix-pr.sh" "$need" "$PRBAR_FIX_REPO" "$n" "$branch" >> "$LOG" 2>&1
echo $((count+1)) > "$M/attempts/$n.count"

newsha=$(gh pr view "$n" --repo "$PRBAR_FIX_REPO" --json headRefOid --jq .headRefOid 2>/dev/null)
url="https://github.com/$PRBAR_FIX_REPO/pull/$n"
if [ "$newsha" = "$sha" ]; then
  echo "$sha" > "$M/attempts/$n.nopush"
  say "#$n: no push; giving up on this commit"; status "🪄 #$n needs you (not fixed)"
  notify "#$n: couldn't fix $need safely, needs you" "$url"
else
  say "#$n: pushed ${newsha:0:8}; waiting for CI"; status "🪄 #$n pushed, waiting for CI"
  [ $((count+1)) -ge "$PRBAR_MAGIC_MAX_ATTEMPTS" ] && notify "#$n: last attempt pushed; check it if CI fails again" "$url"
fi
