#!/bin/zsh
# merge-pr.sh <owner/repo> <pr-number> <mergeStateStatus> <title>   (squash, asks yes/no first)
source "${0:A:h}/lib.sh"
repo=$1; pr=$2; state=$3; title=$4
warn=""
[ "$state" = UNSTABLE ] && warn="\n\n⚠️ Some non-required checks are failing."
ans=$(osascript -e "button returned of (display dialog \"Merge $repo #$pr (squash)?\n\n$title$warn\" buttons {\"No\",\"Yes\"} default button \"No\" cancel button \"No\" with icon caution with title \"Merge PR\")" 2>/dev/null)
[ "$ans" = "Yes" ] || exit 0
if out=$(gh pr merge "$pr" --repo "$repo" --squash 2>&1); then
  terminal-notifier -title "Merged #$pr" -message "$title" -open "https://github.com/$repo/pull/$pr" >/dev/null 2>&1
else
  terminal-notifier -title "Merge failed #$pr" -message "${out:0:200}" -open "https://github.com/$repo/pull/$pr" >/dev/null 2>&1
fi
