<p align="center">
  <img src="docs/images/hero.png" alt="A person and a small robot walking together down a stone path toward the mountains and the rising sun." width="100%" />
</p>

# OpenSOP

[![CLI tests](https://github.com/opensop/opensop/actions/workflows/cli-tests.yml/badge.svg)](https://github.com/opensop/opensop/actions/workflows/cli-tests.yml)

> ### OpenSOP turns your best agent workflow into a file anyone can run.

Every process sits somewhere between a script and a judgment call. Some steps must always come out the same: run the tests, check the diff, merge only on green. Others need a model's judgment: plan the work, review the change, decide what a failure means.

OpenSOP lets you set that dial step by step, in one simple file. **Scripts where it must be certain, LLMs where it needs thinking.** When a judgment call keeps going wrong, turn it into a script. When a rigid step needs nuance, hand it to a model.

Agents don't have to remember anything. The file holds the process and the run folder holds the state, so any agent from any vendor, or a person, can pick up any step. Every step leaves a receipt.

A Dockerfile is just a file. A GitHub Actions workflow is just YAML. They mattered because they made something that lived in one person's head runnable, checkable and shareable. OpenSOP does that for agent work.

Read [MANIFESTO.md](./MANIFESTO.md) for the thesis and [SPEC.md](./SPEC.md) (spec v0.9.1) for the format.

---

## Quickstart (60 seconds)

You need `bash` 4+ and `jq`. No server, no account.

```bash
# 1. Install: one bash file, checksum-verified, lands in ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/opensop/opensop/main/cli/install.sh | bash

# 2. Write a process: one scripted step, one judgment call
cat > ship.sop.json <<'EOF'
{
  "name": "ship",
  "version": "1.0",
  "inputs": { "change": "fix typo" },
  "steps": [
    { "id": "check", "type": "shell",
      "description": "A script: comes out the same every time.",
      "run": "echo '{\"tests\": \"passed\"}'" },
    { "id": "approve", "type": "approval",
      "description": "A judgment call: ship it?" }
  ]
}
EOF

# 3. Run it. The script runs, then the run waits for a decision.
id=$(opensop run ship.sop.json --json | jq -r .run_id)
opensop status "$id"                 # waiting on approve, and the exact command to continue

# 4. Decide, then read the receipts
opensop submit "$id" approve --output decision=approve
opensop show "$id"
```

Everything about that run lives in its run folder (`opensop status "$id" --json | jq -r .run_dir`): `manifest.json`, an append-only `audit.jsonl`, and `context.json`. Any agent or person can read it and pick up where it stopped.

### Hand a step to a model

Swap the approval for a model review, and keep a person only where it matters:

```json
{ "id": "review", "type": "llm",
  "model": "claude-code:",
  "permission": "read-only",
  "prompt": "Review this change: {{ change }}. Reply as JSON.",
  "expected_output_schema": { "verdict": "enum[ship,rework]", "reason": "string" } },
{ "id": "approve", "type": "approval",
  "condition": "steps.review.outputs.verdict == 'ship'" }
```

`model` picks the vendor. `claude-code:`, `codex:`, `cursor:` and `kimi:` drive those CLIs non-interactively (empty after the colon means the CLI's default model), and a bare `claude-*` model calls the Anthropic API. The answer must match `expected_output_schema`, or the step retries and then fails; it is never passed on unchecked. Each call's receipt records the provider, model, permission, token usage and, where the vendor reports it, cost.

To try `llm` and `judgment` steps with no API key or model CLI, set `OSL_LLM_STUB` to the JSON every such step should answer, on each command that reaches one (`run`, `submit`, `heal`):

```bash
export OSL_LLM_STUB='{"verdict": "ship", "reason": "looks good"}'
```

---

## The software factory

The flagship use: plan, build, review, test gate, accept, land, run across several coding agents and vendors.

- **Scripts decide done.** The test gate is a command, not an opinion.
- **The reviewer is never the author.** A fresh agent, often from another vendor, reviews each change.
- **Fixes go into the process.** When something breaks, you change the file, not an agent's memory, and every later run gets the fix.

[`cli/examples/agent-loops/`](./cli/examples/agent-loops/) is the open, runnable version: `planner-worker` and `dev-loop`, driving local `claude`, `codex`, `cursor-agent` or `kimi` CLIs against a git checkout.

```bash
git clone https://github.com/opensop/opensop.git && cd opensop
opensop run cli/examples/agent-loops/planner-worker.sop.json \
  --input workdir=/path/to/scratch-worktree \
  --input request="Add a --verbose flag to the export command, with tests" \
  --input test_command="npm test"
```

---

## Agents

OpenSOP is built to be driven by agents. Every command speaks `--json`, `opensop status` says what a run is waiting for and how to continue, and `opensop help agents` is a quick-start written for them.

```bash
opensop skill install --runtime claude          # or codex, hermes, openclaw, openhands, goose
opensop skill install --runtime claude --skill opensop-build-harness   # the process-authoring skill
opensop skill paths                             # where each runtime looks
opensop doctor                                  # version, deps, installed skills
```

**Hermes Agent plugin (coming):** [opensop/hermes-opensop](https://github.com/opensop/hermes-opensop) gives Hermes tools to start, inspect, submit and retry runs. It re-anchors the agent on its current step every turn, nudges it to finish that step before it wraps up a turn in which it edited code, and refuses to submit a step reserved for a person. It is a seat belt, not a sandbox.

The full agent guide is [`docs/AGENTS.md`](./docs/AGENTS.md).

---

## The step types

| Step | What it does | Local CLI |
|---|---|---|
| `automated` | Run a script file (any language). A relative `run:` path is found next to the process file | Runs |
| `shell` | Run a command line in the directory you started the run from (`npm test`, `pytest -q`) | Runs |
| `noop` | Pass context through | Runs |
| `llm` | A model call validated against `expected_output_schema` | Anthropic API (`claude-*`, needs `ANTHROPIC_API_KEY`) or a CLI provider (`claude-code:`, `codex:`, `cursor:`, `kimi:`) |
| `judgment` | A model decides with a confidence score; low confidence or `require_human_review` escalates to a person | Runs; an escalation pauses for `submit` |
| `loop` | Repeat a body of steps: `for_each`, `repeat_until` or `while` | Runs (body steps can't pause) |
| `form` | Collect data from a person or agent | Pauses for `submit` |
| `approval` | A person approves or rejects | Pauses for `submit` |
| `wait` | Pause on a timer or a condition | `seconds` runs; `until` pauses |
| `webhook` | Outbound HTTP, sync or callback | Sync runs; callback pauses |
| `subprocess` | Start another process | Runs (depth-guarded) |
| `notification` | Send a message | Not in the local CLI yet |

Any step can carry a `condition`, and a run can end early with `exit_when`. Full grammar: [`SPEC.md`](./SPEC.md).

---

## The CLI

`cli/bin/opensop` is a single bash file. The file *is* the binary: read it before you run it.

```bash
opensop run ./ship.sop.json --input change="bump deps"   # start a run
opensop status <run_id>                 # state, what it waits on, what to run next
opensop submit <run_id> <step> --output k=v              # answer a paused step
opensop show <run_id>                   # the receipts
opensop runs                            # every local run
opensop heal <run_id>                   # a failed step, as a fix prompt for an agent
opensop dry-run ./ship.sop.json         # validate inputs and preview the steps
opensop pull opensop/release-checklist  # fetch an example from sops/ (never runs it)
opensop upgrade                         # verified, atomic self-update
```

Full command reference: [`cli/README.md`](./cli/README.md). From a clone, `opensop bench` reproduces the reliability comparison in [`cli/bench/`](./cli/bench/).

---

## The optional server

The CLI runs everything locally and never needs a server. For a shared audit log or team visibility, point it at any server that implements the [`SPEC.md`](./SPEC.md) `/sop/*` contract with `--server <url>` (or `opensop config set url …` plus `--remote`). There is no maintained reference server; the profile is specified so anyone can build one.

---

## Documentation

| Doc | Covers |
|---|---|
| [`MANIFESTO.md`](./MANIFESTO.md) | The thesis: why processes are infrastructure |
| [`SPEC.md`](./SPEC.md) | The OpenSOP v0.9.1 format and the `/sop/*` API contract |
| [`docs/AGENTS.md`](./docs/AGENTS.md) | Agents: discover, run, build, and turn a prompt into a process |
| [`cli/README.md`](./cli/README.md) | Every CLI command, install verification, threat model |
| [`sops/`](./sops/) | Example processes you can `pull` |
| [`CONTRIBUTING.md`](./CONTRIBUTING.md) | How to send a change |

## License

Apache 2.0. See [`LICENSE`](./LICENSE). The CLI is MIT ([`cli/LICENSE`](./cli/LICENSE)).
