#!/usr/bin/env bash
# diffs.sh: writes the change as files a read-only agent can Read (a read-only
# Claude agent has Read/Grep/Glob only, so it cannot run `git diff` itself).
#   .agent-loop/full.diff   everything since the base commit, untracked files included
#   .agent-loop/delta.diff  everything since the previous cycle (fix rounds only)
# A throwaway git index keeps your own staging area untouched, and .agent-loop/ is
# added to the checkout's info/exclude so it never reaches a commit.
set -uo pipefail
ctx=$(cat)
wd=$(jq -r '.workdir' <<<"$ctx"); base=$(jq -r '.task.base' <<<"$ctx"); prev=$(jq -r '.diffs.tree // empty' <<<"$ctx")
cd "$wd" || { jq -cn '{error: "diffs: cannot enter workdir"}'; exit 1; }
exclude=$(git rev-parse --git-path info/exclude); mkdir -p "$(dirname "$exclude")" .agent-loop
grep -qx '.agent-loop/' "$exclude" 2>/dev/null || echo '.agent-loop/' >> "$exclude"
export GIT_INDEX_FILE; GIT_INDEX_FILE=$(mktemp); trap 'rm -f "$GIT_INDEX_FILE"' EXIT
git read-tree HEAD && git add -A && tree=$(git write-tree)
git diff "$base" "$tree" > .agent-loop/full.diff
if [[ -n $prev ]]; then git diff "$prev" "$tree" > .agent-loop/delta.diff; else : > .agent-loop/delta.diff; fi
jq -cn --arg t "$tree" --argjson f "$(wc -l < .agent-loop/full.diff)" --argjson d "$(wc -l < .agent-loop/delta.diff)" \
  '{tree: $t, full: ".agent-loop/full.diff", delta: ".agent-loop/delta.diff", full_lines: $f, delta_lines: $d}'
