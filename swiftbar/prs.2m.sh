#!/bin/zsh
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
ROOT=${0:A:h:h}; source "$ROOT/bin/lib.sh"
FIX="$ROOT/bin/fix-pr.sh"; MERGE="$ROOT/bin/merge-pr.sh"; STATE="$PRBAR_STATE"
FIX_REPO="$PRBAR_FIX_REPO"

Q='query { search(query: "is:pr is:open author:@me archived:false '"$PRBAR_SEARCH_EXTRA"'", type: ISSUE, first: 50) { nodes { ... on PullRequest {
  number title url isDraft headRefName mergeable mergeStateStatus reviewDecision repository { nameWithOwner }
  reviewThreads(first: 100) { nodes { isResolved } }
  commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 100) { totalCount nodes { ... on CheckRun { name conclusion status } ... on StatusContext { context state } } } } } } } } } } }'

data=$(gh api graphql -f query="$Q" 2>&1) || { echo "PR ⚠️"; echo "---"; echo "gh failed: ${data:0:120}"; exit 0; }

magic=""
if [ -f "$STATE/magic/enabled" ] && [ "$(cat "$STATE/magic/enabled")" -gt "$(date +%s)" ]; then
  magic="until $(date -r "$(cat "$STATE/magic/enabled")" +%H:%M)"
fi
magic_status=$(cat "$STATE/magic/status" 2>/dev/null)
CI_JQ=$(<"$ROOT/bin/ci-state.jq")
running=$(ls "$STATE/running" 2>/dev/null | jq -R . | jq -sc .)

echo "$data" | jq -r --arg fix "$FIX" --arg merge "$MERGE" --arg fixrepo "$FIX_REPO" --arg st "$STATE" --arg magic "$magic" --arg mstatus "$magic_status" --arg magicsh "$ROOT/bin/magic.sh" --argjson running "$running" --arg ignore "$PRBAR_IGNORE_CHECKS" "$CI_JQ"'
  [.data.search.nodes[] | select(.number)] as $prs
  | ($prs | map(select(ci_state($ignore) | IN("FAILURE","ERROR"))) | length) as $failing
  | "\(if $magic != "" then "🪄 " else "" end)PR \($prs|length)\(if $failing>0 then " ❌\($failing)" else "" end)",
  ( ($prs | group_by(.repository.nameWithOwner) | sort_by(if .[0].repository.nameWithOwner == $fixrepo then 0 else 1 end))[] as $g
    | "---",
      "\($g[0].repository.nameWithOwner) · \($g|length)\(($g | map(select(ci_state($ignore) | IN("FAILURE","ERROR"))) | length) as $f | if $f>0 then "  ❌\($f)" else "" end) | size=12 color=#8e8e93 href=https://github.com/\($g[0].repository.nameWithOwner)/pulls",
    ( $g[] |
    ci_state($ignore) as $ci
    | ([.reviewThreads.nodes[] | select(.isResolved|not)] | length) as $unres
    | (.mergeable == "CONFLICTING") as $conf
    | (.number|tostring) as $n
    | ($running | index($n) != null) as $busy
    | (if ((.mergeStateStatus|IN("CLEAN","HAS_HOOKS")) or (.mergeStateStatus=="UNSTABLE" and $ci=="SUCCESS")) and (.isDraft|not) then "🟢" elif $ci=="SUCCESS" then "✅" elif ($ci|IN("FAILURE","ERROR")) then "❌" elif ($ci|IN("PENDING","EXPECTED")) then "🟡" else "⚪️" end) as $ciIcon
    | "\(if $busy then "⏳" else $ciIcon end)\(if $unres>0 then " 💬\($unres)" else "" end)\(if $conf then " ⚠️" else "" end) #\(.number) \(.title|gsub("\\|";"/"))\(if .isDraft then " [draft]" else "" end) | href=\(.url) length=70",
    (if (.mergeStateStatus|IN("CLEAN","HAS_HOOKS","UNSTABLE")) and (.mergeable=="MERGEABLE") and (.isDraft|not) then "--🚀 Merge | bash=\($merge) param1=\(.repository.nameWithOwner) param2=\($n) param3=\(.mergeStateStatus) param4=\"\(.title|gsub("[\"|]";""))\" terminal=false refresh=true" elif (.isDraft|not) then "--🚫 Merge unavailable (\(.mergeStateStatus|ascii_downcase)) | disabled=true" else empty end),
    (if .repository.nameWithOwner == $fixrepo then
       (if $busy then "--working… | disabled=true" else
         (if ($ci|IN("FAILURE","ERROR")) then "--🔧 Fix CI (push) | bash=\($fix) param1=ci param2=\(.repository.nameWithOwner) param3=\($n) param4=\(.headRefName) terminal=true refresh=true" else empty end),
         (if $conf then "--🔀 Resolve conflicts (push) | bash=\($fix) param1=conflicts param2=\(.repository.nameWithOwner) param3=\($n) param4=\(.headRefName) terminal=true refresh=true" else empty end),
         (if $unres>0 then "--💬 Triage comments (no push) | bash=\($fix) param1=comments param2=\(.repository.nameWithOwner) param3=\($n) param4=\(.headRefName) terminal=true refresh=true" else empty end)
       end),
       "--Open PR | href=\(.url)",
       "--Latest log | bash=/usr/bin/open param1=\($st)/logs terminal=false"
     else "--Open PR | href=\(.url)" end)
  )),
  "---",
  (if $magic != "" then
     "🪄 Magic mode ON \($magic): turn off | bash=\($magicsh) param1=off terminal=false refresh=true",
     (if $mstatus != "" then "--\($mstatus) | disabled=true" else empty end),
     "--Watch magic log | bash=/usr/bin/tail param1=-f param2=\($st)/logs/magic.log terminal=true"
   else
     "🪄 Enable magic mode (auto-fix conflicts and CI, pushes!) | bash=\($magicsh) param1=on terminal=false refresh=true"
   end),
  "Refresh | refresh=true", "Logs | bash=/usr/bin/open param1=\($st)/logs terminal=false"
'
