# OpenSOP SOP Examples

A small set of reusable, shareable `.sop.json` process files kept in this repo as **examples and test fixtures** for the CLI's `pull`/`import`/`dry-run` paths.

**The canonical public SOP library lives at [github.com/opensop/sops](https://github.com/opensop/sops).** `opensop pull` fetches from that repo by default. The SOPs here have not been through the library's publishing bar (10 verified runs) and are not mirrored there — treat them as local examples, not the library.

## Layout

```
sops/<author>/<slug>/<slug>.sop.json
```

- **`author`** — a GitHub username or organisation name (namespace). `opensop` is reserved for officially maintained SOPs.
- **`slug`** — a short kebab-case name that uniquely identifies the SOP within the author namespace. Each SOP lives in its own `<slug>/` folder (room to grow beyond a single file — assets, fixtures, etc.).

Example: `sops/opensop/daily-standup-notes/daily-standup-notes.sop.json`

## How to pull an SOP

```bash
# Pull the latest version (from main) — fetches from github.com/opensop/sops
opensop pull opensop/daily-standup-notes

# Pull and pin to an immutable commit SHA for reproducibility
opensop pull opensop/daily-standup-notes@a1b2c3d

# Write to a specific path instead of the default ./<slug>.sop.json
opensop pull opensop/daily-standup-notes --output ~/processes/standup.sop.json

# Verify the file matches a known SHA-256 (supply the hash out-of-band)
opensop pull opensop/daily-standup-notes --verify <sha256-hex>
```

The CLI writes the file and prints a summary (name, version, step count, step types, source, SHA-256). It never executes the file automatically. **Read its `run` commands before running** — dry-run previews the step flow only, not the command bodies:

```bash
jq '(.process.steps // .steps)[] | {id, type, run}' ./daily-standup-notes.sop.json
```

## How to import from a local file or stdin

```bash
# Import from a file
opensop import ./my-sop.sop.json

# Import from stdin (e.g. after piping curl output)
curl -fsSL <url> | opensop import -
```

`import` validates, writes, and prints a summary — same as `pull`, same safety contract. Never auto-runs.

## Safety note

**An SOP's shell/automated steps execute arbitrary commands on your machine** — the same trust boundary as a `Makefile` or `npm postinstall`. Before running an SOP, **read its `run` commands directly** — they are plain JSON:

```bash
jq '(.process.steps // .steps)[] | {id, type, run}' <file>   # or just open the file
```

**Approval steps are unauthenticated locally.** OpenSOP's local runtime does not verify *who* submits an approval/decision — the actor is whoever runs the process (same trust boundary as a `Makefile`). SOPs that record an approver identity (e.g. a reviewer) label it *self-reported*; do not treat a locally-produced approval record as an authenticated attestation.

`opensop dry-run <file>` validates inputs and previews the step *flow*, but it does **not** print command bodies — so it is not a substitute for reading the steps above.

The `sha256` printed after every pull is for pinning and identification (both the file and the hash come from the same GitHub origin — they confirm transfer integrity and help you reproduce exact versions, not authenticate against a third party). Supply `--verify <sha256>` to enforce a hash you obtained out-of-band.

## Example SOPs in this repo (`opensop/`)

| Slug | Description |
|---|---|
| `daily-standup-notes` | Collect standup answers (yesterday / today / blockers) and format a concise summary |
| `triage-bug-report` | Triage a bug report with an LLM: assign a P0–P3 priority + rationale, then format a triage summary (input-driven) |
| `release-checklist` | Approval-gated release checklist: confirm each item before marking the release ready |
| `lead-qualification` | Score and route a sales lead with an LLM (qualified/nurture + rationale), then format a qualification summary |
| `meeting-action-items` | Paste meeting notes, extract structured action items with an LLM step, then format the list |
| `incident-postmortem` | Collect incident details, gate on sign-off approval, then emit a postmortem Markdown doc |
| `pr-review-gate` | Collect PR details, gate on reviewer approval or rejection, then emit a formal review record |
| `customer-onboarding` | Collect customer details, gate on kickoff go/no-go, then emit an onboarding checklist |
| `content-publish-approval` | Collect draft content details, gate on editorial approval, then emit a publish record |
| `weekly-status-digest` | Collect weekly wins, risks, and next steps via form, then format a Markdown status digest |
| `email-spam-filter` | ADVISORY LLM spam triage: classify (spam/ham + confidence) and recommend deliver vs quarantine — delivery only for high-confidence ham; injection-aware (advisory; LLM classifiers are susceptible to crafted-email prompt injection); not an authenticated gate |
| `scoped-change-delegation` | Collect a scoped code-change task, gate delegating it to a worker agent on planner approval, then emit a delegation record — exercises SPEC 0.9.1 §2.9's agent-work fields (`evidence`, `agent_contract`, `prompt`, `isolation`) |

These exist as CLI test fixtures and `opensop dry-run`/`opensop import` examples. They are not published to the `opensop/sops` library.

## How to contribute to the public library

The SOP library that `opensop pull` fetches from is a separate repo: **[github.com/opensop/sops](https://github.com/opensop/sops)**. Contribute there, not here:

1. Fork that repo and create your SOP under `<your-github-username>/<slug>/<slug>.sop.json`.
2. Each SOP must be a valid `.sop.json` that passes `opensop dry-run`.
3. Include the `sop` object (`recipe` is accepted as a deprecated alias) with `source`, `install`, and at least one tag.
4. Use only safe, synthetic examples — no PII, no secrets, no destructive commands.
5. Open a pull request. The title should be `feat(sops): add <author>/<slug>`.

SOPs that contain destructive shell commands, network calls to untrusted endpoints, or secrets will be rejected. New SOPs go through a publishing bar (verified runs) before being listed as official — see the `opensop/sops` repo for the current process.
