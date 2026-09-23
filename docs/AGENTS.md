# OpenSOP — How It Works for Agents

Agents are good at *doing* steps and bad at *remembering which steps*. Left alone, an agent re-invents the procedure every time — slowly, inconsistently, unauditably. OpenSOP gives you a process as infrastructure: declare it once, run it the same way every time, keep the receipts.

This guide covers the full loop: **Discover → Run → Build → openSOP-ize → Iterate & Evolve**.

Companion references: [`SPEC.md`](../SPEC.md) (format grammar + HTTP API §4.2), [`cli/README.md`](../cli/README.md) (full command reference).

---

## Contents

1. [Install](#1-install)
2. [Discover](#2-discover)
3. [Run](#3-run)
4. [Receipts and structured output](#4-receipts-and-structured-output)
5. [Build a process](#5-build-a-process)
6. [openSOP-ize — the key agent skill](#6-opensop-ize--the-key-agent-skill)
7. [Iterate and evolve](#7-iterate-and-evolve)
8. [Self-check rubric](#8-self-check-rubric)
9. [Common mistakes](#9-common-mistakes)
10. [CLAUDE.md snippets](#10-claudemd-snippets)
11. [Adopt OpenSOP in your agent — AGENTS.md block](#11-adopt-opensop-in-your-agent--agentsmd-block)
12. [Runtime → skill path table](#12-runtime--skill-path-table)

---

## 1. Install

The CLI is a single bash file. No build step, no daemon, no package manager.

### Prerequisites

| Dependency | Required for |
|---|---|
| `bash` 4+ | Everything (macOS ships 3.2 — install via `brew install bash`) |
| `jq` | Everything |
| `curl` | Remote server mode only |
| `ANTHROPIC_API_KEY` | `llm` steps only |

macOS: `brew install bash jq`
Linux: `apt-get install -y jq curl`

### Install (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/opensop/opensop/main/cli/bin/opensop \
  -o /usr/local/bin/opensop && chmod +x /usr/local/bin/opensop
```

If `sudo` is needed for `/usr/local/bin`, use `~/.local/bin/opensop` and confirm it is on `$PATH`.

From source (hermetic / air-gapped):

```bash
git clone https://github.com/opensop/opensop.git /tmp/opensop
cp /tmp/opensop/cli/bin/opensop /usr/local/bin/opensop && chmod +x /usr/local/bin/opensop
```

Verify:

```bash
opensop --version    # opensop 0.9.1
opensop help         # full command reference
```

### Trust boundary

Local steps in a `.sop.json` execute arbitrary shell on the host — same posture as a Makefile. Never fetch and run process files from URLs the user has not reviewed.

---

## 2. Discover

Before writing anything, check whether a process already exists.

### Keyword search

```bash
opensop search lead                      # ranked text search (local)
opensop --remote search lead             # same, against server library
```

Output is ranked by name/description/tag match. Parse with `--json`:

```bash
opensop search lead --json | jq '.[].name'
```

### Intent-based match

```bash
opensop suggest "qualify an inbound lead"          # local
opensop --remote suggest "score a prospect"        # server
opensop suggest "extract action items" --threshold 0.6  # minimum confidence (0.0–1.0)
```

`suggest` returns the top-matching process name + score. If score is below threshold, nothing is returned — no false matches.

### Enumerate all processes

```bash
opensop list                             # processes visible from cwd (cell chain)
opensop list --tag extraction            # filter by tag
opensop --remote list                    # server library
```

### Machine-readable command index (new in v0.9.1)

```bash
opensop help --json                      # full command registry as JSON
opensop help --json | jq '.[] | select(.category=="discovery")'
```

Every command entry has: `command`, `summary`, `usage`, `category`, `backend` (`local` | `remote` | `dual`).

### When to stop searching and write a new process

Search first. Write new only when:
- `suggest` returns confidence < 0.6 on two distinct phrasings of the task.
- The matched process covers ≤ 50% of the steps you need.
- The task recurs and has a clear input/output boundary.

---

## 3. Run

v0.9.1 is local-first. `opensop run` runs on-machine with no server required.

### Start a run

```bash
opensop run ./extract-action-items.sop.json --input notes="$(cat meeting.txt)"
opensop run extract-action-items --input notes="$(cat meeting.txt)"   # bare name resolves in cell chain
opensop run extract-action-items --inputs '{"notes":"raw text here"}' # JSON object form
```

With `--json`, the run emits a JSON object on stdout when it starts (or completes synchronously):

```bash
opensop run extract-action-items --input notes="..." --json
# → {"run_id":"r-abc123","status":"running","process":"extract-action-items"}
```

### Validate without running

```bash
opensop dry-run ./my-process.sop.json --input key=value
```

Validates inputs and previews steps. No run is created.

### Check status

```bash
opensop status <run_id>                  # current state
opensop status <run_id> --json           # machine-readable
opensop steps  <run_id>                  # per-step state
opensop steps  <run_id> --json
```

`status` values: `running` | `waiting` | `completed` | `failed` | `interrupted`.

Poll until done:

```bash
until opensop status <run_id> --json | jq -e '.status != "running" and .status != "waiting"' >/dev/null; do
  sleep 2
done
```

### Resume a paused step

Some step types pause the run:

| Step type | Pause state | Resume command |
|---|---|---|
| `form` | `waiting_for_input` | `opensop submit <run_id> <step-id> --output key=value` |
| `approval` | `waiting_for_approval` | `opensop submit <run_id> <step-id> --output decision=approve` |
| `webhook` callback | `waiting_for_callback` | `opensop submit <run_id> <step-id> --output key=value` |
| `wait` with `until:` | `waiting_for_callback` | `opensop submit <run_id> <step-id>` |
| `subprocess` | propagates child pause | Resume the child run; parent auto-continues |

When paused, `manifest.waiting` records the step id, pause reason, and expected outputs. Inspect it:

```bash
opensop show <run_id> --json | jq '.manifest.waiting'
# → {"step":"collect-info","index":0,"reason":"waiting_for_input","expects":{"outputs":["notes"],"schema":[{"name":"notes","type":"string","required":true}]},"since":"..."}
```

Then submit:

```bash
opensop submit <run_id> collect-info --output notes="$(cat file.txt)"
```

Completed steps never re-run. The run resumes at the next unexecuted step.

### Cancel

```bash
opensop cancel <run_id> --reason "superseded by newer run"
```

### List and inspect runs

```bash
opensop runs                             # all local runs
opensop show <run_id>                    # manifest + per-step receipts
opensop show <run_id> --json            # machine-readable full receipt
opensop history --process extract-action-items --limit 10
opensop compass                          # top processes by run-count, recency, failure rate
```

### Remote server mode

```bash
opensop config set url https://your-server.example.com
opensop config set token <your-api-token>

opensop --remote run extract-action-items --input notes="..."
opensop --remote status <run_id>
opensop --remote submit <run_id> <step-id> --output key=value
opensop --remote schema extract-action-items    # full process definition from server
```

`--server <url>` overrides the configured URL for a single call.

---

## 4. Receipts and structured output

Every local run writes three files under `~/.opensop-local/runs/<run_id>/` (or `.opensop/runs/<run_id>/` when inside a cell):

| File | Contents |
|---|---|
| `manifest.json` | Status, cursor position, `waiting` block when paused, inputs, timestamps |
| `audit.jsonl` | Append-only log — one JSON object per step event |
| `context.json` | Accumulated outputs after each completed step |

### Parsing outputs

`show --json` returns `{manifest, steps}` where `steps` is an array of audit events (one per step execution). Each event has `.step` (the step id) and `.output` (the merged JSON output). Final outputs accumulate in `context.json`.

```bash
# final outputs after completion (context.json, keyed by step id)
cat ~/.opensop-local/runs/<run_id>/context.json | jq '.'

# specific step output from context
cat ~/.opensop-local/runs/<run_id>/context.json | jq '.["extract-items"]'

# specific step output from show --json steps array
opensop show <run_id> --json | jq '.steps | map(select(.step=="extract-items")) | last | .output'

# full step audit (each line is one audit event)
cat ~/.opensop-local/runs/<run_id>/audit.jsonl | jq 'select(.step=="extract-items")'
```

### Structured errors

When `--json` is set and a command fails, errors emit to stderr as:

```json
{"error": "process_not_found", "message": "No process named 'foo' in cell chain.", "hint": "Run 'opensop list' to see available processes."}
```

Parse them:

```bash
opensop run missing-process --json 2>/tmp/err.json || jq .error /tmp/err.json
```

---

## 5. Build a process

When a task recurs, has 3+ distinct steps, and has a clear input/output boundary, encode it.

### Process file shape

Process files are JSON (`.sop.json`). Minimal skeleton:

```json
{
  "opensop": "0.9.1",
  "name": "extract-action-items",
  "version": "1.0",
  "description": "Extract action items and owners from meeting notes.",
  "inputs": {
    "notes": { "type": "string", "required": true }
  },
  "outputs": {
    "action_items": { "from": "steps.extract.outputs.action_items" }
  },
  "steps": [
    {
      "id": "extract",
      "type": "llm",
      "model": "claude-haiku-4-5",
      "prompt": "Extract action items from these meeting notes: {{notes}}\n\nRespond with ONLY a JSON object of the form {\"action_items\": [{\"task\": \"...\", \"owner\": \"...\", \"due\": \"...\"}]}.",
      "expected_output_schema": {
        "action_items": { "type": "array", "required": true }
      }
    }
  ]
}
```

Key rules:
- `"opensop"` is optional in this bare form, but if present must be an allowlisted version — `0.9.1` for new files. (The wrapped/server form requires it.)
- `name` and step `id` must match `^[a-z0-9][a-z0-9_-]*$`.
- `"version"` is a quoted string.
- Step `id` values must be unique.

### Field types

| Type | Notes |
|---|---|
| `string` | Accepts `format: "email"` or `format: "uri"` |
| `number` | Integer or float |
| `boolean` | `true` / `false` |
| `enum` | Requires `"values": [...]` |
| `object` | Accepts a `"schema"` map of key→type |
| `string[]` / `number[]` / `object[]` | Arrays |

### The `from:` resolver

| Reference | Resolves to |
|---|---|
| `process.inputs.<name>` | A value passed at run start |
| `steps.<step-id>.outputs.<name>` | Output of a completed prior step |
| `instance.id` / `instance.started_at` | Runtime metadata |
| `env.<VAR_NAME>` | `ENV["VAR_NAME"]` — fails if unset |

Forward references (pointing to a step that hasn't run yet) fail at runtime.

### The twelve step types

Pick one per boundary. Stop if you need a type not in this list — you're likely over-engineering or need a spec extension.

| Type | What it does | Local support |
|---|---|---|
| `shell` | Raw shell command; stdout captured as output | Full |
| `automated` | Subprocess (any language) on stdin/stdout JSON | Full |
| `noop` | Pass-through; useful as placeholder | Full |
| `form` | Pause for structured human or agent input | Full (pause/resume) |
| `approval` | Binary human gate (approve/reject) | Full (pause/resume) |
| `llm` | LLM call; structured response validates against schema | Full (needs `ANTHROPIC_API_KEY`) |
| `wait` | Pause for duration or condition | Full (immediate for `seconds`; pause/resume for `until`) |
| `webhook` | Outbound HTTP call; sync or callback response mode | Full sync + callback; `poll` not implemented |
| `subprocess` | Start a child OpenSOP process; pause until it completes | Full (max depth 16) |
| `loop` | Iterate a subprocess over a collection | Full |
| `judgment` | LLM or human decision with confidence threshold | Not implemented locally — use server runtime |
| `notification` | Fire-and-forget email/Slack/SMS | Not implemented locally — use server runtime |

### Conditions

`condition:` on a step and `required_if:` on an output accept a small expression language:

- Operators: `== != > >= < <= && || !`
- Literals: numbers, `"quoted strings"`, `true`, `false`, `null`
- References: same syntax as `from:`

```json
{ "condition": "steps.review.outputs.decision == 'approve'" }
{ "condition": "process.inputs.country == 'US' && steps.verify.outputs.score > 0.8" }
```

No `eval`. No function calls. No regex.

### Validate your process file

```bash
opensop dry-run ./my-process.sop.json --input key=value
```

This does a full schema and input validation pass without creating a run.

---

## 6. openSOP-ize — the key agent skill

This is the highest-leverage thing an agent can do: take a prose "skill" or prompt a user runs repeatedly, and encode it as a `.sop.json` process — pinning scope, adding a schema, making deterministic parts real steps so the output is reliable and identical every time.

### When to openSOP-ize

openSOP-ize when a task has all three:
1. Runs more than once (it will be called again).
2. Has a clear input/output boundary (you know what goes in and what must come out).
3. Has at least one deterministic sub-step that can be separated from the LLM call.

### The transformation: before and after

**Scenario:** An AI consultant's team runs a meeting-notes debrief. They paste notes into a chat and ask the model to "extract the action items." Different runs produce differently-shaped JSON (or plain prose). Owners are sometimes missing. Schema changes with the model's mood.

---

**Before — naive prose prompt ("skill")**

```
You are a meeting notes analyst. Extract all action items from the notes I give you.
Return them as JSON.

Notes:
<paste meeting notes here>
```

Problems:
- No schema — output shape varies between runs.
- No scope — the model decides what counts as an "action item."
- No validation — a malformed response goes straight to the caller.
- Not repeatable — different model, different prompt, different day → different output.
- No audit trail — you can't see what ran or what it returned.

---

**After — openSOP-ized process**

`extract-action-items.sop.json`:

```json
{
  "opensop": "0.9.1",
  "name": "extract-action-items",
  "version": "1.0",
  "description": "Extract action items, owners, and due dates from meeting notes. Returns a typed JSON array.",
  "inputs": {
    "notes": {
      "type": "string",
      "required": true,
      "description": "Raw meeting notes text."
    },
    "meeting_date": {
      "type": "string",
      "required": false,
      "default": "(not provided)",
      "description": "ISO 8601 date of the meeting, e.g. 2026-08-05. Used to infer relative due dates."
    }
  },
  "outputs": {
    "action_items": { "from": "steps.extract.outputs.action_items" }
  },
  "steps": [
    {
      "id": "extract",
      "type": "llm",
      "model": "claude-haiku-4-5",
      "prompt": "Extract every action item from these meeting notes.\n\nMeeting date: {{meeting_date}}\n\nNotes:\n{{notes}}\n\nRules:\n- Include only explicitly assigned tasks, not discussion points.\n- If no owner is stated, set owner to null.\n- Express due dates as ISO 8601 or null if not mentioned.\n- Return a JSON object with key 'action_items' containing an array of objects, each with 'task' (string), 'owner' (string or null), 'due' (string or null).",
      "expected_output_schema": {
        "action_items": { "type": "array", "required": true }
      }
    }
  ]
}
```

Two renderer rules to remember:
- Prompt tokens use `{{key}}` where `key` is a plain identifier — it resolves directly from the accumulated run context. Inputs are merged into context at run start, so `{{notes}}` resolves the `notes` input. The `{{process.inputs.notes}}` syntax is not supported by the local renderer.
- Optional inputs that may be absent should declare a `"default"` in the input definition; the default is merged into context before the first step, so `{{meeting_date}}` always has a value.
- `expected_output_schema` is a flat object mapping field names to field-definition objects with `type` (`"string"`, `"number"`, `"boolean"`, `"enum"`, `"array"`) and optionally `required: true`. Array shorthand (e.g. `[{"task":"string"}]`) and union strings (e.g. `"string|null"`) are not valid — the engine ignores unknown type values silently.

Run it:

```bash
opensop run extract-action-items.sop.json \
  --input notes="$(cat meeting-2026-08-05.txt)" \
  --input meeting_date=2026-08-05 \
  --json
```

The CLI's `llm` step:
- Strips markdown fences before JSON parsing.
- Validates the response against `expected_output_schema`.
- Retries automatically on schema mismatch (up to the configured retry count).
- Writes the validated output to `context.json`.

---

**What changed and why it matters**

| Dimension | Before (prose prompt) | After (openSOP process) |
|---|---|---|
| Output shape | Variable — model decides | Fixed schema, validated before caller receives it |
| Scope | Unbounded — model includes what it likes | Explicit rules in the prompt; scope is part of the file |
| Retries | None — caller handles failures | CLI retries on schema mismatch automatically |
| Auditability | None | `audit.jsonl` records every call, output, and timestamp |
| Reproducibility | Re-derive the prompt every time | `opensop run extract-action-items` — same file, same behavior |
| Evolution | Edit the chat | `git diff`, `opensop fork`, `opensop lineage` |
| Discovery | Grep chat history | `opensop search action items` or `opensop suggest "pull out tasks"` |

---

### openSOP-ize checklist

Work through these in order. Stop at the first item that doesn't hold — fix it before proceeding.

1. **Name it.** One slug: `extract-action-items`. Must match `^[a-z0-9][a-z0-9_-]*$`.
2. **Declare inputs.** What must be provided for this to run? Mark required ones. Add a description for each.
3. **Declare the output schema.** What must come back? Type every field. The LLM step validates against this.
4. **Split deterministic from generative.** If there is a step that transforms, validates, or routes data without needing an LLM — make it `shell` or `automated`. The LLM step does only what needs intelligence.
5. **Write the prompt as part of the file.** The prompt is infrastructure now. It must be explicit about scope, output format, and edge cases (no owner → `null`, not omitted).
6. **Set `model` explicitly.** Never rely on a default. Pin the model in the step.
7. **Validate.** `opensop dry-run ./extract-action-items.sop.json --input notes="test"`

---

## 7. Iterate and evolve

OpenSOP processes evolve like code — fork, adapt, record lineage.

### Fork a process

```bash
opensop fork extract-action-items          # copy from nearest ancestor cell
opensop fork extract-action-items --from /path/to/cell   # from a specific cell
```

Forking records lineage automatically. The new copy starts in `unverified` status.

### Annotate lineage

```bash
opensop annotate extract-action-items promote '{"to":"m2","by":"alice@example.com"}'
opensop annotate extract-action-items bless   '{"by":"human","note":"verified on 20 meetings"}'
```

Event types: `promote`, `bless`, `deprecate`, `fork`, and any custom event type.

### Inspect lineage

```bash
opensop lineage extract-action-items         # status, metadata, history
opensop lineage extract-action-items --json  # machine-readable
```

### Compare runs

```bash
opensop diff <run_id_1> <run_id_2>           # diff outputs of two runs of the same process
```

Useful when iterating on prompt changes: run twice with different versions, diff the outputs.

### Evolution policy

The mineralization tiers (m0–m6), transition rules, and lineage annotation conventions are documented in [EVOLUTION.md](../EVOLUTION.md). The `opensop evolve` command and the m-tier policy fields (`lineage.metadata.m`) described there are experimental — they are not yet frozen in the SPEC and may change before S0b.

---

## 8. Self-check rubric

Run through these before committing or running a process. The engine rejects processes that fail format checks; the rest are authoring best practices.

### Format (engine enforced)
- [ ] `"opensop": "0.9.1"` at the top.
- [ ] `"version"` is a quoted string, not a bare number.
- [ ] Every `name` and `id` matches `^[a-z0-9][a-z0-9_-]*$`.
- [ ] Step `id` values are unique within the process.

### Structure
- [ ] `name`, `version`, and `steps` are all present.
- [ ] Every step has `id` and `type`.
- [ ] `type` is one of the twelve listed in §5.

### Data flow
- [ ] Every `from: process.inputs.X` has a matching entry in `inputs`.
- [ ] Every `from: steps.Y.outputs.Z` refers to a step that appears earlier in the step list.
- [ ] Every `form`, `approval`, `judgment`, and `webhook` step declares `outputs`.
- [ ] Enum types have `values` populated.
- [ ] `automated` steps have a script file at the resolved path.

### LLM steps
- [ ] `model` is set explicitly.
- [ ] `expected_output_schema` is declared.
- [ ] Prompt includes explicit output format instructions and edge-case handling.

### Conditions
- [ ] Every `condition:` / `required_if:` uses only the supported operators.
- [ ] Fields referenced in conditions exist in the output schema of the referenced step.

---

## 9. Common mistakes

**`run:` path doesn't resolve.** In server mode, `run:` is relative to the `sops/` library root, not to the process file. A YAML at `sops/examples/my-process.sop.yaml` must write `run: "./examples/steps/my-script.rb"`, not `"./steps/my-script.rb"`.

**Condition always true/false.** The evaluator treats missing identifiers as `null`, which compares false to almost everything. Check the exact output key name on the upstream step.

**`from:` resolution error at runtime.** The referenced step completed but its output key name differs. Keys must match exactly (`account_id` ≠ `accountId`).

**LLM step fails schema validation repeatedly.** The `expected_output_schema` or the prompt's output instructions are inconsistent. Make the prompt say exactly what the schema requires, including null handling for optional fields.

**Unquoted version.** `version: 1.0` in YAML parses as a float. Always quote: `version: "1.0"`.

**Webhook step never advances.** The callback URL was not given to the third party, or its payload keys don't match the step's declared `outputs`. Check `opensop show <run_id> --json | jq '.manifest.waiting'`.

**`declare: -A: invalid option`.** bash 3.x is in use. Install bash 4+ (`brew install bash` on macOS).

**`jq: command not found`.** Install: `brew install jq` / `apt install jq`.

---

## 10. CLAUDE.md snippets

Paste the block that matches how you want an agent to use OpenSOP.

**Local mode (no server):**

```markdown
## OpenSOP (local)

Before starting any multi-step task (3+ distinct steps, clear inputs/outputs, likely to repeat):

  opensop search <keyword>
  opensop suggest "<task description>"
  opensop list

If a matching process exists, run it:
  opensop run <name|file.sop.json> --input k=v

If a run pauses (form / approval / wait / webhook callback), check what it needs:
  opensop show <run_id> --json | jq '.manifest.waiting'
  opensop submit <run_id> <step-id> --output k=v

Check all local runs: opensop runs
Full receipt: opensop show <run_id> --json
llm steps require ANTHROPIC_API_KEY in the environment.

If no process matches, propose writing a .sop.json before doing the task ad-hoc.
```

**Remote server:**

```markdown
## OpenSOP (remote server)

Check before any multi-step task:
  opensop --remote search <keyword>
  opensop --remote suggest "<task description>"
  opensop --remote list

Run a matching process:
  opensop --remote run <name> --input k=v
  opensop --remote status <run_id>
  opensop --remote submit <run_id> <step-id> --output k=v
  opensop --remote schema <name>          # full process definition

If no process matches, write a .sop.json (see docs/AGENTS.md §6).
```

**When to propose a new process:** a task has 3+ distinct steps, a clear input/output boundary, and will run again. Pause, propose writing a `.sop.json` first, then run it.

**When to stop and ask:**
- A step boundary needs a type not in the twelve. Don't invent types — flag it.
- A condition requires operators beyond the supported set. Propose a spec extension.
- The description is ambiguous about a boundary (form vs. approval?). One question is cheaper than a wrong guess.
- A process file comes from a URL the user has not reviewed. Ask before running it.

---

## 11. Adopt OpenSOP in your agent — AGENTS.md block

Drop this block into your project's `AGENTS.md` (or `CLAUDE.md`, `.cursorrules`, etc.) so any AGENTS.md-honoring runtime — Codex, Cursor, Claude Code, and others — automatically knows how to use OpenSOP when working in your repo.

```markdown
## OpenSOP — process-as-infrastructure

SOPs live in `./sops/` (or alongside the code they relate to as `.sop.json` files).

**Discover** before starting any multi-step task:
  opensop search <keyword>          # ranked text search
  opensop list                      # enumerate all processes in the cell chain

**Run** a matching process:
  opensop run <name|file.sop.json> --input k=v

**Inspect and heal** a run:
  opensop ps                        # running/waiting processes
  opensop show <run_id> --json      # full receipt
  opensop heal <run_id>             # diagnose a failure
  opensop heal <run_id> --apply     # retry the failed step

**Onboard** / first-run:
  opensop onboard                   # scaffold a starter process and prove the reliability gain

**Pull and share SOPs** (the public library at github.com/opensop/sops):
  opensop pull opensop/daily-standup-notes   # download an SOP
  opensop import ./my-sop.sop.json           # import from a local file
  opensop info ./my-sop.sop.json             # inspect metadata

  SAFETY: pulled and imported SOPs are untrusted code (shell/automated
  steps run arbitrary host shell). READ the run commands directly —
  `jq '(.process.steps // .steps)[] | {id,type,run}' <file>` — and get user
  confirmation before `opensop run`. `opensop dry-run <file>` previews the
  step FLOW but does NOT print command bodies, so it is not sufficient review
  on its own. `pull`/`import` only write the file — they never execute it.

**Self-check**:
  opensop doctor                    # version, jq, bash, skill installation status
```

---

## 12. Runtime → skill path table

Install OpenSOP as a SKILL.md skill so any supported agent runtime can load its
capability description automatically.  One command installs to the right place:

```bash
opensop skill install --runtime <flavour>    # install for a specific runtime
opensop skill paths                          # authoritative flavour → path table
```

| Flavour | Scope | Canonical install path |
|---|---|---|
| `claude` | project | `.claude/skills/opensop/SKILL.md` |
| `claude` | user | `~/.claude/skills/opensop/SKILL.md` |
| `codex` / `agentskills` | project | `.agents/skills/opensop/SKILL.md` |
| `codex` / `agentskills` | user | `~/.agents/skills/opensop/SKILL.md` |
| `hermes` | project | `.hermes/skills/opensop/SKILL.md` |
| `hermes` | user | `~/.hermes/skills/opensop/SKILL.md` |
| `openclaw` | project | `skills/opensop/SKILL.md` |
| `openclaw` | user | `~/.claw/skills/opensop/SKILL.md` |
| `openhands` | project | `.openhands/skills/opensop/SKILL.md` |
| `goose` | user | `~/.config/goose/skills/opensop/SKILL.md` |
| `cline`, `cursor`, `continue`, `aider` | — | Rules-only — no SKILL.md slot; use the AGENTS.md block from §11 instead |

`opensop skill paths` is the authoritative source — it reads the embedded registry
and always reflects what the installed CLI supports.

### Which mechanism?

| Mechanism | What it is | When to use it |
|---|---|---|
| **SKILL.md** (Agent Skills standard) | A portable capability description the runtime loads once per project or user install | Install once per runtime; gives the agent the full command surface, key patterns, and safety rules at load time |
| **AGENTS.md block** (§11) | Always-on project context baked into your repo | Use in every project so agents operating in your codebase always know the SOP conventions, regardless of whether they have the SKILL.md installed |

Use both: SKILL.md teaches the agent *how* OpenSOP works; the AGENTS.md block
tells it *where* your processes live and what conventions your project follows.
