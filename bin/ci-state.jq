# ci_state($ignore): a PR's CI state, not counting failures of non-blocking checks.
# $ignore = comma-separated check names (case-insensitive), e.g. "Mutation testing gate".
def ci_state($ignore):
  (.commits.nodes[0].commit.statusCheckRollup // null) as $r
  | if $r == null then "NONE"
    elif $ignore == "" or (($r.state | IN("FAILURE","ERROR")) | not) then $r.state
    # shortcut: only the first 100 checks are fetched; if there are more, keep GitHub's verdict. Upgrade when a repo has >100 checks.
    elif $r.contexts.totalCount > ($r.contexts.nodes | length) then $r.state
    else
      ($ignore | split(",") | map(gsub("^\\s+|\\s+$"; "") | ascii_downcase)) as $skip
      | [$r.contexts.nodes[]
         | {n: ((.name // .context) | ascii_downcase), c: (.conclusion // .state), s: (.status // "")}
         | select((.n | IN($skip[])) | not)] as $rest
      | if any($rest[]; .c | IN("FAILURE","ERROR","TIMED_OUT","CANCELLED","STARTUP_FAILURE","ACTION_REQUIRED")) then "FAILURE"
        elif any($rest[]; (.s != "" and .s != "COMPLETED") or .c == "PENDING") then "PENDING"
        else "SUCCESS" end
    end;
