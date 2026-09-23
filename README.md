<p align="center">
  <img src="docs/images/hero.png" alt="A person and a small robot walking together down a stone path toward the mountains and the rising sun." width="100%" />
</p>

# OpenSOP

> ### Make your agents reliable.

OpenSOP packages an agent's process as a **file in your repo** — same steps, same output contract, a receipt for every run. Version it, fork it, run it anywhere. One bash file, no server, no account.

**Docker did this for environments; OpenSOP does it for procedures.** Docker pins the bits — OpenSOP pins the **steps, the output schema, and the audit trail**. And when a step can't meet its contract, the run **stops and says so** instead of improvising.

```bash
# Install the CLI — one file, deps: bash 4+ and jq
curl -fsSL https://raw.githubusercontent.com/opensop/opensop/main/cli/bin/opensop \
  -o opensop && chmod +x opensop

# Turn a process you already run into an OpenSOP process — and see the difference
./opensop onboard
```

Read [MANIFESTO.md](./MANIFESTO.md) for the thesis. Spec: [SPEC.md](./SPEC.md) (v0.9.1).

---

## The three problems

You're building on agents. Three things are biting you:

1. **Reliability.** The demo worked. The 400th run gave a different answer, a different shape, or a confident lie. You can't put your name on output that changes every run.
2. **Portability.** The "skill" is trapped in a prompt and a specific setup. Move it and you rebuild everything. It isn't a file you can ship.
3. **Auditability.** An agent did something wrong in production and there's no trace of *which step*. No receipts, no way to prove what happened.

OpenSOP is the layer that fixes the *process*, so the model can stay creative where it needs to be.

| Problem | What OpenSOP does |
|---|---|
| **Reliability** | A process declares its steps; each declares what it requires and returns; outputs validate against a schema. When a step can't meet its contract, the runtime **stops** — it never asks the LLM to launder the gap. Prove the gain yourself with [`opensop bench`](#proof-run-it-yourself). |
| **Portability** | It's a **plain file in your repo.** Nothing to export, nothing to migrate — **git is the versioning.** Fork it, ship it in a commit; the lineage is recorded, not lost in a doc. Runs on the local CLI with no account; the server is optional. |
| **Auditability** | Every run writes **append-only receipts** (`manifest.json` / `audit.jsonl` / `context.json`) to your repo — not another dashboard. `opensop ps` and `opensop watch` show what's running, scheduled, and last-status, in your terminal. |

> OpenSOP fixes the *procedure*, the *output contract*, and the *audit trail* — not the laws of nondeterminism. An LLM step still calls a model; what changes is that its output must conform, the step stops if it can't, and every run leaves a receipt.

---

## Who it's for

**You sell agents.** Your customers don't churn because your agent is dumb — they churn because it's *unreliable*: it worked in the demo and drifted in production, and one day their ops lead pasted the wrong output into a shared channel. Ship processes that are reproducible and auditable, and that **stop instead of lying** when a step can't meet its contract. **Prove reliability before you ship: `opensop bench`.**

**You run an AI-transformation practice.** You take a client's messy skill and make it real. `opensop onboard` it, `opensop bench` it, and hand the client a **before/after reliability report** you can invoice against. What you leave behind is a **file the client owns** — a process in their repo that survives your handoff — not a prompt that rots after you're gone.

**You're a CTO / AI director already running agents.** It's 2am, an agent misfired in prod, and there's no trace of which step. OpenSOP **wraps what you already run** — it's a format + contract, not another orchestrator or dashboard to migrate to. Receipts land in your repo; `opensop onboard` an existing skill and bench it in ~10 minutes. One auditable file, checksum-verified install, no daemon.

---

## Why not LangGraph / n8n / a dashboard?

OpenSOP is a **format + a contract + receipts** — not an orchestrator, not a canvas, not a SaaS. It **wraps** what you already have.

| Tool | Decides | OpenSOP |
|---|---|---|
| LangGraph / CrewAI / AutoGen | *how an agent thinks* | defines *what a process is allowed to do* — typed steps, an output contract, receipts — around your agent |
| n8n / Zapier | *wiring between SaaS apps* | the contract for the process itself, versioned in your repo, run by your agents |
| Langfuse / a dashboard | *observing calls in their UI* | the receipt lives in your repo; `ps`/`watch` read it in your terminal |

- **"My agents already work."** Great — `opensop onboard` one and `opensop bench` it. If it's already reliable, you lose ten minutes; if it isn't, you found out before your customer did.
- **"curl-installed bash in my stack?"** It's one file you can read before you run it (that's the point), checksum-verified on install and upgrade, no daemon, no account. See [Install verification](./cli/README.md#install-verification--threat-model).
- **"Standard, or one repo?"** Pre-1.0, but the spec is open ([SPEC.md](./SPEC.md), Apache-2.0) and a `.sop.json` is a plain file. Worst case, you keep the file and drop the tool.

---

## Proof: run it yourself

`opensop bench` runs the same task three ways and scores it. Task: *extract the action items from a set of meeting notes.* Three arms, **n=10 runs each, on Claude Haiku and Sonnet**:

- **skill** — the naive prompt a person writes ("extract all action items… list what you found").
- **json-only** — the same ask, but demanding JSON with the schema in the prompt. Isolates *format* from *scope*.
- **openSOP** — the encoded process: JSON schema **+ an explicit scope rule** + field rules.

| Model | Arm | Recall (found the 3 real) | Valid JSON | **Exact & usable** | Phantom items | Median time |
|---|---|:---:|:---:|:---:|:---:|:---:|
| Haiku | skill | **3/3** | 0/10 | 0/10 | +4 | 2.69 s |
| Haiku | json-only | **3/3** | 10/10 | 0/10 | +4 | 2.51 s |
| Haiku | **openSOP** | **3/3** | **10/10** | **10/10** | **+0** | **1.56 s** |
| Sonnet | skill | **3/3** | 0/10 | 0/10 | +5 | 5.49 s |
| Sonnet | json-only | **3/3** | 10/10 | 0/10 | +3 | 3.85 s |
| Sonnet | **openSOP** | **3/3** | **10/10** | **10/10** | **+0** | **2.68 s** |

Read it honestly:

- **Recall is 3/3 in every arm.** The model is *not* the problem — it always finds the three real action items. This isn't a strawman where the naive prompt "can't read."
- **The failure is scope-creep.** Every naive run inflates the 3 real items into 6–8 by promoting informal commitments to "action items" — a *different set every run*.
- **`json-only` is the control that matters.** Asking for JSON gives 10/10 valid structure and **still 0/10 exact** — it keeps inventing 3–5 phantom items. **Format alone doesn't buy reliability.** Only the encoded scope rule does.
- **openSOP: 10/10 exact, zero phantoms, ~2× faster**, and its schema-constrained output was **byte-identical across all 10 runs in this benchmark** (a measured result on this task — not a promise that every LLM step is deterministic).

Same model. Same notes. **Reliability 0 → 10/10.**

<details>
<summary>One naive run vs. one openSOP run (real outputs)</summary>

**skill (naive) — prose, 6 items, a different set next run:**
```
Action Items
1. Bob Navarro — Fix the CSV export race condition before 2026-08-12.
2. Carol Singh — Complete the WCAG 2.1 AA accessibility audit by 2026-08-15.
3. Dave Wu — Write integration tests for payments-flow edge cases by 2026-08-14.
4. Bob Navarro — File a planning ticket for the data-grid upgrade sprint.
5. Alice Chen — Follow up with customers on the batch-import escalations.
6. Alice Chen — Raise staging reliability as a P1 in the infra backlog.
```

**openSOP — exactly the three, structured, identical every run:**
```json
{"action_items":[
  {"owner":"Bob Navarro","task":"Fix the CSV export race condition"},
  {"owner":"Carol Singh","task":"Complete the WCAG 2.1 AA accessibility audit"},
  {"owner":"Dave Wu","task":"Write integration tests for payments-flow edge cases"}]}
```
</details>

Run it on your machine — `opensop bench` (add `ANTHROPIC_API_KEY` for a live run, or `--stub` offline). Full numbers + the reproducible video are in [`cli/bench/`](./cli/bench/). *(n=10 is a demo sample, not a statistical claim — the point is the shape.)*

---

## A process is a file

One model, two serializations (SPEC v0.9.1):

- **`.sop.json`** — the canonical format the local CLI runs (`opensop run`).
- **`.sop.yaml`** — the wrapped variant a server accepts at `POST /sop/processes/register`.

```yaml
opensop: "0.9.1"
process:
  name: morning-briefing
  version: "1.0"
  inputs:
    - { name: date, type: string, format: date, required: true }
  steps:
    - id: fetch-calendar
      type: automated
      run: ./scripts/fetch-calendar.sh
      outputs:
        - { name: success, type: boolean }
        - { name: events, type: object }

    - id: synthesize
      type: llm
      model: claude-haiku-4-5
      # The gate that makes "the agent can't launder missing data" mechanical:
      # if the fetch returned success:false, the LLM is never asked.
      condition: "steps.fetch-calendar.outputs.success == true"
      expected_output_schema: { brief: string }
      prompt: "Synthesize a 200-word brief from these sources…"
      outputs:
        - { name: brief, type: string }
```

If Calendar times out, the run stops at the gate. It does **not** hand the LLM a blank calendar and let it say *"your schedule looks clear this morning."* You get back exactly what was collected — with a receipt.

---

## The CLI is the product

`cli/bin/opensop` is a single bash file — no build step, no package manager, no compiled artifact. The file *is* the binary. Local execution is the default; the server is opt-in.

```bash
opensop onboard                       # scaffold a process, validate it, and bench it
opensop run ./greet.sop.json --input name=Ana   # run locally — no server, no account
opensop bench                         # 3-arm reliability comparison (skill / json-only / openSOP)
opensop ps                            # every process: open / scheduled / running · last status
opensop watch                         # the same, live in your terminal (--remote for a server)
opensop heal <run_id>                 # a failed step → an agent-actionable fix prompt
opensop show <run_id>                 # the receipts for a run
opensop search "qualify a lead"       # find an existing process before writing a new one
opensop upgrade                       # verified, atomic self-update
```

Every run writes append-only receipts under `$OPENSOP_LOCAL_HOME/runs/<id>/`. Full command reference: [`cli/README.md`](./cli/README.md). Agent-facing guide: [`docs/AGENTS.md`](./docs/AGENTS.md).

---

## The step types

| Step | What it does | Local execution |
|---|---|---|
| `automated` / `shell` | Run a script in any language | Full |
| `noop` | Pass context through | Full |
| `form` | Collect data from a human or agent | Pauses; resume with `submit` |
| `approval` | A human must approve or reject | Pauses; resume with `submit` |
| `wait` | Pause on a timer or condition | `seconds` immediate; `until` pauses |
| `llm` | LLM call with a prompt + `expected_output_schema` | Full (`ANTHROPIC_API_KEY`) |
| `webhook` | Outbound HTTP (sync or callback) | Sync full; callback pauses |
| `subprocess` | Start another process | Full (depth-guarded) |
| `loop` / `judgment` / `notification` | Iterate / LLM-or-human decision / send | Server-side |

Full grammar and the `/sop/*` API contract: [`SPEC.md`](./SPEC.md).

---

## The optional server

The CLI runs everything locally with no server. When you want shared orchestration, a team audit log, or a monitoring API, point the CLI at any server that implements the [`SPEC.md`](./SPEC.md) `/sop/*` contract — including per-process status at `GET /sop/processes/status`, which backs `opensop ps --remote` / `opensop watch --remote`.

There is no maintained reference server. The profile is specified so anyone can build one; the CLI is the reference implementation of the local profile, and `opensop run` never requires a server.

---

## Used internally at Coba

[Coba](https://coba.ai) runs internal operations and scheduled engineering agents on OpenSOP; improvements flow upstream first. Specialized agents review PRs, bump dependencies, resolve conflicts, re-run CI, and handle the chores humans defer — each as a typed `.sop` process with named steps, bounded I/O, structured prompts, size caps, git-diff checks, and append-only receipts. The agents do the creative work. OpenSOP provides the rails.

---

## Documentation

| Doc | For | Covers |
|---|---|---|
| [`MANIFESTO.md`](./MANIFESTO.md) | Everyone | The thesis — why processes are infrastructure |
| [`SPEC.md`](./SPEC.md) | Architects + implementors | The OpenSOP v0.9.1 spec and `/sop/*` API contract |
| [`docs/AGENTS.md`](./docs/AGENTS.md) | Agent builders | Discover → run → build → openSOP-ize → evolve |
| [`EVOLUTION.md`](./EVOLUTION.md) | Process authors | Mineralization tiers — hardening a process over time |
| [`cli/README.md`](./cli/README.md) | CLI users | Full command reference + install verification |

---

## License

Apache 2.0. See [`LICENSE`](./LICENSE).

**Turn a process you run into one that runs the same way every time — `opensop onboard`.** If OpenSOP is useful, [star the repo](https://github.com/opensop/opensop) — it tells us the standard is worth hardening.
