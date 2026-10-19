#!/usr/bin/env bash
# gate.sh: the mechanical gate. Runs process.inputs.test_command in the workdir and
# prints {passed, log} (the last 6 KB of output). It always exits 0, so a red gate
# reaches the reviewer and rater as evidence instead of stopping the run.
set -uo pipefail
ctx=$(cat)
wd=$(jq -r '.workdir' <<<"$ctx"); cmd=$(jq -r '.test_command' <<<"$ctx")
log=$(mktemp); trap 'rm -f "$log"' EXIT
ok=true
(cd "$wd" && bash -c "$cmd") >"$log" 2>&1 || ok=false
jq -cn --argjson p "$ok" --arg l "$(tail -c 6000 "$log")" '{passed: $p, log: $l}'
