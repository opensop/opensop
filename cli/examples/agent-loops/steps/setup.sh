#!/usr/bin/env bash
# setup.sh: the first step of both agent loops. Checks the inputs and records the
# base commit every later diff is taken against. Prints {task, base}.
set -euo pipefail
ctx=$(cat)
input() { jq -r --arg k "$1" '.[$k] // ""' <<<"$ctx"; }
fail() { jq -cn --arg e "$1" '{error: $e}'; exit 1; }
wd=$(input workdir); req=$(input request); req_file=$(input request_file)
[[ -n $wd ]] || fail "set --input workdir=<path to a git checkout the agents may change>"
git -C "$wd" rev-parse --git-dir >/dev/null 2>&1 || fail "workdir is not a git checkout: $wd"
[[ -n $(input test_command) ]] || fail "set --input test_command='<the command that runs your tests>'"
if [[ -n $req_file ]]; then
  [[ -f $req_file ]] || fail "request_file not found: $req_file"
  req=$(cat "$req_file")
fi
[[ -n $req ]] || fail "set --input request='<what to build>' or --input request_file=<path>"
jq -cn --arg t "$req" --arg b "$(git -C "$wd" rev-parse HEAD)" '{task: $t, base: $b}'
