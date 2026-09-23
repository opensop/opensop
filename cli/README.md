# OpenSOP CLI

A bash CLI for running and managing OpenSOP processes — locally on your machine, or against any OpenSOP server. One file; only `jq` required for local use.

## Why

OpenSOP is an open standard for executable processes — define a YAML, get a typed REST API. This CLI runs those processes locally (no server, no daemon, no network) and can also talk to a running OpenSOP server over its `/sop/*` HTTP API. It exists so agents (and humans) can drive OpenSOP from any terminal, immediately.

## Two backends: local (default) and remote (`--remote`)

The CLI is one interface to **two backends**. By default it runs processes **locally on your machine** — no Rails app, no daemon, no network, no `curl`:

```bash
opensop run ./greet.sop.json --input name=Ana       # local: runs on this machine, no server
opensop run lead-qualification --input lead_name=Ana # local: looks up the process in the cell chain
```

Add `--remote` (or `--server <url>`) to talk to an OpenSOP server instead:

```bash
opensop --remote run lead-qualification --input lead_name=Ana   # remote: hits the configured server
opensop --server https://demo.opensop.ai list                    # remote: one-call server override
```

Local execution needs only `bash` + `jq`. Remote needs `curl` too.

```bash
opensop run ./greet.sop.json           # run a process locally
opensop list [dir]                     # list .sop.json processes in the cell chain
opensop runs                           # list local runs
opensop show <run_id>                  # a local run's manifest + per-step receipts
bash test/test.sh                      # golden test
```

> **`--local` flag:** accepted for backwards compatibility but now a no-op (local is already the default). Scripts using `opensop run ./x.sop.json --local` continue to work; they will see a deprecation note on stderr. Drop `--local` from new scripts.

**Process format:** `.sop.json` (jq-native), mirroring `SPEC.md` v0.9.1. **Step I/O contract:** each step gets the accumulated context (inputs + prior outputs) on stdin and in `$OSL_CONTEXT`; its JSON stdout merges back under the step id. **Step types (local — v0.7 full SPEC parity):**

| Type | Pause? | Resume trigger | Notes |
|---|---|---|---|
| `automated` / `shell` | No | — | Runs a shell script; JSON stdout merged into context |
| `noop` | No | — | Pass-through; no execution |
| `form` | Yes — `waiting_for_input` | `submit --output k=v` | Collects structured human/agent input |
| `approval` | Yes — `waiting_for_approval` | `submit --output decision=approve\|reject` | Defaults to `decision` enum; fully configurable |
| `wait` | `wait.seconds` → No; `wait.until` → Yes — `waiting_for_callback` | `submit` (no outputs required) | `wait.seconds` completes immediately with `{waited:true}` |
| `llm` | No | — | Calls Anthropic Claude; requires `ANTHROPIC_API_KEY`; model must start with `claude` |
| `webhook` | sync → No; callback → Yes — `waiting_for_callback` | `submit --output k=v` | sync asserts 2xx; poll mode not yet implemented |
| `subprocess` | Propagates child pause | child resume | Recursive local execution; depth-guarded (max 16) |

**Pause/resume lifecycle:** when a step pauses the run, `manifest.status` becomes `waiting` and `manifest.waiting` records the step, reason, and what outputs are expected. Resume with:

```bash
opensop submit <run_id> <step-id> --output key=value
```

Execution re-enters at `cursor.next_index` — never re-runs completed steps.

**Step executor (v0.6):** each step may declare `executor: internal|external`. `external` = work happens in an outside process (script, webhook), OpenSOP orchestrates and receives the receipt; `internal` = the OpenSOP runtime handles the step itself. Optional; defaults apply per step type (`automated`/`shell`/`webhook` → external, `noop`/`form`/`approval`/`notification`/`wait`/`judgment` → internal). Invalid values fail loudly at parse time. The effective executor is recorded in each step's audit receipt.

**Step effects (v0.7.x):** each step may declare `effects: "<plain-string description>"` (e.g. `"publishes a post to LinkedIn"`) to mark it as irreversible — it acts on the world, not just on the run's data. The presence of the field is the signal; there is no enum or boolean form. `opensop heal --apply` refuses to re-run a step that declares `effects` (see the `heal` row above) because it may have already succeeded remotely before the CLI observed the failure.

**Receipts:** `$OPENSOP_LOCAL_HOME/runs/<id>/{manifest.json, audit.jsonl, context.json}`. As of v0.6: when cwd is inside an OpenSOP cell, `$OPENSOP_LOCAL_HOME` defaults to the active cell's `.opensop/` (receipts land alongside the processes that produced them); outside any cell it defaults to `~/.opensop-local`. Explicit env override always wins. **Name resolution (v0.6):** inside a cell, `opensop run <name>` looks up `processes/<name>.sop.json` in the active cell, then each ancestor cell (nearest wins). Explicit file paths still work as before. The same process file is meant to run on a server runtime *and* locally — portability is the point.

> **⚠ Trust boundary:** local steps execute as shell **on your machine** — a `.sop.json`'s `shell`/`automated` steps run arbitrary commands. Only run process files you trust (same posture as a `Makefile` or an npm `postinstall`). This matters most for agents: don't `opensop run` a process file you just fetched from an untrusted source.
>
> **Note on `--local`:** accepted for backwards compatibility but now a deprecated no-op (v0.9.1+ default is local). In v0.5–v0.7 `--local` opted into local execution; in v0.9.1 local is the default so `--local` can simply be dropped from scripts — no other migration needed. For a local dev *server*, use `opensop --server http://localhost:3000` or `opensop config set url http://localhost:3000`.

## Install

### Platform matrix

| Platform | Status | Notes |
|---|---|---|
| Linux | Supported | bash 4+ is the distro default |
| macOS | Supported | Requires bash 4+ — see below |
| Windows | WSL only | Run inside a WSL Ubuntu/Debian shell |

**macOS bash caveat:** macOS ships bash 3.2 (GPL licensing prevented Apple from updating it). The CLI requires bash 4+. Install a current bash via Homebrew:

```bash
brew install bash
echo "$(brew --prefix)/bin/bash" | sudo tee -a /etc/shells
chsh -s "$(brew --prefix)/bin/bash"
```

### Installer (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/opensop/opensop/main/cli/install.sh | bash
```

Installs to `~/.local/bin/opensop` (user-writable, no sudo). Options:

```bash
# Pin to a specific release
curl -fsSL .../install.sh | bash -s -- --version 0.8.1

# Install system-wide (requires write access to /usr/local/bin)
curl -fsSL .../install.sh | bash -s -- --prefix /usr/local

# Preview without making changes
curl -fsSL .../install.sh | bash -s -- --dry-run
```

The installer checks bash version, verifies `jq` is available, and prints a `$PATH` hint if `~/.local/bin` is not yet on your path. See [Install verification & threat model](#install-verification--threat-model) for what the checksum check does and does not protect against.

### Direct download (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/opensop/opensop/main/cli/bin/opensop \
  -o ~/.local/bin/opensop && chmod +x ~/.local/bin/opensop
```

### From source

```bash
git clone https://github.com/opensop/opensop.git
cp opensop/cli/bin/opensop ~/.local/bin/
chmod +x ~/.local/bin/opensop
```

The CLI is a single bash file living at `cli/bin/opensop` in the [opensop](https://github.com/opensop/opensop) repo (the `opensop-cli` repo is archived — all development continues here).

### Upgrade

Once installed, keep it current with:

```bash
opensop upgrade              # latest release
opensop upgrade --pin 0.9.1  # specific version
```

### Requirements

- `bash` 4+ (Linux default; macOS needs `brew install bash` — see above)
- `jq` — `brew install jq` / `apt install jq` / `dnf install jq`
- `curl` — needed by `install.sh`, `opensop upgrade`, and the **remote backend** (`--remote` / `--server`); local execution does not need it

## Install verification & threat model

**What checksum verification does — and doesn't — protect against.** The installer and `opensop upgrade` fetch a companion `.sha256` file and refuse to replace your binary unless the download's SHA-256 matches (opt out with `--allow-unverified`). This protects against *corruption in transit*: truncated downloads, CDN/proxy mangling, and partial caches. It does **not** protect against a compromised source: the binary and its checksum are served from the same GitHub origin, so an attacker who can modify this repository or its CDN path can replace both consistently. There are no cryptographic signatures on releases today, and we won't pretend a checksum is one. Your actual trust anchor when running `curl … | bash` is TLS to `raw.githubusercontent.com` plus the integrity of this repository and its maintainer's GitHub account. If that trust model is insufficient for your environment, be precise about what each mitigation buys you:

- **Reproducibility, not authenticity** (these help you pin and re-verify a *known* revision, but do **not** defend against a compromised account — the git history, tags, and GitHub Release notes are all controlled through the same repository/account, so an attacker with that access can rewrite them consistently): install from a specific tag with `--pin X.Y.Z`, and record the digest you trusted so upgrades are diffable.
- **Independent verification** (the only measures that actually escape the same-origin/same-account boundary): read `install.sh` and `bin/opensop` yourself before running them (they're plain bash — that's the point), or vendor the file into a repository *you* control and diff every upgrade against your own trusted copy. Compare the digest against a copy you obtained through a channel you trust independently of this account, not against artifacts served from it.

There is no cryptographic authenticity check available today — if that is a hard requirement for you, treat this install as unverified until you have vendored and reviewed it. We may add Sigstore-based release signing later if the project gains CI; we'd rather ship no signature than an unverified one.

## Quick start

### Local (no server)

Drop a process file and run it — no config required:

```bash
# Write a minimal process
cat > greet.sop.json <<'JSON'
{ "name": "greet", "inputs": [{"name":"name","type":"string","required":true}],
  "steps": [{ "id": "say", "type": "shell", "executor": "external",
              "run": "echo \"hello, $name\"" }] }
JSON

opensop run ./greet.sop.json --input name=Ana
opensop runs               # list all local runs
opensop show <run_id>      # receipts + audit log
```

Inside an OpenSOP cell (`opensop init`), bare process names resolve automatically:

```bash
opensop run greet --input name=Ana   # looks up processes/greet.sop.json in the cell chain
```

### Remote server

Point the CLI at a server (the public demo is at `demo.opensop.ai`):

```bash
opensop config set url https://demo.opensop.ai
opensop config set token demo-public-token-resets-daily
```

Discover what processes are registered:

```bash
$ opensop --remote list
agent-pr-review                  developer-tooling, code-review, agent-harness, ai  An agent reviews a PR diff…
lead-qualification               growth, sales, qualification              Qualify an inbound lead and score…
```

Search by intent (works locally too — scans the cell chain):

```bash
$ opensop --remote search lead
2     lead-qualification           (growth, sales, qualification)  Qualify an inbound lead and score their fit
```

Start a remote run:

```bash
opensop --remote run lead-qualification \
  --input lead_name="Ana García" \
  --input lead_email=ana@example.com \
  --input source=website
```

You'll get a run ID back. The CLI caches the ID → process name mapping so subsequent commands take just the ID:

```bash
opensop --remote status <run-id>
opensop --remote steps <run-id>
```

Advance a paused step (form / judgment / approval):

```bash
opensop --remote submit <run-id> collect-context \
  --output budget=12000 \
  --output timeline=immediate \
  --output notes="Strong fit, spoke to CEO" \
  --decided-by agent:my-bot \
  --confidence 0.92
```

Preview a remote process without executing it:

```bash
opensop --remote dry-run lead-qualification \
  --input lead_name="Ana García" \
  --input lead_email=ana@example.com \
  --input source=website
```

This validates inputs against the process schema and describes each step — no run is created. Exit code 1 if validation fails.

Cancel a run:

```bash
opensop --remote cancel <run-id> --reason "lead unresponsive"
```

List all runs on the server:

```bash
opensop --remote instances --state running --limit 20
```

## Worked example

A full `lead-qualification` run from start to completion on the remote server — what each command returns and what to do next.

**Step 1: start the run**

```
$ opensop --remote run lead-qualification \
    --input lead_name="Ana García" \
    --input lead_email=ana@example.com \
    --input source=website

✓ started lead-qualification
  id:    e33baee4-84d3-4d04-b902-2f50437d8191
  state: running

waiting:
  collect-context (form): waiting_for_input

next:  opensop status e33baee4-84d3-4d04-b902-2f50437d8191
```

The run is paused at the first step — a `form` step waiting for human or agent input.

**Step 2: inspect the steps**

```
$ opensop --remote steps e33baee4-84d3-4d04-b902-2f50437d8191

collect-context    form           active    waiting_for_input
score-lead         automated      pending
notify-team        notification   pending
```

**Step 3: submit the paused step**

```
$ opensop --remote submit e33baee4-84d3-4d04-b902-2f50437d8191 collect-context \
    --output budget=12000 \
    --output timeline=immediate \
    --output notes="Strong fit, spoke to CEO" \
    --decided-by agent:my-bot \
    --confidence 0.92

✓ submitted collect-context (completed) — run running
next:  opensop status e33baee4-84d3-4d04-b902-2f50437d8191
```

The form step is complete. The runtime moves to `score-lead` (automated) and `notify-team` (notification) automatically.

**Step 4: poll until done**

```
$ opensop --remote status e33baee4-84d3-4d04-b902-2f50437d8191

run:      e33baee4-84d3-4d04-b902-2f50437d8191
process:  lead-qualification
state:    completed (2026-05-08T20:28:41Z)

  ✓ collect-context              form
  ✓ score-lead                   automated
  ✓ notify-team                  notification
```

That's the run-pause-submit-poll lifecycle. The receipt is stored in the runtime's database; `opensop --remote instances --process lead-qualification` will show all historical runs.

## Output modes

By default the CLI is **TTY-aware**: pretty-printed in a terminal, JSON when piped.

```bash
opensop list                    # pretty in terminal, JSON when piped
opensop list --json             # always JSON
opensop list --pretty           # always pretty (well, always indented JSON outside a TTY)
opensop status <id> | jq ...    # piping → JSON automatically
```

When `--json` is set, **errors also emit JSON to stderr**: server errors round-trip via `{error, message, ...}` from the engine (augmented with `_meta.http_status`); CLI-side errors (config missing, file not found, invalid input, unknown command, etc.) emit `{error, message, hint?}` from the same envelope. Agents can parse stderr the same way they parse stdout.

```bash
$ opensop --json schema validate /nonexistent.yaml 2>&1 1>/dev/null
{"error":"file_not_found","message":"file does not exist: /nonexistent.yaml"}
```

Set `NO_COLOR=1` to disable ANSI color.

**`OPENSOP_SOPS_BASE`** overrides the base URL used by `opensop pull` (default: `https://raw.githubusercontent.com/opensop/sops`). Set it to a `file://` URL pointing at a local directory with the same `<ref>/<author>/<slug>/<slug>.sop.json` layout for offline testing or air-gapped environments. `OPENSOP_RECIPES_BASE` is a deprecated alias — honoured (with a stderr deprecation warning) only when `OPENSOP_SOPS_BASE` is unset.

## Input forms

Three ways to provide inputs to `run` (and outputs to `submit`):

```bash
# Inline JSON
opensop run X --inputs '{"lead_name": "Ana", "source": "website"}'

# JSON file
opensop run X --inputs-file ./inputs.json

# Key=Value pairs (repeatable; values that look like JSON parse as JSON)
opensop run X \
  --input lead_name="Ana García" \
  --input source=website \
  --input budget=12000 \
  --input urgent=true
```

For `submit`, swap `--inputs/--input` for `--outputs/--output`, plus optional `--decided-by` and `--confidence`.

You can also attach metadata to a `run`:

```bash
opensop run lead-qualification \
  --input lead_name=Ana \
  --metadata source_system=crm \
  --metadata external_id=lead_8821
```

## Configuration

Config lives at `~/.opensop/config` (or `$OPENSOP_HOME/config` if set). Two values:

```
OPENSOP_URL="https://your-server"
OPENSOP_TOKEN="your-x-sop-token"
```

Override per-call via env vars:

```bash
OPENSOP_URL=https://prod.opensop.ai opensop --remote list
```

> **Note:** `OPENSOP_URL` alone does not enable remote mode — pair it with `--remote` or `--server`.

To point at a local dev **server** for a single call, use `--server` or set `OPENSOP_URL`:

```bash
opensop --server http://localhost:3000 list                       # hit your dev server
OPENSOP_URL=http://localhost:3000 opensop --remote run lead-qualification ... # test against it before prod
```

## Process authoring

The CLI supports the full authoring loop for `.sop.yaml` files — from lint to registration.

**Step 1: lint your file**

`schema validate` is fully client-side (no server round-trip). It checks structural requirements using `yq` (mikefarah/yq v4+) if installed, or `python3` + PyYAML as a fallback:

```bash
opensop schema validate ./my-process.sop.yaml
```

What it checks:

- Top-level `opensop` version field present
- `process` object with `name`, `version`, `description`, `inputs` (array), `steps` (array)
- Each step has `id` and `type`; `type` is one of the known values (`form`, `automated`, `judgment`, `approval`, `webhook`, `notification`, `subprocess`, `loop`, `llm`, `wait`)
- Each input has `name` and `type`
- All `from:` reference strings match `steps.X.outputs.Y` or `process.inputs.Y`

Exit 0 if valid, 1 if errors. Use `--json` to get a structured `{file, valid, errors}` object.

**Step 2: preview execution**

Run `dry-run` to validate inputs against the process schema and walk through each step's description without creating an instance:

```bash
opensop dry-run my-process --input foo=bar
```

Exit 0 if inputs are valid, 1 if validation fails.

**Step 3: register** (requires a remote server)

```bash
opensop --remote register ./my-process.sop.yaml
# or: opensop --server https://your-server register ./my-process.sop.yaml
```

POSTs the file to `/sop/processes/register`. On success, prints `registered <name>@<version>`. If the server returns 401/403, registration may be admin-only — check your token scope or use the dashboard at `<OPENSOP_URL>/admin`.

`register` always requires `--remote` or `--server`; calling it without either exits with `usage_error`.

## Subcommand reference

Commands marked **[remote]** require `--remote` or `--server <url>`. All others default to local.

| Command | Purpose |
|---|---|
| **Discovery** | |
| `opensop list [--tag <tag>]` | List processes in the cell chain (local) or from the server (**[remote]** with `--remote`) |
| `opensop search <keyword> [...]` | Ranked text search over process names, descriptions, and tags |
| `opensop suggest "<task description>"` | Describe a task in prose; get the top-matching process back |
| `opensop schema <name>` | **[remote]** Full process definition (`GET /sop/<name>/schema`) — requires `--remote` or `--server` |
| **Inspection** | |
| `opensop ps [--follow]` | Process status table: `open`/`running`, last result, last/next run time. `--follow` polls every 2s. (**[remote]** `GET /sop/processes/status` with `--remote`) |
| `opensop watch [--interval N]` | Live-refreshing terminal dashboard. Auto-clears and reprints every `N` seconds (default 2). `--json` emits NDJSON — one compact array per refresh, no escapes. Ctrl-C to exit cleanly. (**[remote]** `GET /sop/processes/status` with `--remote`) |
| `opensop status <run_id>` | State of a local run (or **[remote]** `GET /sop/<name>/<id>` with `--remote`) |
| `opensop steps <run_id>` | Per-step state of a local run (or **[remote]** with `--remote`) |
| `opensop diff <id1> <id2>` | Compare two runs of the same process |
| `opensop history --process <name> [--limit N]` | Recent runs of a specific process, newest-first |
| `opensop compass` | Top processes by run-count, recency, and failure rate |
| **Execution** | |
| `opensop run <name\|file> [opts]` | Start a local run (or **[remote]** `POST /sop/<name>/start` with `--remote`) |
| `opensop dry-run <name\|file> [opts]` | Validate inputs + preview steps — no run created |
| `opensop submit <run_id> <step-id> [opts]` | Resume a paused local run (or **[remote]** with `--remote`) |
| `opensop cancel <run_id> [--reason TEXT]` | Cancel a local run (or **[remote]** with `--remote`) |
| `opensop runs` | List all local runs |
| `opensop show <run_id>` | Local run manifest + per-step receipts |
| `opensop heal <run_id> [--apply] [--force-effects] [--input k=v ...]` | Diagnose a failed run (print fault + debug_prompt); `--apply` re-runs the failed step and continues from there (closed heal loop). Fault records may contain input data — local only, never committed (SPEC §11.4). If the failed step declares `effects` (SPEC §3.2 — it acts on the world, e.g. "publishes a post to LinkedIn"), `--apply` refuses and exits non-zero: the step may have already succeeded before the observed failure, so a blind retry can double-post/double-send/double-spend. Pass `--force-effects` to re-run it anyway. |
| **Authoring** | |
| `opensop register <process.yaml>` | **[remote]** POST a `.sop.yaml` to `/sop/processes/register` — requires `--remote` or `--server` |
| `opensop schema validate <file.yaml>` | Client-side YAML lint — always local, no server round-trip |
| **Cells (v0.6)** | |
| `opensop init [--name N] [--parent PATH]` | Create `.opensop/` in cwd; cwd becomes the active cell. Auto-detects parent from ancestor cell when present. |
| `opensop scope` | Print the active cell + ancestor chain (nearest-first); errors if cwd is not inside a cell |
| `opensop annotate <skill> <event-type> <json>` | Append a policy event to the skill's lineage history in the active cell. Event type is open-string; data is whatever JSON the policy needs. |
| `opensop lineage <skill>` | Print a skill's lineage entry (status, metadata, history) in the active cell. Returns the empty default if no events have been recorded yet. |
| `opensop fork <name> [--from <cell>]` | Materialize an ancestor cell's skill in the active cell. Copies `processes/<name>.sop.json` over, then records a lineage entry with `forked_from = {cell, forked_at, snapshot}` where `snapshot` captures the parent's `status` and `metadata`. Child's live status + metadata start empty (policy decides what to do with the snapshot). Refuses to overwrite an existing skill. |
| `opensop list --conflicts` | Inside a cell, walk the chain and **mark shadowed entries**. The first occurrence of each filename (nearest cell that has it) is tagged `← active`; subsequent occurrences in ancestors are tagged `← shadowed by [cell-name]`. |
| **Admin** | |
| `opensop instances [--state X] [--process Y]` | List runs — local by default; **[remote]** paginated `GET /sop/instances` with `--remote` |
| **Config** | |
| `opensop config [set <key> <value>]` | Manage remote server config (url + token) |
| `opensop help [<command>\|agents] [--json]` | Full help, per-command detail, agent quick-start, or machine-readable JSON index |
| **Bench** | |
| `opensop bench [<task-dir>] [--n N] [--model MODEL] [--arm ARMNAME] [--stub]` | 3-arm reliability comparison: skill vs json_only vs opensop over N runs. Built-in default task: extract-action-items. `--stub` runs offline (no API key). |
| **Onboarding** | |
| `opensop onboard [<process.sop.json>] [--stub] [--n N]` | First-run experience: scaffold a starter `.sop.json` if none given, validate it via dry-run, run the 3-arm bench comparison (built-in task only) to prove the reliability gain, and print next steps. Side-effect-safe: never executes your process against production. `--stub` runs offline. To benchmark a custom task use `opensop bench <task>` directly. |
| **Agent Skills** | |
| `opensop skill show` | Print the embedded SKILL.md to stdout — no file written. Lets an agent read the skill content without installing it. |
| `opensop skill install <dir> [--force]` | Write the embedded SKILL.md to `<dir>/opensop/SKILL.md` (creates dirs as needed). Requires `--force` to overwrite an existing file. |
| `opensop skill install --runtime <flavour> [--scope user\|project] [--force]` | Install the SKILL.md at the canonical path for the given agent runtime (see table below). Rules-only runtimes (`cline`, `cursor`, `continue`, `aider`) print guidance instead (exit 0, no file written). Unknown flavour → `usage_error` listing valid names. |
| `opensop skill paths [--json]` | Print the flavour→path registry as a TTY table or JSON object. This is the authoritative reference for where each runtime expects the skill file. |
| `opensop doctor [--json]` | Self-check: opensop version + PATH, jq present, bash ≥4, per-runtime skill installation status. Exits non-zero only on CRITICAL failure (jq missing, bash too old). Missing skills are informational. |
| **SOPs** | |
| `opensop pull <author>/<slug>[@<ref>]` | Download an SOP from the [opensop/sops](https://github.com/opensop/sops) library (`<author>/<slug>/<slug>.sop.json`). Defaults to `main`; pin with a commit SHA: `opensop pull opensop/daily-standup-notes@a1b2c3d`. `--output <path>` overrides the default `./<slug>.sop.json`. No-clobber without `--force`. Prints a summary (name, version, step count + types, source, sha256) and a "review before running" note. **Never executes the file.** `--verify <sha256>` enforces a hash the user supplies out-of-band. Requires curl. |
| `opensop import [<file>\|-] [--output <path>] [--force]` | Read an SOP from a local file or stdin (`-`), validate it as a process, write to `./<name>.sop.json` or `--output <path>`, no-clobber without `--force`. Prints the same summary; **never executes the file.** Local-only (no curl). |
| `opensop info <file.sop.json>` | Print an SOP's `sop.*` metadata (source, install hint, tags — `recipe.*` accepted as a deprecated alias) plus the process summary (name, version, step count + types, sha256). No writes; no curl. |

### Agent runtime skill paths

| Flavour | Scope | Canonical path |
|---|---|---|
| `claude` | project | `.claude/skills/opensop/SKILL.md` |
| `claude` | user | `~/.claude/skills/opensop/SKILL.md` |
| `codex` / `agentskills` | project | `.agents/skills/opensop/SKILL.md` (Agent Skills standard) |
| `codex` / `agentskills` | user | `~/.agents/skills/opensop/SKILL.md` |
| `hermes` | project | `.hermes/skills/opensop/SKILL.md` |
| `hermes` | user | `~/.hermes/skills/opensop/SKILL.md` |
| `openclaw` | project | `skills/opensop/SKILL.md` |
| `openclaw` | user | `~/.claw/skills/opensop/SKILL.md` |
| `openhands` | project | `.openhands/skills/opensop/SKILL.md` |
| `goose` | user | `~/.config/goose/skills/opensop/SKILL.md` |
| `cline`, `cursor`, `continue`, `aider` | — | Rules-only (no SKILL.md slot; see `opensop skill install --runtime cline`) |

## Demo

A reproducible ~55-second terminal recording of the `opensop bench` comparison
(skill vs json_only vs openSOP, 3 arms, Claude Haiku) lives at
[`bench/demo/`](bench/demo/). It replays outputs from the verified 60-run benchmark;
see [`bench/NUMBERS.md`](bench/NUMBERS.md) for full methodology and results.

```sh
# Re-render the GIF/MP4 from scratch (requires asciinema + agg + ffmpeg):
cd bench/demo && make demo

# Or just watch the pre-rendered GIF:
# bench/demo/comparison.gif
```

Headline: same model, same notes — naive prompt invents 3–5 phantom tasks on every
run; openSOP returns exactly the 3 real ones, byte-identical, ~2× faster.

## Local cache

The CLI caches `id → process name` mappings in `~/.opensop/instances.tsv` — a plain TSV of `id`, `name`, `created_at`, `url`. This is used by the remote backend so `opensop --remote status <id>` doesn't require re-typing the process name. Safe to delete at any time; the CLI rebuilds it from `/sop/instances` on the next cache miss.

## Authentication

The CLI sends `X-SOP-Token` on every request when the token is set. The OpenSOP server can run in two modes:

- **Token unset, dev/test environment** — server allows all requests (logs a warning)
- **Token set** — every non-webhook request must match; mismatch returns 401

In production the server **fails closed** (503 with `server_misconfigured`) when the token is unset, so `opensop list` against a misconfigured prod will return that error from the server, not a silent open API.

## Use with Claude Code (and other agents)

The CLI was designed so an agent can use OpenSOP without writing HTTP requests. See [`docs/AGENTS.md`](../docs/AGENTS.md) for the full agent guide — discovery, run lifecycle, building processes, the openSOP-ize pattern, and CLAUDE.md snippets.

The short version: when an agent recognizes that what it's about to do is a multi-step process, it runs it with `opensop run`, polls `opensop status`, and submits step outputs as it works. Local runs need no server; add `--remote` to involve the runtime's database.

For discovery, agents should use `opensop search` or `opensop suggest` rather than scanning the full `list` output — they surface the right process from intent, not from name recall.

**Adopt OpenSOP in your agent runtime** — install the embedded SKILL.md in one command:

```bash
opensop skill install --runtime claude   # Claude Code: .claude/skills/opensop/SKILL.md
opensop skill install --runtime codex    # Codex: .agents/skills/opensop/SKILL.md
opensop skill paths                      # see all supported runtimes and their paths
```

For runtimes without a SKILL.md slot (`cline`, `cursor`, `continue`, `aider`), add the AGENTS.md block from [`docs/AGENTS.md §11`](../docs/AGENTS.md#11-adopt-opensop-in-your-agent--agentsmd-block) to your rules file. Run `opensop doctor` to verify the installation.

**SOP library** — shareable `.sop.json` processes live at [github.com/opensop/sops](https://github.com/opensop/sops) (a small set of examples/fixtures also live in-repo at [`sops/`](../sops/)). Pull one with:

```bash
opensop pull opensop/daily-standup-notes       # download to ./daily-standup-notes.sop.json
opensop info ./daily-standup-notes.sop.json    # metadata: name, version, tags, source

# A pulled SOP is UNTRUSTED code — READ its run commands before running it:
jq '(.process.steps // .steps)[] | {id, type, run}' ./daily-standup-notes.sop.json

opensop dry-run ./daily-standup-notes.sop.json # THEN validate inputs + preview the flow (not command bodies)
opensop run ./daily-standup-notes.sop.json     # only after reading the steps and confirming
```

`opensop pull` and `opensop import` only write the file — they never execute it. A pulled SOP is untrusted code: **read its `run` commands directly** (`jq '(.process.steps // .steps)[] | {id,type,run}' <file>`) before running it. `opensop dry-run <file>` previews the step flow but does **not** print command bodies, so it is not a substitute for reading the steps.

## Limitations

- **Bash 4+** assumed. Default macOS bash is 3.2 — install a newer one (`brew install bash`) or run via `/usr/local/bin/bash`.
- **`register` may be admin-only.** Some OpenSOP deployments restrict `/sop/processes/register` to admin tokens. If you get a 401/403, check your token scope or use the dashboard.
- **No inbound webhook receiver.** The CLI doesn't run a server, so it can't receive webhook callbacks over the network. `webhook` steps in `callback` mode pause the run — resume manually with `opensop submit <run_id> <step-id>`. The OpenSOP server runtime handles live inbound callbacks at `/sop/webhooks/<callback_id>`.
- **`webhook` poll mode** is not yet implemented in the local backend (mirrors the server runtime's current state). The step exits non-zero with a clear message.
- **`llm` step type** requires `ANTHROPIC_API_KEY` and outbound HTTPS to `api.anthropic.com`. Local runs without network access cannot execute `llm` steps.
- **`judgment` and `notification` step types** are not yet implemented in the local backend; they will fail the run with a clear error. Use the server runtime for processes that rely on these types.

## Contributing

Issues and pull requests welcome. The whole CLI is one bash file (`bin/opensop`); read it top-to-bottom in 10 minutes.

If you find a `set -u` bug (very common in bash with empty arrays), open an issue — there are corners where `${array[@]}` triggers "unbound variable" if not guarded.

## License

MIT — see [LICENSE](LICENSE).
