# Agent loops

Two OpenSOP processes that run coding agents against a git checkout, using
local `claude`, `codex`, `cursor-agent` or `kimi` CLIs as the models. Every
agent call, gate result and decision is receipted under
`$OPENSOP_LOCAL_HOME/runs/<run_id>/`.

| Process | Shape |
|---|---|
| `planner-worker.sop.json` | A planner splits the request into units, workers build them in order, the test gate runs, and a fresh reviewer accepts or sends feedback to the next planner. Up to `max_cycles` (4). |
| `dev-loop.sop.json` | Plan, then a fresh critique, then a revised plan with units. Workers build the units, the test gate runs, an adversarial reviewer reviews the change (first cycle only), and a fresh rater labels findings BLOCKING / MAJOR / MINOR. While a BLOCKING or MAJOR finding stands, a fix round turns them into new units. The next rating judges only the fix (a delta). Up to `max_cycles` (3). |

## Requirements

- opensop CLI 0.9.2 or later (CLI providers, local `loop`, `condition`)
- `bash`, `jq`, `git`
- The CLI for every model you use, installed and signed in. The defaults use
  only `claude` (Claude Code).

## Run it

Agents change files in `workdir`, so point it at a scratch checkout or worktree
with a clean tree, never at work you care about:

```bash
git -C ~/code/myapp worktree add /tmp/myapp-loop
opensop run cli/examples/agent-loops/planner-worker.sop.json \
  --input workdir=/tmp/myapp-loop \
  --input request="Add a --verbose flag to the export command, with tests" \
  --input test_command="npm test"
```

The request can also come from a file: `--input request_file=/abs/path/task.md`.

Then follow it with `opensop status <run_id>`. When it ends, read the change in the
worktree. The loop never commits or pushes.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `workdir` | (required) | Git checkout the agents work in |
| `request` / `request_file` | (one required) | What to build |
| `test_command` | (required) | The mechanical gate, e.g. `npm test`, `bundle exec rspec`, `pytest -q`. It runs in `workdir` every cycle; a failure is evidence for the reviewer, not a crash |
| `planner`, `critic`, `worker`, `reviewer`, `rater`, `fixer` | `claude-code:claude-opus-5-5` (worker: `claude-sonnet-5-5`) | `<cli>:<model>`, where `<cli>` is `claude-code`, `codex`, `cursor` or `kimi`. An empty model (`codex:`) means that CLI's default |
| `worker_permission` | `workspace-write` | `read-only`, `workspace-write` or `full-access`. All other roles are read-only |
| `max_cycles` | 3 / 4 | Cycles before the run fails as not converged |

Mixing vendors is the point of the fresh reviewer and rater. A reviewer from a
different model family catches more than one sharing the worker's blind spots:

```bash
--input reviewer=codex:gpt-6.1-sol --input worker=cursor:
```

`kimi -p` has no sandbox, so OpenSOP only runs kimi with `full-access`. To use it
as a worker, also set `--input worker_permission=full-access`.

## How it works

- `steps/setup.sh` checks the inputs and records the base commit.
- `steps/gate.sh` runs `test_command` and prints `{passed, log}`.
- `steps/diffs.sh` writes `.agent-loop/full.diff` (everything since the base) and
  `.agent-loop/delta.diff` (since the last cycle). Read-only agents can read these
  files but cannot run `git diff`. It uses a throwaway git index, so your
  staging area is untouched, and `.agent-loop/` goes in the checkout's
  `info/exclude`.
- `steps/rate-brief.sh` builds the rater's prompt: a full rating on the first
  cycle, a delta judgment of the previous rating plus the fix diff after that.
  A MAJOR can be waived only on three named grounds.
- Prompts are in `prompts/`. They are plain Markdown with `{{ ref }}` templating.
  Edit them to match your team's rules.

If a provider hits a usage limit, the step fails with an error starting
`provider_limit:`, and the provider's own message is in the receipt.
