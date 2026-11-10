# OpenSOP CLI

A bash CLI that runs OpenSOP processes on your machine. One file; `bash` 4+ and `jq` are all it needs. It can also talk to an optional OpenSOP server.

## Why

OpenSOP is an open standard for processes as files: each step is either a script that must come out the same every time or a model call that needs judgment, and every step leaves a receipt. This CLI runs those `.sop.json` files locally (no server, no daemon, no account) so agents and people can drive them from any terminal.

```bash
opensop run ./greet.sop.json --input name=Ana        # run a file
opensop run greet --input name=Ana                   # inside a cell: look the process up by name
opensop runs                                         # list local runs
opensop show <run_id>                                # a run's manifest + per-step receipts
```

Local is the default. `--remote` / `--server <url>` route commands to an optional server instead; see [Optional server](#optional-server---remote).

**Process format:** `.sop.json` (jq-native), mirroring `SPEC.md` v0.9.1. **Step I/O contract:** each step gets the accumulated context (inputs + prior outputs) on stdin and in `$OSL_CONTEXT` (left unset past Linux's 128 KiB env-string cap; stdin always has it); its JSON stdout merges back under the step id. **Step types (local):**

| Type | Pause? | Resume trigger | Notes |
|---|---|---|---|
| `automated` / `shell` | No | — | Runs a shell script; JSON stdout merged into context |
| `noop` | No | — | Pass-through; no execution |
| `form` | Yes — `waiting_for_input` | `submit --output k=v` | Collects structured human/agent input |
| `approval` | Yes — `waiting_for_approval` | `submit --output decision=approve\|reject` | Defaults to `decision` enum; fully configurable |
| `wait` | `wait.seconds` → No; `wait.until` → Yes — `waiting_for_callback` | `submit` (no outputs required) | `wait.seconds` completes immediately with `{waited:true}` |
| `llm` | No | — | `claude*` → Anthropic API (`ANTHROPIC_API_KEY`). CLI providers: `claude-code:<model>`, `codex:<model>`, `cursor:<model>`, `kimi:<model>` (empty model = the CLI's default), with `workdir` and `permission` (`read-only` default \| `workspace-write` \| `full-access`; refused where the CLI cannot enforce it — kimi is `full-access` only) and an optional `timeout` per CLI attempt. `workdir` defaults to where the run was started. `model`, `permission` and `workdir` are `{{ var }}`-templated (the rendered `permission` is still vocabulary-checked) |
| `judgment` | Yes — `escalated` | `submit --output decision=...` | With `judgment.allow_agent` + `model` + `prompt`, runs the `llm` path against the step's outputs + `confidence`; escalates on `require_human_review` or confidence below `confidence_threshold`. No agent → escalates at once |
| `loop` | No | — | `for_each` (+`as`) / `repeat_until` / `while` over `body` steps; `max_iterations` (default 100); `aggregate` sum\|concat\|last. A pausing body step fails the loop |
| `webhook` | sync → No; callback → Yes — `waiting_for_callback` | `submit --output k=v` | sync asserts 2xx; poll mode not yet implemented |
| `subprocess` | Propagates child pause | child resume | Recursive local execution; depth-guarded (max 16) |
| `notification` | — | — | Not implemented locally yet; fails the run with a clear error |

**Try it with coding agents:** [`examples/agent-loops/`](examples/agent-loops/) has two ready-to-run loops (`planner-worker`, `dev-loop`) that drive local `claude` / `codex` / `cursor-agent` / `kimi` CLIs against a git checkout, using `llm`, `loop` and a test-command gate.

**Pause/resume lifecycle:** when a step pauses the run, `manifest.status` becomes `waiting` and `manifest.waiting` records the step, reason, and what outputs are expected. Resume with:

```bash
opensop submit <run_id> <step-id> --output key=value
```

Execution re-enters at `cursor.next_index` — never re-runs completed steps.

**Step executor (v0.6):** each step may declare `executor: internal|external`. `external` = work happens in an outside process (script, webhook), OpenSOP orchestrates and receives the receipt; `internal` = the OpenSOP runtime handles the step itself. Optional; defaults apply per step type (`automated`/`shell`/`webhook` → external, `noop`/`form`/`approval`/`notification`/`wait`/`judgment` → internal). Invalid values fail loudly at parse time. The effective executor is recorded in each step's audit receipt.

**Step effects (v0.7.x):** each step may declare `effects: "<plain-string description>"` (e.g. `"publishes a post to LinkedIn"`) to mark it as irreversible — it acts on the world, not just on the run's data. The presence of the field is the signal; there is no enum or boolean form. `opensop heal --apply` refuses to re-run a step that declares `effects` (see the `heal` row above) because it may have already succeeded remotely before the CLI observed the failure.

**Receipts:** `$OPENSOP_LOCAL_HOME/runs/<id>/{manifest.json, audit.jsonl, context.json}`. As of v0.6: when cwd is inside an OpenSOP cell, `$OPENSOP_LOCAL_HOME` defaults to the active cell's `.opensop/` (receipts land alongside the processes that produced them); outside any cell it defaults to `~/.opensop-local`. Explicit env override always wins. **Name resolution (v0.6):** inside a cell, `opensop run <name>` looks up `processes/<name>.sop.json` in the active cell, then each ancestor cell (nearest wins). Explicit file paths still work as before. The same process file is meant to run locally *and* on any conforming server — portability is the point.

> **⚠ Trust boundary:** local steps execute as shell **on your machine** — a `.sop.json`'s `shell`/`automated` steps run arbitrary commands. Only run process files you trust (same posture as a `Makefile` or an npm `postinstall`). This matters most for agents: don't `opensop run` a process file you just fetched from an untrusted source.
>
> **Note on `--local`:** accepted for backwards compatibility but a deprecated no-op (local has been the default since v0.8). Drop it from scripts; it prints a deprecation note on stderr.

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
curl -fsSL .../install.sh | bash -s -- --version 0.10.0

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
opensop upgrade --pin 0.10.0 # specific version
```

### Requirements

- `bash` 4+ (Linux default; macOS needs `brew install bash` — see above)
- `jq` — `brew install jq` / `apt install jq` / `dnf install jq`
- `curl` — needed by `install.sh`, `opensop upgrade`, `opensop pull`, `webhook` steps, `claude-*` `llm` steps, and the remote backend; other local execution does not need it

## Install verification & threat model

**What checksum verification does — and doesn't — protect against.** The installer and `opensop upgrade` fetch a companion `.sha256` file and refuse to replace your binary unless the download's SHA-256 matches (opt out with `--allow-unverified`). This protects against *corruption in transit*: truncated downloads, CDN/proxy mangling, and partial caches. It does **not** protect against a compromised source: the binary and its checksum are served from the same GitHub origin, so an attacker who can modify this repository or its CDN path can replace both consistently. There are no cryptographic signatures on releases today, and we won't pretend a checksum is one. Your actual trust anchor when running `curl … | bash` is TLS to `raw.githubusercontent.com` plus the integrity of this repository and its maintainer's GitHub account. If that trust model is insufficient for your environment, be precise about what each mitigation buys you:

- **Reproducibility, not authenticity** (these help you pin and re-verify a *known* revision, but do **not** defend against a compromised account — the git history, tags, and GitHub Release notes are all controlled through the same repository/account, so an attacker with that access can rewrite them consistently): install from a specific tag with `--pin X.Y.Z`, and record the digest you trusted so upgrades are diffable.
- **Independent verification** (the only measures that actually escape the same-origin/same-account boundary): read `install.sh` and `bin/opensop` yourself before running them (they're plain bash — that's the point), or vendor the file into a repository *you* control and diff every upgrade against your own trusted copy. Compare the digest against a copy you obtained through a channel you trust independently of this account, not against artifacts served from it.

There is no cryptographic authenticity check available today — if that is a hard requirement for you, treat this install as unverified until you have vendored and reviewed it. We may add Sigstore-based release signing later if the project gains CI; we'd rather ship no signature than an unverified one.

## Quick start

Drop a process file and run it — no config required:

```bash
# Write a minimal process
cat > greet.sop.json <<'JSON'
{ "name": "greet", "inputs": [{"name":"name","type":"string","required":true}],
  "steps": [{ "id": "say", "type": "shell",
              "run": "jq '{greeting: (\"hello, \" + .name)}'" }] }
JSON

opensop run ./greet.sop.json --input name=Ana
opensop runs               # list all local runs
opensop show <run_id>      # receipts + audit log
```

Each step reads the run context (inputs plus earlier outputs) as JSON on stdin; its JSON stdout lands in the context under the step id (`say.greeting` here).

Inside an OpenSOP cell (`opensop init`), bare process names resolve automatically:

```bash
opensop run greet --input name=Ana   # looks up processes/greet.sop.json in the cell chain
```

A paused run (a `form`, `approval`, or escalated `judgment`) waits for `opensop submit`. `opensop status <run_id>` shows what it is waiting on and prints the command to continue; `opensop status <run_id> --json` carries the same as `waiting` (with the step's `description`), `run_dir`, and on failure `error: {step, exit_code, message}`.

## Output modes

By default the CLI is **TTY-aware**: pretty-printed in a terminal, JSON when piped.

```bash
opensop list                    # pretty in terminal, JSON when piped
opensop list --json             # always JSON
opensop list --pretty           # force the human form when piped (some commands, e.g. status, print indented JSON)
opensop status <id> | jq ...    # piping → JSON automatically
```

When `--json` is set, **errors also emit JSON to stderr**: server errors round-trip via `{error, message, ...}` from the engine (augmented with `_meta.http_status`); CLI-side errors (config missing, file not found, invalid input, unknown command, etc.) emit `{error, message, hint?}` from the same envelope. Agents can parse stderr the same way they parse stdout.

```bash
$ opensop --json schema validate /nonexistent.yaml 2>&1 1>/dev/null
{"error":"file_not_found","message":"file does not exist: /nonexistent.yaml"}
```

Set `NO_COLOR=1` to disable ANSI color.

**`OPENSOP_SOPS_BASE`** overrides the base URL used by `opensop pull` (default: this repo's [`sops/`](../sops/) directory on GitHub). Set it to a `file://` URL pointing at a local directory with the same `<ref>/<author>/<slug>/<slug>.sop.json` layout for offline testing or air-gapped environments. `OPENSOP_RECIPES_BASE` is a deprecated alias — honoured (with a stderr deprecation warning) only when `OPENSOP_SOPS_BASE` is unset.

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
opensop run ./my-process.sop.json \
  --input lead_name=Ana \
  --metadata source_system=crm \
  --metadata external_id=lead_8821
```

## Process authoring

A process is a `.sop.json` file. The loop is: write it, `dry-run` it, run it, read the receipts.

```bash
opensop dry-run my-process.sop.json --input foo=bar    # validate inputs + preview the steps, no run
opensop run my-process.sop.json --input foo=bar
opensop show <run_id>
```

`dry-run` exits 1 if validation fails. To have an agent write processes for you, install the authoring skill: `opensop skill install --runtime claude --skill opensop-build-harness`.

For the wrapped `.sop.yaml` form a server accepts, `opensop schema validate ./my-process.sop.yaml` is a client-side lint (needs `yq` v4+ or `python3` + PyYAML): it checks the `opensop` version field, the `process` object, each step's `id` and `type`, each input's `name` and `type`, and that `from:` references look like `steps.X.outputs.Y` or `process.inputs.Y`. `opensop --server <url> register ./my-process.sop.yaml` POSTs it to a server (below).

## Optional server (`--remote`)

Everything above runs locally. To share runs with a team, point the CLI at any server that implements the [`SPEC.md`](../SPEC.md) `/sop/*` contract. There is no maintained reference server.

```bash
opensop config set url https://sop.example.com          # saved to ~/.opensop/config (or $OPENSOP_HOME/config)
opensop config set token <your-token>                   # sent as X-SOP-Token
opensop --remote run my-process --input k=v             # dual commands take --remote
opensop --server http://localhost:3000 list             # or a one-call server override
```

`OPENSOP_URL` / `OPENSOP_TOKEN` override the config per call, but `OPENSOP_URL` alone does not enable remote mode. `register` and `schema <name>` are remote-only; `runs` and `show` are always local. For remote runs the CLI caches `id → process name` in `~/.opensop/instances.tsv` (safe to delete) so later commands take just the run ID. Server errors (HTTP ≥ 400) come back verbatim plus `_meta.http_status`.

## Subcommand reference

Commands marked **[remote]** require `--remote` or `--server <url>`. All others default to local.

| Command | Purpose |
|---|---|
| **Discovery** | |
| `opensop list [dir]` | List processes in the cell chain (local) or from the server (**[remote]** with `--remote`) |
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
| `opensop cancel <run_id> [--reason TEXT]` | Cancel a running, waiting or interrupted local run (or **[remote]** with `--remote`) |
| `opensop runs` | List all local runs |
| `opensop show <run_id>` | Local run manifest + per-step receipts |
| `opensop heal <run_id> [--apply] [--force-effects] [--input k=v ...]` | Diagnose a failed run (print fault + debug_prompt); `--apply` re-runs the failed step and continues from there (closed heal loop). On an `interrupted` run (the CLI was killed mid-step) `--apply` re-runs the step it was on. Fault records may contain input data — local only, never committed (SPEC §11.4). If the failed step declares `effects` (SPEC §3.2 — it acts on the world, e.g. "publishes a post to LinkedIn"), `--apply` refuses and exits non-zero: the step may have already succeeded before the observed failure, so a blind retry can double-post/double-send/double-spend. Pass `--force-effects` to re-run it anyway. |
| **Authoring** | |
| `opensop register <process.yaml>` | **[remote]** POST a `.sop.yaml` to `/sop/processes/register` — requires `--remote` or `--server` |
| `opensop schema validate <file.yaml>` | Client-side YAML lint — always local, no server round-trip |
| **Cells (v0.6)** | |
| `opensop init [--name N] [--parent PATH]` | Create `.opensop/` in cwd; cwd becomes the active cell. Auto-detects parent from ancestor cell when present. Writes `.opensop/.gitignore` with `runs/` so run receipts stay out of git. |
| `opensop scope` | Print the active cell + ancestor chain (nearest-first); errors if cwd is not inside a cell |
| `opensop annotate <skill> <event-type> <json>` | Append a policy event to the skill's lineage history in the active cell. Event type is open-string; data is whatever JSON the policy needs. |
| `opensop lineage <skill>` | Print a skill's lineage entry (status, metadata, history) in the active cell. Returns the empty default if no events have been recorded yet. |
| `opensop fork <name> [--from <cell>]` | Materialize an ancestor cell's skill in the active cell. Copies `processes/<name>.sop.json` over, then records a lineage entry with `forked_from = {cell, forked_at, snapshot}` where `snapshot` captures the parent's `status` and `metadata`. Child's live status + metadata start empty (policy decides what to do with the snapshot). Refuses to overwrite an existing skill. |
| `opensop list --conflicts` | Inside a cell, walk the chain and **mark shadowed entries**. The first occurrence of each filename (nearest cell that has it) is tagged `← active`; subsequent occurrences in ancestors are tagged `← shadowed by [cell-name]`. |
| **Admin** | |
| `opensop instances [--state X] [--process Y]` | List runs — local by default; **[remote]** paginated `GET /sop/instances` with `--remote` |
| **Config** | |
| `opensop config [set <key> <value>]` | Manage remote server config (url + token) |
| `opensop upgrade [--pin X.Y.Z]` | Verified, atomic self-update to the latest (or a pinned) release |
| `opensop help [<command>\|agents] [--json]` | Full help, per-command detail, agent quick-start, or machine-readable JSON index |
| **Bench** | |
| `opensop bench [<task-dir>] [--n N] [--model MODEL] [--arm ARMNAME] [--stub]` | Run from a git clone of this repo: 3-arm reliability comparison (skill vs json_only vs opensop) over N runs on the task in [`bench/`](bench/). `--stub` runs offline (no API key). |
| **Onboarding** | |
| `opensop onboard [<process.sop.json>]` | First-run experience: scaffold a starter `.sop.json` if none given, validate it via dry-run, and print next steps. Never executes your process. |
| **Agent Skills** | |
| `opensop skill show [--skill NAME]` | Print an embedded SKILL.md to stdout — no file written. Lets an agent read the skill content without installing it. |
| `opensop skill install <dir> [--force]` | Write the embedded SKILL.md to `<dir>/opensop/SKILL.md` (creates dirs as needed). Requires `--force` to overwrite an existing file. |
| `opensop skill install ... --skill opensop-build-harness` | Install the process-authoring skill (`opensop-build-harness`) instead of the default `opensop` skill. Works with `<dir>` or `--runtime`. |
| `opensop skill install --runtime <flavour> [--scope user\|project] [--force]` | Install the SKILL.md at the canonical path for the given agent runtime (see table below). Rules-only runtimes (`cline`, `cursor`, `continue`, `aider`) print guidance instead (exit 0, no file written). Unknown flavour → `usage_error` listing valid names. |
| `opensop skill paths [--json]` | Print the flavour→path registry as a TTY table or JSON object. This is the authoritative reference for where each runtime expects the skill file. |
| `opensop doctor [--json]` | Self-check: opensop version + PATH, jq present, bash ≥4, per-runtime skill installation status. Exits non-zero only on CRITICAL failure (jq missing, bash too old). Missing skills are informational. |
| **SOPs** | |
| `opensop pull <author>/<slug>[@<ref>]` | Download an SOP from this repo's [`sops/`](../sops/) directory (`<author>/<slug>/<slug>.sop.json`). Defaults to `main`; pin with a commit SHA: `opensop pull opensop/release-checklist@a1b2c3d`. `--output <path>` overrides the default `./<slug>.sop.json`. No-clobber without `--force`. Prints a summary (name, version, step count + types, source, sha256) and a "review before running" note. **Never executes the file.** `--verify <sha256>` enforces a hash the user supplies out-of-band. Requires curl. |
| `opensop import [<file>\|-] [--output <path>] [--force]` | Read an SOP from a local file or stdin (`-`), validate it as a process, write to `./<name>.sop.json` or `--output <path>`, no-clobber without `--force`. Prints the same summary; **never executes the file.** Local-only (no curl). |
| `opensop info <file.sop.json>` | Print an SOP's `sop.*` metadata (source, install hint, tags — `recipe.*` accepted as a deprecated alias) plus the process summary (name, version, step count + types, sha256). No writes; no curl. |

### Agent runtime skill paths

| Flavour | Scope | Canonical path |
|---|---|---|
| `claude` | project | `.claude/skills/opensop/SKILL.md` |
| `claude` | user | `~/.claude/skills/opensop/SKILL.md` |
| `codex` / `agentskills` | project | `.agents/skills/opensop/SKILL.md` (Agent Skills standard) |
| `codex` | user | `$CODEX_HOME/skills/opensop/SKILL.md` (`~/.codex/skills` when unset) |
| `agentskills` | user | `~/.agents/skills/opensop/SKILL.md` |
| `hermes` | project | `.hermes/skills/opensop/SKILL.md` |
| `hermes` | user | `$HERMES_HOME/skills/opensop/SKILL.md` (`~/.hermes/skills` when unset) |
| `openclaw` | project | `skills/opensop/SKILL.md` |
| `openclaw` | user | `~/.claw/skills/opensop/SKILL.md` |
| `openhands` | project | `.openhands/skills/opensop/SKILL.md` |
| `goose` | user | `~/.config/goose/skills/opensop/SKILL.md` |
| `cline`, `cursor`, `continue`, `aider` | — | Rules-only (no SKILL.md slot; see `opensop skill install --runtime cline`) |

## Bench (from a clone)

`opensop bench`, run from a git clone of this repo, compares three ways of doing one task (a naive prompt, JSON-only, and an OpenSOP process). The task, fixtures, methodology and a reproducible terminal recording live in [`bench/`](bench/) — see [`bench/NUMBERS.md`](bench/NUMBERS.md) and [`bench/demo/`](bench/demo/).

## Use with Claude Code (and other agents)

The CLI was designed so an agent can use OpenSOP without writing HTTP requests. See [`docs/AGENTS.md`](../docs/AGENTS.md) for the full agent guide — discovery, run lifecycle, building processes, the openSOP-ize pattern, and CLAUDE.md snippets.

The short version: when an agent recognizes that what it's about to do is a multi-step process, it runs it with `opensop run`, polls `opensop status --json` (read `.state`), and submits step outputs as it works. Local runs need no server.

For discovery, agents should use `opensop search` or `opensop suggest` rather than scanning the full `list` output — they surface the right process from intent, not from name recall.

**Adopt OpenSOP in your agent runtime** — install the embedded SKILL.md in one command:

```bash
opensop skill install --runtime claude   # Claude Code: .claude/skills/opensop/SKILL.md
opensop skill install --runtime codex    # Codex: .agents/skills/opensop/SKILL.md
opensop skill install --runtime hermes   # Hermes Agent: .hermes/skills/opensop/SKILL.md
opensop skill paths                      # see all supported runtimes and their paths
```

For runtimes without a SKILL.md slot (`cline`, `cursor`, `continue`, `aider`), add the AGENTS.md block from [`docs/AGENTS.md §11`](../docs/AGENTS.md#11-adopt-opensop-in-your-agent--agentsmd-block) to your rules file. Run `opensop doctor` to verify the installation.

**Example SOPs** — shareable `.sop.json` processes live in this repo's [`sops/`](../sops/) directory, which is where `opensop pull` fetches from. Pull one with:

```bash
opensop pull opensop/release-checklist         # download to ./release-checklist.sop.json
opensop info ./release-checklist.sop.json      # metadata: name, version, tags, source

# A pulled SOP is UNTRUSTED code — READ its run commands before running it:
jq '(.process.steps // .steps)[] | {id, type, run}' ./release-checklist.sop.json

opensop dry-run ./release-checklist.sop.json   # THEN validate inputs + preview the flow (not command bodies)
opensop run ./release-checklist.sop.json       # only after reading the steps and confirming
```

`opensop pull` and `opensop import` only write the file — they never execute it. A pulled SOP is untrusted code: **read its `run` commands directly** (`jq '(.process.steps // .steps)[] | {id,type,run}' <file>`) before running it. `opensop dry-run <file>` previews the step flow but does **not** print command bodies, so it is not a substitute for reading the steps.

## Limitations

- **Bash 4+** assumed. Default macOS bash is 3.2 — install a newer one (`brew install bash`) or run via `/usr/local/bin/bash`.
- **`register` may be admin-only** on a given server. A 401/403 means the token lacks that scope.
- **No inbound webhook receiver.** The CLI doesn't run a server, so it can't receive webhook callbacks over the network. `webhook` steps in `callback` mode pause the run — resume manually with `opensop submit <run_id> <step-id>`. A server implementing SPEC §4 receives live callbacks at `/sop/webhooks/<callback_id>`.
- **`webhook` poll mode** is not yet implemented in the local backend. The step exits non-zero with a clear message.
- **`llm` step type** with a `claude*` model requires `ANTHROPIC_API_KEY` and outbound HTTPS to `api.anthropic.com`; CLI providers need that CLI installed and signed in. A CLI-provider prompt goes on stdin, except kimi's (`-p <prompt>`, capped at 128 KiB on Linux). Without a step `timeout`, CLI calls are unbounded.
- **`loop` bodies cannot pause.** A `form`, `approval`, escalated `judgment`, or other pausing step inside a loop body fails the loop step.
- **`notification` step type** is not yet implemented in the local backend; it fails the run with a clear error.

## Contributing

Issues and pull requests welcome. The whole CLI is one bash file (`bin/opensop`); read it top-to-bottom in 10 minutes.

If you find a `set -u` bug (very common in bash with empty arrays), open an issue — there are corners where `${array[@]}` triggers "unbound variable" if not guarded.

## License

MIT — see [LICENSE](LICENSE).
