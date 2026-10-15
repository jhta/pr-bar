# Shared config loader. Sourced by every script.
export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH
PRBAR_STATE="${PRBAR_STATE:-$HOME/.pr-bar}"
# Optional user config (never committed). See config.example.
[ -f "$PRBAR_STATE/config" ] && source "$PRBAR_STATE/config"
: "${PRBAR_SEARCH_EXTRA:=}"      # extra GitHub search qualifiers, e.g. "org:acme"
: "${PRBAR_FIX_REPO:=}"          # owner/repo that fix actions are enabled for
: "${PRBAR_REPO_CHECKOUT:=}"     # local path of that repo's main checkout
: "${PRBAR_SETUP_CMD:=}"         # run in a fresh worktree when node_modules is missing
: "${PRBAR_EXTRA_RULES:=}"       # extra rules appended to every Claude prompt
: "${PRBAR_COMMIT_HINT:=a conventional commit message}"
mkdir -p "$PRBAR_STATE"/{logs,reports,running}
