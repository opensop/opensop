# OpenSOP — Specification v0.7

**Date:** 2026-08-05
**Authors:** Chosen9115 + Claude (digital twin)
**Status:** Current — authoritative cross-repo contract
**Domain:** opensop.ai
**License:** Apache 2.0

> This document supersedes SPEC.md v0.6.
> All content from prior versions has been folded in and reconciled against the
> running code. Where the prior documents said one thing and the code does
> another, the code governs — discrepancies are noted inline.
>
> **v0.7 adds:** process status model (§9), reliability metrics contract (§10),
> and a security model (§11). The `/sop/*` HTTP API contract is unchanged.
> Stream protocol, self-heal semantics, and scheduler-trigger promotion are
> reserved for v0.7.x — they land with their respective implementations (A2, D2, A3).

**This is the OpenSOP specification.** It defines the process definition format,
step-type semantics, local execution backend, and HTTP API surface that any
conforming implementation must honor.

**Reference implementation:** the local-first CLI in this repo (`cli/bin/opensop`). The server profile in §4 has no maintained reference implementation.
implements the server profile described in this spec (sections 4 and 8). Anyone may
build a compliant server against this document. The local CLI (`cli/`) implements
the local profile; `opensop run` requires no server.

---

## 1. What OpenSOP Is

OpenSOP is process-as-infrastructure for agentic processes. A process is a file
you declare, version, fork, run, and audit — living in your repo, not locked in
a SaaS. The CLI runs processes locally with no server, no network, and no
account required. The server is optional infrastructure for shared orchestration
and monitoring.

> **Terraform is to cloud resources what OpenSOP is to agentic processes.**

**Core beliefs:**

1. **Local-first.** `opensop run` executes against `.sop.json` on your machine — no server, no curl, no account. The server is opt-in via `--remote`.
2. **A process is a file.** One declarative artifact: inputs, steps, outputs. It lives in your repo, reviews in your PRs, ships in your commits.
3. **Processes are company IP.** Self-hostable; never leaves your infrastructure unless you choose.
4. **Every step has a type.** The engine knows which steps need a human, which need an LLM, and which just run.
5. **Agents are first-class consumers.** The discovery endpoint (server profile) lets any agent understand what a company does.
6. **LLM creativity belongs inside deterministic gates.** Agent steps have typed inputs, explicit outputs, validation, receipts, and checks before side effects.

---

## 2. The Process Definition Format

### 2.1 The one logical model — two serializations

A process definition is a single logical object. It can be serialized two ways,
and both are canonical. The parser accepts either form.

**Flat local shorthand (`.sop.json` — primary format for local execution):**

```json
{
  "name": "greet",
  "inputs": { "name": "World" },
  "steps": [
    { "id": "say-hello", "type": "shell", "run": "echo Hello $( jq -r .name <<<"$OSL_CONTEXT" )" }
  ]
}
```

The flat form omits the `opensop` version key and the `process:` wrapper.
The CLI accepts this by default — no server required.

**Wrapped envelope (standard — for server registration and YAML files):**

```yaml
opensop: "0.6"

process:
  name: lead-qualification
  version: "1.0"
  description: "Qualify an inbound lead and assign to a rep"
  inputs:
    - name: lead_name
      type: string
      required: true
    - name: lead_email
      type: string
      format: email
      required: true
    - name: source
      type: enum
      values: [website, linkedin, email, referral]
  outputs:
    - name: qualified
      type: boolean
    - name: assigned_to
      type: string
  steps:
    - id: score-lead
      type: llm
      model: claude-sonnet-4-6
      prompt: "Score this lead 1-10: name={{ lead_name }}, source={{ source }}"
      expected_output_schema:
        score: number
        rationale: string
      outputs:
        - { name: score, type: number }
        - { name: rationale, type: string }
    - id: assign
      type: form
      inputs:
        - name: score
          from: steps.score-lead.outputs.score
      outputs:
        - name: assigned_to
          type: string
```

The CLI (`cli/bin/opensop`) accepts both serializations; the server runtime
requires the wrapped form for registration.

**Spec version policy:**

| Value | Accepted by |
|---|---|
| `"0.1"` | Server parser, CLI `schema validate` |
| `"0.2"` | Server parser, CLI `schema validate` |
| `"0.6"` | Server parser, CLI `schema validate` |
| `"0.7"` | Server parser, CLI `schema validate` |

New process files should declare `opensop: "0.7"`. Files declared at earlier
versions continue to parse and run unchanged — this spec is additive.

---

### 2.2 Process object fields

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Process identifier. Slug-style, e.g. `customer-onboarding`. |
| `version` | Yes | Semver string, e.g. `"1.0"`. |
| `description` | Yes | Human-readable purpose. |
| `inputs` | No | Array of Field objects (see §2.4). |
| `outputs` | No | Array of Field objects declared at process level. |
| `steps` | Yes | Ordered array of Step objects (see §2.5). |
| `trigger` | No | How the process starts (see §2.3). |
| `owner` | No | Team or user label. |
| `tags` | No | Array of strings for discovery/filtering. |
| `sla` | No | `{target: "72h", warning: "48h"}`. |
| `on_error` | No | `{notify: {channel, target}, retry_policy}`. |
| `access` | No | `{start: [], view: [], advance: [], admin: []}`. |
| `sop` | No | Distribution metadata: origin, install hint, discovery tags. See §2.8. Ignored by the execution engine. `recipe` is accepted as a deprecated alias. |
| `evidence` | No | Declares what a trace of this process's execution MUST contain for a conformance claim about it to be checkable. See §2.9.1. Ignored by the execution engine. |
| `agent_contract` | No | Declares the role an agent executing this process fills, and the boundaries it operates within. See §2.9.2. Ignored by the execution engine. |
| `prompt` | No | A reference to the versioned prompt an agent executing this process was given — never the prompt text itself. See §2.9.3. Ignored by the execution engine. |
| `isolation` | No | Declares the execution substrate a conforming runtime should provide (e.g. an independent checkout). See §2.9.4. Advisory; ignored by the execution engine. |

---

### 2.3 Triggers

Declares how a new instance of this process is started.

**API trigger (default — any authenticated POST starts a new instance):**

```yaml
trigger:
  type: api
```

**Webhook trigger (third-party SaaS → OpenSOP):**

```yaml
trigger:
  type: webhook
  auth:
    scheme: hmac-sha256          # only supported scheme
    secret_env: CAL_WEBHOOK_SECRET
    header: X-Cal-Signature-256
    encoding: hex                # hex | base64
    prefix: ""                   # optional; stripped before comparing
  input_mapping:
    attendee_email: "${payload.attendees.0.email}"
    attendee_name:  "${payload.attendees.0.name}"
    meeting_time:   "${payload.startTime}"
    source:         "cal.com"    # literal value
```

Endpoint: `POST /sop/triggers/<process-name>`.
The declared HMAC scheme authenticates the request; `X-SOP-Token` is NOT
required on trigger endpoints.

| Condition | Status | Body |
|---|---|---|
| Instance started | 200 | `{"status":"started","instance_id":"..."}` |
| Mapping failed or input validation failed | 200 | `{"status":"accepted","action":"logged","reason":"..."}` |
| Malformed JSON body | 400 | `{"error":"invalid_payload",...}` |
| HMAC mismatch or missing signature header | 401 | `{"error":"invalid_signature",...}` |
| Process not found | 404 | `{"error":"not_found",...}` |
| No webhook trigger configured | 404 | `{"error":"trigger_not_configured",...}` |
| Secret env var unset | 500 | `{"error":"trigger_misconfigured",...}` |

The 200-with-logged-reason is deliberate: providers like Cal.com send multiple
event types to one endpoint. When the payload does not match the mapping, the
engine logs it but returns 200 so the provider does not retry.

**Supported HMAC providers:**

| Provider | Signature header | Encoding | Prefix |
|---|---|---|---|
| Cal.com | `X-Cal-Signature-256` | hex | — |
| Stripe | `Stripe-Signature` | hex | `v1=` |
| HubSpot | `X-HubSpot-Signature-v3` | hex | — |
| Typeform | `Typeform-Signature` | base64 | `sha256=` |
| GitHub | `X-Hub-Signature-256` | hex | `sha256=` |

> Stripe's timestamp-scoped HMAC variant is not yet supported. Twilio uses HMAC-SHA1, also not implemented.

**Interval trigger (parser-only — scheduler not yet wired):**

```yaml
trigger:
  type: interval
  interval: 30m      # 5s minimum; s / m / h / d suffixes
```

The parser stores `interval_seconds` on the trigger record. Runtime scheduling is
roadmapped. The parser rejects cron (`schedule:`) and time-of-day (`at: [...]`)
forms today.

**Manual trigger:**

```yaml
trigger:
  type: manual
```

Equivalent to API trigger but signals human intent in the definition.

---

### 2.4 Field types

| Type | Description | Example value |
|---|---|---|
| `string` | Text | `"Acme Corp"` |
| `number` | Integer or decimal | `42`, `3.14` |
| `boolean` | True/false | `true` |
| `enum` | One of a declared set | `"approved"` with `values: [approved, rejected]` |
| `date` | ISO 8601 date | `"2026-06-10"` |
| `datetime` | ISO 8601 datetime | `"2026-06-10T09:00:00Z"` |
| `file` | File reference (path or URL) | uploaded PDF |
| `file[]` | Array of files | multiple documents |
| `string[]` | Array of strings | `["item-a", "item-b"]` |
| `object` | Nested structure with schema | `{ legal_name: "Acme", rfc: "ABC123" }` |
| `reference` | ID pointing to another record | `deal_id`, `member_id` |
| `currency` | Amount + currency code | `{ amount: 1500.00, currency: "USD" }` |

**Collection outputs (v0.2):**

Any output field may declare `collection: true` with an `item_schema`:

```yaml
outputs:
  - name: classifications
    type: object
    collection: true
    item_schema:
      label: string
      score: number
```

Collection reference syntax:

| Syntax | Meaning |
|---|---|
| `steps.classify.outputs.classifications` | The whole array |
| `steps.classify.outputs.classifications[*]` | All items (used by `for_each:`) |
| `steps.classify.outputs.classifications[0]` | Indexed access |
| `steps.classify.outputs.classifications[*].label` | Pluck a field across all items |

---

### 2.5 Reference syntax

Inside `from:`, `condition:`, `exit_when:`, and `required_if:`:

| Prefix | Source |
|---|---|
| `process.inputs.<name>` | Process-level input provided at start |
| `steps.<step-id>.outputs.<name>` | Output of a completed step |
| `env.<NAME>` | Environment variable |
| `instance.<field>` | Instance metadata (`started_at`, etc.) |
| `loop.<as-name>` | Loop iteration variable (body steps only) |
| `instance.shared_state.<key>` | Inter-instance shared state (roadmapped — parser rejects today) |

---

### 2.6 Expressions and conditions

Simple boolean expressions used in `condition:`, `exit_when:`, and `required_if:`:

```yaml
condition: "steps.review.outputs.decision == 'approve'"
condition: "steps.verify.outputs.score >= 0.8"
condition: "steps.verify.outputs.result != 'invalid'"
required_if: "status == 'rejected'"
exit_when: "outputs.score < 0.4"
```

Evaluated by `Opensop::ConditionEvaluator` (server) or jq (CLI local engine).
No `eval`, no arbitrary code — the evaluator handles `==`, `!=`, `>=`, `<=`, `>`, `<` against literal scalars.

---

### 2.7 Process versioning

```yaml
process:
  name: customer-onboarding
  version: "2.0"
  replaces: "1.0"
```

Running instances are pinned to the version they started on. `replaces` marks
the prior version as deprecated.

### 2.8 The `sop` object — distribution metadata (additive, v0.7.x; renamed from `recipe` in v0.7.x)

The optional `sop` object makes a `.sop.json` or `.sop.yaml` file
self-describing as a distribution artifact. It carries metadata about where the
file came from and how a consumer can install or reference it. These fields are
**ignored by the execution engine** — they have no effect on how a process runs,
what steps execute, or what outputs are produced. Their sole purpose is
discovery and distribution tooling.

All three fields are optional. Omitting the `sop` object entirely is the
normal case for private or in-repo processes; nothing breaks and nothing changes.

`recipe` is accepted as a **deprecated alias** for `sop`, with the same three
sub-fields (`recipe.source`, `recipe.install`, `recipe.tags`). Conforming
parsers MUST still accept it. If a document has both `sop` and `recipe`, `sop`
wins and `recipe` is ignored.

| Field | Type | Description |
|---|---|---|
| `sop.source` | string | Canonical location of this SOP file. A raw URL (e.g. `https://raw.githubusercontent.com/acme/sops/main/customer-onboarding.sop.json`) or a short owner/slug reference (e.g. `acme/customer-onboarding`) that tooling can resolve. Lets a consumer trace the file back to its authoritative origin. |
| `sop.install` | string | A one-line human- or agent-runnable install hint (e.g. `opensop pull acme/customer-onboarding`). Tooling (CLI, registry UIs) may display this as a copy-pasteable command. Not executed by the engine. |
| `sop.tags` | string[] | Array of strings for discovery and search (e.g. `["sales", "lead-qualification", "crm"]`). Distinct from the process-level `tags` field (§2.2), which is for runtime filtering and appears in `GET /sop/` responses. `sop.tags` is for external registry or marketplace discovery. |

**Rationale:** a shared process file is its own distribution vehicle. Without
`sop`, a consumer who receives a `.sop.json` has no machine-readable way to
know where it came from or how to get updates. With `sop`, the file carries
that metadata alongside its execution definition, enabling a registry or agent to
surface the install command and link back to the source without out-of-band
documentation.

**`.sop.json` example (flat form):**

```json
{
  "name": "customer-onboarding",
  "version": "2.1",
  "description": "Onboard a new customer: collect info, verify, assign rep",
  "sop": {
    "source": "acme/customer-onboarding",
    "install": "opensop pull acme/customer-onboarding",
    "tags": ["onboarding", "crm", "sales"]
  },
  "steps": [
    { "id": "collect", "type": "form", "outputs": [{ "name": "company", "type": "string" }] }
  ]
}
```

**`.sop.yaml` example (wrapped envelope):**

```yaml
opensop: "0.7"

process:
  name: customer-onboarding
  version: "2.1"
  description: "Onboard a new customer: collect info, verify, assign rep"
  sop:
    source: acme/customer-onboarding
    install: opensop pull acme/customer-onboarding
    tags: [onboarding, crm, sales]
  steps:
    - id: collect
      type: form
      outputs:
        - { name: company, type: string }
```

`sop` is a Process field (§2.2), so it follows the same flat/wrapped
projection as every other process field (§2.1): in the wrapped envelope it sits
inside `process:`; in the flat `.sop.json` form it appears as a top-level key
alongside `name`, `steps`, etc. It is purely distribution metadata that
describes the file as an artifact — it never participates in the execution model.

**Engine behavior:** conforming v0.7.x parsers MUST ignore the `sop` object
(and its deprecated `recipe` alias) and their sub-fields when loading a process
for execution — it never affects which steps run or what they produce. Normal
document validation (size limits, type checks, security constraints) still
applies to the object itself. Older or strict parsers that predate the v0.7.x
`sop`/`recipe` field may not recognize it; that is a known compatibility
boundary, not a conformance violation — this metadata is advisory and safe to
drop. This clause establishes no general rule about other unknown keys; it
governs `sop` and its `recipe` alias only.

---

### 2.9 Agent-work fields (additive, v0.7.x)

Sections 2–11 describe what a process *does*: steps, triggers, inputs and
outputs. The four optional Process fields below describe a different axis —
what an *agent* executing this process is, and what must have been recorded
about that execution for a claim about it to be checkable at all. All four
are Process fields (siblings of `name`, `steps`, `sop`), all optional, and
none of them are read by the execution engine: a conforming engine MUST
parse and then ignore all four when running a process, the same way §2.8
requires it to ignore `sop`. Omitting any or all of them changes nothing —
every process definition written before this section existed remains valid
and runs unchanged.

---

#### 2.9.1 `evidence`

The rest of this spec describes what a process's execution *does*. `evidence`
inverts that: it declares what MUST have been recorded for a claim about this
process's execution to be checkable at all. It is the `effects` mechanism
(§3.2) pointed at traces instead of at the world — `effects` is a declared
field a tool refuses to ignore when deciding whether to retry; `evidence` is
a declared field a conformance checker refuses to ignore when deciding
whether to certify a run.

```yaml
evidence:
  required:
    - session_started
    - effective_prompt
    - task_received
    - handoff
```

`evidence.required` is an array of requirement names. Each name is drawn from
one of two closed vocabularies:

| Kind | Names | Satisfied when |
|---|---|---|
| Event-type requirement | Any of the event types in the `event` enum of `schemas/execution-event-0.5.json` (`session_started`, `agent_created`, `agent_terminated`, `task_received`, `intent`, `tool_call`, `tool_result`, `uncertainty`, `handoff`, `error`) | A structurally sound event of that type — its base envelope intact — is present in the trace. |
| Field-level requirement | `effective_prompt` — the only field-level name in v0.1 | The `session_started` event's `effective_prompt` carries a non-empty `body`, or a `uri` that resolves. A `hash`-only `effective_prompt` does NOT satisfy this requirement: a hash proves integrity, not retrievability. |

This spec does not restate the event schema's field-level structure here; see
`schemas/execution-event-0.5.json` for the full shape each event type MUST
have to be considered structurally sound.

Both vocabularies are **closed**. A requirement name that is not an event
type from the schema's `event` enum and not `effective_prompt` MUST be
treated as an error by a conformance checker — never as a silently-passed
requirement. Extending either vocabulary (a new event type, a new
field-level name) is a coordinated spec change, made alongside the schema it
draws from, not something an adopter can introduce informally by writing a
new name into a process file.

**SOPs with no `evidence` block, or an empty one.** A process with no
`evidence` field is **vacuously conformant** — nothing was required, so
nothing can be missing. This mirrors how §3.2 treats a step with no
`effects` field as side-effect-free: absence is a meaningful, valid state,
not an error, and it is what makes this field purely additive — no process
written before `evidence` existed retroactively fails a conformance check it
never declared. A checker MUST state the vacuous case explicitly (e.g. "no
`evidence` block declared — nothing required, vacuously conformant") rather
than printing an unqualified pass, so a vacuous pass is never visually
indistinguishable from a pass that actually checked something.
`evidence: {required: []}` is the same outcome — vacuously conformant — but
is a distinct, deliberate input from omitting the block entirely, and a
checker SHOULD word the two differently for an operator scanning output.

**This is a conformance concern, not an execution concern.** A conforming
execution engine MUST ignore `evidence` when running a process: it MUST NOT
affect step dispatch, retries, timeouts, outputs, or any other execution
behavior. `evidence` is checked only by a separate conformance checker that
compares a process definition against a trace of one execution of it,
strictly after the fact — the same boundary that keeps `sop` (§2.8) out of
execution, applied here to a field that is inherently retrospective rather
than merely advisory. A reference conformance checker implementing this
grammar against `schemas/execution-event-0.5.json` ships at
`adapters/conformance.py`; its design rationale and worked examples live in
`adapters/EVIDENCE-CONTRACT.md`.

**Worked example.** An SOP that requires a session to have started with a
retrievable prompt, a task to have been formally received, and a handoff to
close it out:

```json
{
  "name": "extract-action-items",
  "version": "1.0",
  "description": "Extract action items from a transcript",
  "steps": [
    { "id": "extract", "type": "automated", "run": "steps/extract.sh" }
  ],
  "evidence": {
    "required": ["session_started", "effective_prompt", "task_received", "handoff"]
  }
}
```

Checked against a trace missing a `handoff` event, a conformance checker
reports that requirement missing and the process non-conformant, while every
other declared requirement is reported present — presence is evaluated
per-requirement, not as an all-or-nothing bundle.

---

#### 2.9.2 `agent_contract`

Declares the role an agent executing this process fills, and the boundaries
it operates within.

```yaml
agent_contract:
  kind: worker          # planner | worker — exactly two, closed
  owns: task
  may_spawn: false
  lateral_communication: forbidden
```

| Field | Required | Description |
|---|---|---|
| `kind` | No | `planner` or `worker`. Exactly two values, closed. A worker writes code (or otherwise produces the artifact); a planner owns and decomposes scope. Matches the `agent.kind` enum in `schemas/execution-event-0.5.json`. |
| `owns` | No | Free-text label for the unit of scope this agent is responsible for (e.g. `task`, `epic`). |
| `may_spawn` | No | Boolean. Whether this agent may create subordinate agents. |
| `lateral_communication` | No | `forbidden` or `permitted`. Whether this agent may communicate directly with sibling agents, rather than only through its parent or children. |

**The vocabulary is deliberately minimal.** This spec mints no roles beyond
`planner` and `worker` — no reviewer, judge, integrator, or coordinator —
because those responsibilities already have a home elsewhere in this spec: a
judgment call is a `judgment` step (§3.9) or an `approval` step (§3.7);
review and integration are what planners and workers already do for each
other through ordinary handoffs, not a third kind of agent. A third `kind`
value would be a coordinated, closed-vocabulary change, not something an
adopter introduces by writing a new string into a process file — the same
discipline `evidence`'s closed vocabulary (§2.9.1) follows.

`agent_contract` is declarative. A conforming execution engine MUST ignore
it: it does not gate step dispatch, and the local engine does not verify
that the agent actually running a process matches the declared contract. An
orchestrating harness MAY use it to configure or constrain the agent it
launches; that enforcement, like `evidence`'s conformance check, happens
outside the execution engine.

**Enforcement is optional, but half-enforcement is not.** A harness that
elects to enforce `agent_contract` and cannot back a given declaration MUST
refuse the run rather than execute it unenforced. A trace of an unenforced
run is indistinguishable from a trace of an enforced one, so silently
proceeding produces a record that overstates its own evidence — the failure
§11.7 exists to prevent. Where a harness does enforce, the constraint the
agent actually ran under is recorded in `session_started.permission_envelope`
(required by `schemas/execution-event-0.5.json`), which is where an auditor
looks to tell *could not have* from *was asked not to*.

This spec deliberately does not say *how* a declaration is to be enforced.
The mapping from a `kind` to a sandbox, an allow-list, or an isolation
mechanism is a property of a harness and its backend, not of this format,
and no such mapping can be stated neutrally while only one enforcing
implementation exists.

**`lateral_communication` is the exception, and the limit is structural.** A
conformance checker MUST NOT report `lateral_communication: forbidden` as
verified from an execution trace. A trace can show that a spawn tree is
well-formed; it can never show that a side channel was absent. Enforcement
of this field is by construction — by what the harness makes possible — and
a trace is silent on it, not affirmative.

---

#### 2.9.3 `prompt`

A reference to the versioned prompt an agent executing this process was
given — never the prompt text itself.

```yaml
prompt:
  id: software-worker
  version: "2.4"
```

| Field | Required (if `prompt` present) | Description |
|---|---|---|
| `id` | Yes | Identifier of the prompt. |
| `version` | Yes | Version of that prompt (e.g. semver-style, or any identifier the prompt's own versioning scheme uses). |

**Why a reference, never the text.** A prompt embedded in a process file
cannot be versioned, diffed, or reviewed independently of the process that
uses it — and the text that actually reaches a model is a *composition*
(this prompt plus tool definitions, task context, and harness-injected
material) that the process file never sees and has no way to represent. That
composition is what `session_started.effective_prompt` in
`schemas/execution-event-0.5.json` records, at execution time, in the event
stream — not here. `prompt` names and versions the reusable input; the event
stream is the only place the actual, composed output of that input is ever
recorded.

Ignored by the execution engine, for the same reason `sop` (§2.8) is: it
identifies something about the process as an artifact without affecting how
the process runs.

---

#### 2.9.4 `isolation`

Declares the execution substrate a conforming runtime should provide for an
agent executing this process.

```yaml
isolation:
  repository: independent-checkout
```

| Field | Required | Description |
|---|---|---|
| `repository` | No | Repository isolation the runtime should provide (e.g. `independent-checkout` — a dedicated clone or worktree, not a working copy shared with other concurrent work). |

`isolation` is advisory. A conforming runtime SHOULD provide the declared
substrate, but the local execution engine (§5) does not verify it and a
process lacking the declared isolation still runs — this field documents an
expectation of the environment around execution, not a precondition the
engine checks before running.

---

## 3. Step Types — Complete Reference

### 3.1 Capability matrix

For each step type, the table shows its status in each profile. "Working" means
the step executes end-to-end in production. "Stubbed" means the executor class
exists and the instance transitions to a terminal/waiting state, but the core
business logic is not implemented. "Not in profile" means the step type is not
dispatched or recognized in that profile.

| Step type | Server profile | Local profile (CLI v0.6) | Primary waiting reason |
|---|---|---|---|
| `automated` | Working | Working | — (synchronous) |
| `shell` | Not in profile | Working (local-only extension) | — (synchronous) |
| `noop` | Not in profile | Working (local-only extension) | — (synchronous) |
| `form` | Working | Working | `waiting_for_input` |
| `approval` | Working | Working (pause) | `waiting_for_approval` |
| `llm` | Working | Not in profile (falls to unsupported) | — |
| `judgment` | Stubbed — escalates to human | Not in profile | `escalated` |
| `webhook` | Working (sync + callback); poll stubbed | Not in profile | `waiting_for_callback` |
| `subprocess` | Stubbed — pauses instance | Not in profile | `waiting_for_callback` |
| `notification` | Stubbed — returns `{notified: true}` immediately | Not in profile | — |
| `wait` | Partial — `wait.seconds` returns immediately; `wait.until` pauses | Not in profile | `waiting_for_callback` |
| `loop` | Working (`for_each` / `repeat_until` / `while`) | Not in profile | — |

> **"Not in profile" in the local engine** means the step falls to the `*` arm of
> the dispatch case in `_local_step_loop`, which sets `rc=2` and fails the step
> with "unsupported step type for local execution: \<type\>". The run transitions
> to `failed` unless `continue_on_error: true` is set.

### 3.2 Step fields common to all types

| Field | Required | Description |
|---|---|---|
| `id` | Yes | Step identifier. Pattern: `[a-z0-9][a-z0-9_-]*`. |
| `name` | No | Human-readable label. |
| `type` | Yes | One of the 10 types listed in §3.1. |
| `inputs` | No | Array of field references resolved at runtime. |
| `outputs` | No | Declared output fields (name, type, optional schema). |
| `condition` | No | Boolean expression; step is skipped when false. |
| `exit_when` | No | Boolean expression; if true after step completes, process terminates immediately with `exit_outputs`. |
| `exit_outputs` | No | Literal key-value map merged into process outputs on early exit. |
| `continue_on_error` | No | `true` = run continues even if this step fails. |
| `executor` | No | Audit metadata only. See §6. |
| `effects` | No | Plain-string description of what this step does to the world outside the run (e.g. `"publishes a post to LinkedIn"`, `"sends an email"`, `"spends ad budget"`). **The presence of the field, not its content, is the signal:** a step that declares `effects` is irreversible and MUST NOT be silently auto-retried, because the step can fail from the caller's point of view (timeout, dropped connection) after the underlying action already succeeded remotely — retrying then double-posts, double-sends, or double-spends. A step with no `effects` field is assumed side-effect-free to retry. There is no enum or boolean form; any non-empty string is sufficient. Process-level effects are not a stored field — a conforming implementation derives them, when needed, as the union of the `effects` declared across a process's steps. Any conforming heal/retry mechanism (e.g. `opensop heal --apply`, §11.4) MUST refuse to auto-retry a step that declares `effects` unless the operator explicitly overrides the refusal. |

---

### 3.3 `automated` — run a script

Executes a script (any language, detected by extension or shebang). The engine
passes resolved inputs as JSON via stdin; the script returns JSON via stdout.

```yaml
- id: verify-documents
  type: automated
  run: steps/verify-documents.py
  validation: strict            # lenient (default) | strict
  retry:
    max: 3
    backoff: exponential
  timeout: 60                   # seconds; default 60 (server)
  inputs:
    - name: business_record
      from: steps.collect-info.outputs.business_record
  outputs:
    - name: verification_result
      type: enum
      values: [complete, incomplete, invalid]
```

**Server execution protocol:**
1. Resolve inputs from previous steps.
2. JSON-encode inputs, pipe to script via stdin (`OSL_CONTEXT` env also available).
3. Read JSON from stdout as outputs.
4. Validate against `outputs:` schema; on failure: retry per `retry:`, then fail step.

**`validation:` modes (v0.2):**

| Mode | Behavior |
|---|---|
| `lenient` (default) | Missing declared output keys silently become `null` downstream. |
| `strict` | Any declared output key absent from stdout JSON fails the step immediately with a listing of missing keys. Extra keys are permitted. Type validation is not yet enforced; presence only. |

**Local engine (CLI):** resolves the script path relative to the process file's
directory, then the parent directory. Passes context JSON via `OSL_CONTEXT` env
and stdin. Non-JSON stdout is wrapped as `{stdout: "..."}`.

---

### 3.4 `shell` — local-only inline script

Local extension not present in the server runtime.

```json
{ "id": "greet", "type": "shell", "run": "echo Hello, world" }
```

Runs `bash -c <run>` with context JSON on stdin. On the server, `shell` is not a
recognized type and the instance will fail.

---

### 3.5 `noop` — no-op placeholder

Local extension not present in the server runtime. Returns `{}` immediately. Useful
as a placeholder step during development.

```json
{ "id": "placeholder", "type": "noop" }
```

---

### 3.6 `form` — collect data from a human or agent

```yaml
- id: collect-info
  type: form
  inputs:
    - name: company_name
      from: process.inputs.company_name
  outputs:
    - name: business_record
      type: object
      schema:
        legal_name: string
        rfc: string
  timeout: 7d
  on_timeout: notify-and-wait
```

**Semantics:** the executor returns `{waiting: "waiting_for_input"}` immediately.
The instance pauses. Submission via
`POST /sop/<name>/<id>/steps/<step_id>/submit` (server) or
`opensop submit <run_id> <step-id> --output k=v` (local) advances the step.

---

### 3.7 `approval` — binary gate

```yaml
- id: manager-approval
  type: approval
  approvers: [manager-role]
  timeout: 48h
  outputs:
    - name: approved
      type: boolean
    - name: notes
      type: string
```

**Semantics:** executor returns `{waiting: "waiting_for_approval"}`. Advances on
`submit`. In the local engine, the step pauses with reason `waiting_for_approval`.

---

### 3.8 `llm` — first-class LLM call (v0.2)

```yaml
- id: classify-intent
  type: llm
  model: claude-sonnet-4-6
  prompt_file: prompts/classify.md    # OR inline prompt: "..."
  tools: [Read, Grep]                 # optional; passed to the provider
  retry_on_incomplete: true           # default true
  max_retries: 2                      # default 2
  expected_output_schema:
    intent: enum[question, task, complaint]
    confidence: number
    rationale: string
  inputs:
    - name: message
      from: process.inputs.user_message
  outputs:
    - { name: intent, type: enum, values: [question, task, complaint] }
    - { name: confidence, type: number }
    - { name: rationale, type: string }
  timeout: 2m
```

**Server semantics:**
1. Render `prompt` / `prompt_file` with `{{ var }}` substitution over resolved inputs.
2. Call configured provider (Anthropic by default for `claude-*` models).
3. Validate response against `expected_output_schema`.
4. On schema failure: retry with a corrective preamble up to `max_retries`; then fail.

Events: `step.llm.requested`, `step.llm.responded`, `step.llm.retry`.

**`expected_output_schema` mini-grammar:** `string | number | boolean | enum[a,b,c] | object (nested) | array[<type>]`.

**Local engine:** not dispatched. Falls to unsupported arm, fails with `rc=2`.

---

### 3.9 `judgment` — LLM or human decision

```yaml
- id: review-application
  type: judgment
  judgment:
    allow_agent: true
    require_human_review: false
    confidence_threshold: 0.9
    escalation: manual
  inputs:
    - name: business_record
      from: steps.collect-info.outputs.business_record
  outputs:
    - name: decision
      type: enum
      values: [approve, reject, request-more-info]
    - name: rejection_reason
      type: string
      required_if: "decision == 'reject'"
```

**Server status — stubbed.** The `Judgment` executor does not call an LLM. It
emits a `step.escalated` event with `reason: "llm_router_not_implemented"` and
returns `{waiting: "escalated"}`. The instance waits for a human to submit via
the API.

**Local engine:** not dispatched.

---

### 3.10 `webhook` — outbound HTTP call

```yaml
- id: submit-to-compliance
  type: webhook
  condition: "steps.review.outputs.decision == 'approve'"
  webhook:
    method: POST
    url: "${env.COMPLIANCE_URL}/entities"
    headers:
      Authorization: "Bearer ${env.COMPLIANCE_API_KEY}"
    body_template: steps/compliance-payload.json   # optional; else inputs used
    response_mode: callback                         # REQUIRED — sync | callback | poll
    poll_timeout: 7d
  inputs:
    - name: business_record
      from: steps.collect-info.outputs.business_record
  outputs:
    - name: entity_id
      type: string
    - name: compliance_status
      type: enum
      values: [pending, approved, rejected]
```

**`webhook` block fields:**

| Field | Required | Description |
|---|---|---|
| `url` | Yes | Outbound request URL. Supports `${env.X}`, `${inputs.X}`, `${callback_url}`. |
| `method` | Yes | HTTP verb: `GET`, `POST`, `PUT`, `PATCH`, or `DELETE`. |
| `response_mode` | **Yes** | How the step handles the response. Must be one of `sync`, `callback`, or `poll`. No default — omitting this field is a parse error. |
| `headers` | No | Key/value map of request headers. Values support template interpolation. |
| `body_template` | No | Path to a JSON body template under `processes/`. If omitted, step inputs are sent as JSON. |
| `poll_timeout` | No | Expiry for callback/poll waiting (e.g. `7d`, `2h`). |

**Response modes:**

| Mode | Server status | Semantics |
|---|---|---|
| `sync` | Working | Fire-and-return; HTTP response body is the step outputs. |
| `callback` | Working | Auto-generates callback URL (`/sop/webhooks/<uuid>`), injects as `${callback_url}`. Instance pauses until the third party POSTs to that URL. |
| `poll` | Stubbed | Not implemented; the executor raises `StepFailure`. |

**URL / header interpolation:** `${env.X}` resolves environment variables; `${inputs.X}` resolves step inputs; `${callback_url}` injects the generated callback path.

**Local engine:** not dispatched.

---

### 3.11 `subprocess` — start a child process

```yaml
- id: run-kyc
  type: subprocess
  process: kyc-verification
  inputs:
    - name: person_name
      from: steps.collect-info.outputs.owner_name
  outputs:
    - name: kyc_status
      type: enum
      values: [passed, failed, manual_review]
```

**Server status — stubbed.** The `Subprocess` executor emits
`step.subprocess_pending` and returns `{waiting: "waiting_for_callback"}`. No
child instance is started. The step must be advanced manually.

**Local engine:** not dispatched.

---

### 3.12 `notification` — fire-and-forget message

```yaml
- id: send-welcome
  type: notification
  channel: email
  to: "${steps.collect-info.outputs.contact_email}"
  template: templates/welcome.html
```

**Server status — stubbed.** The `Notification` executor returns
`{outputs: {notified: true, email_sent: true}}` immediately without sending
anything. The instance advances.

**Local engine:** not dispatched.

---

### 3.13 `wait` — pause until condition or timer

```yaml
- id: wait-for-compliance
  type: wait
  wait:
    seconds: 3600           # OR:
    until: "steps.check.outputs.ready == true"
```

**Server behavior:**
- `wait.seconds` present: returns `{outputs: {waited: true, seconds: N}}` immediately (does not actually sleep — synchronous stub).
- `wait.until` present: returns `{waiting: "waiting_for_callback"}` and pauses.

**Local engine:** not dispatched.

---

### 3.14 `loop` — iteration (v0.2)

```yaml
- id: process-each-lead
  type: loop
  loop:
    for_each: steps.fetch-leads.outputs.leads[*]   # OR repeat_until / while
    as: lead
    max_iterations: 100
    aggregate:
      results: concat
  body:
    - id: enrich
      type: llm
      inputs:
        - { name: lead, from: loop.lead }
      outputs:
        - { name: enriched, type: object }
  outputs:
    - { name: results, type: object, collection: true, item_schema: { name: string, score: number } }
```

**Variants:**

| Variant key | Termination |
|---|---|
| `for_each: <collection>` | Items exhausted |
| `repeat_until: "<expr>"` | Predicate true at end of iteration |
| `while: "<expr>"` | Predicate true at start of iteration |

`max_iterations` accepts a positive integer literal OR `{{ process.inputs.<name> }}`.
`aggregate` per output: `sum` (numbers), `concat` (arrays/strings), `last` (final iteration only).

**Server status:** Working.

**Local engine:** not dispatched.

---

### 3.15 `exit_when` — step-level early exit (v0.2)

A per-step field, not a step type. Applies to any step.

```yaml
- id: gate
  type: automated
  run: steps/gate.sh
  outputs:
    - { name: score, type: number }
  exit_when: "outputs.score < 0.4"
  exit_outputs:
    outcome: "rejected_low_score"
    reason: "Score below threshold"
```

If the predicate is true after step completion, the process terminates
immediately with `instance.exited_early` and the literal `exit_outputs`. Not
an error — `instance.state` becomes `"completed"`.

---

## 4. The Server Runtime

### 4.1 Components

| Component | Responsibility |
|---|---|
| **Definition Registry** (`Opensop::Registry`) | Loads `.sop.yaml` from `processes/`, upserts into `sop_processes`. `bin/rails opensop:load_processes` re-syncs. _(Illustrative of a server implementation; not a command of this repo, and no maintained server implements it today.)_ |
| **Instance Executor** (`Opensop::InstanceExecutor`) | Orchestrates an instance: resolves inputs, evaluates conditions, dispatches step executors, handles early exit. |
| **Step Executors** (`Opensop::StepExecutors::*`) | One class per step type. See §3. |
| **Condition Evaluator** (`Opensop::ConditionEvaluator`) | The only safe path for user-authored expressions. No `eval`, no `instance_eval`. |
| **Input Resolver** (`Opensop::InputResolver`) | Resolves `from:` references against instance state. |
| **LLM Provider** (`Opensop::LlmProviders::Anthropic`) | Calls Anthropic for `llm` steps. Provider resolved by model name prefix (`claude-*`). |
| **API Gateway** | Rails controllers under `/sop/*`. Auto-generated from process definitions. |

### 4.2 Server HTTP API

All endpoints are rooted under `/sop/`. This section is the normative HTTP API
contract — implementers build against it; clients depend on it.

**Conventions:**

| | |
|---|---|
| **Content-Type** | `application/json` for all request bodies |
| **Response format** | JSON, UTF-8 |
| **Timestamps** | ISO 8601 with `Z` suffix (UTC) |
| **IDs** | UUIDs (v4) |
| **Pagination** | `limit` + `offset` query params where supported |
| **Process name** | Pattern: `[a-z0-9][a-z0-9_-]*` |

**Endpoints at a glance:**

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/sop/` | List all active processes (discovery) |
| `GET` | `/sop/:name/schema` | Full YAML-derived process definition as JSON |
| `POST` | `/sop/:name/start` | Start a new instance |
| `GET` | `/sop/:name/:id` | Instance state + all steps |
| `GET` | `/sop/:name/:id/steps` | Step states only (compact) |
| `POST` | `/sop/:name/:id/steps/:step_id/submit` | Submit outputs → advance a waiting step |
| `POST` | `/sop/:name/:id/cancel` | Cancel an instance |
| `GET` | `/sop/instances` | List all instances across processes (admin) |
| `GET` | `/sop/metrics` | Process metrics |
| `POST` | `/sop/webhooks/:callback_id` | Inbound webhook callback (unauthenticated) |
| `POST` | `/sop/triggers/:process_name` | Third-party webhook-triggered start (HMAC-authenticated) |

#### Authentication

OpenSOP uses a single header: **`X-SOP-Token`**.

The server reads the expected token from `OPENSOP_API_TOKEN`.

**Dev mode (token unset):** In development/test, authentication is skipped and
every request is allowed. The server logs a warning on first request. In
production, the engine refuses to serve `/sop/*` when the token is unset —
every request returns `503 server_misconfigured`. This fail-closed behaviour
prevents exposing instance data (including PII from inputs) on an unguarded
deploy. Set the token via your platform's secret manager before directing
traffic at the deploy.

**Strict mode (token set):** Every non-webhook request must include
`X-SOP-Token` with a matching value. Mismatch returns `401`.

The `actor` field on events and step submissions derives from this: `"agent"` when
a valid token was presented, `"system"` when anonymous (dev mode).

**Exception:** `POST /sop/webhooks/:callback_id` and `POST /sop/triggers/:name`
never require `X-SOP-Token` — third parties call these and would not know the token.
Trigger endpoints authenticate via the declared HMAC scheme (§2.3).

#### `GET /sop/`

Returns every active process (latest version per name). Agents use this for
discovery.

**Response — 200 OK**

```json
{
  "processes": [
    {
      "name": "lead-qualification",
      "version": "1.0",
      "description": "Qualify an inbound lead and score their fit",
      "tags": ["growth", "sales", "qualification"],
      "inputs_summary":  "lead_name (string, required), lead_email (string, required), source (enum: website|linkedin|referral, required)",
      "outputs_summary": "score (number), qualified (boolean)",
      "sla": null,
      "schema_url": "/sop/lead-qualification/schema"
    }
  ]
}
```

`inputs_summary` / `outputs_summary` are human-readable strings for agent prompts
and admin lists. For full field types fetch the schema.

#### `GET /sop/:name/schema`

Returns the full YAML-derived definition as JSON. Agents consume this to understand
exact inputs, outputs, and step structure before starting an instance.

**Query parameters:**

| Param | Type | Default | Meaning |
|---|---|---|---|
| `version` | string | latest | Pin to a specific version (e.g. `"1.0"`) |

**Response — 200 OK** — the raw definition with `opensop` (format version) and
`process` (the definition body).

**Errors:**

| Status | `error` | When |
|---|---|---|
| `404` | `not_found` | No active process by that name (or no matching version) |

#### `POST /sop/:name/start`

Starts a new instance. The engine validates `inputs` against the process's declared
input schema, then advances through any auto-executing prefix (e.g. `automated`
steps before the first `form`). The response is the instance state after that initial
advance — a `form` step typically shows up in `sub_state=waiting_for_input` on
first response.

**Request body:**

| Field | Type | Required | Meaning |
|---|---|---|---|
| `inputs` | object | yes | Values for every required process input. Keys must match `process.inputs[*].name`. |
| `metadata` | object | no | Free-form key/value for your own tracking. The engine adds `actor` automatically. |

**Response — 201 Created**

```json
{
  "id": "fea4a13c-227d-40e6-8713-4208b4ee983b",
  "process": { "name": "lead-qualification", "version": "1.0" },
  "state": "running",
  "inputs":  { "lead_name": "Alice", "lead_email": "alice@example.com", "source": "website" },
  "outputs": {},
  "metadata": { "actor": "agent" },
  "started_at":   "2026-04-21T13:25:45Z",
  "completed_at": null,
  "error": null,
  "links": {
    "self":   "/sop/lead-qualification/fea4a13c-...",
    "steps":  "/sop/lead-qualification/fea4a13c-.../steps",
    "cancel": "/sop/lead-qualification/fea4a13c-.../cancel"
  },
  "steps": [
    {
      "id": "eb7c0072-...",
      "step_id": "collect-context",
      "name": "Collect lead context",
      "type": "form",
      "state": "active",
      "sub_state": "waiting_for_input",
      "inputs":  { "lead_name": "Alice" },
      "outputs": {},
      "decided_by": null,
      "confidence": null,
      "position": 1,
      "started_at":   "2026-04-21T13:25:45Z",
      "completed_at": null,
      "error": null,
      "links": { "submit": "/sop/lead-qualification/fea4a13c-.../steps/collect-context/submit" }
    }
  ]
}
```

**Errors:**

| Status | `error` | When |
|---|---|---|
| `404` | `not_found` | No active process by that name |
| `422` | `invalid_inputs` | Required input missing, type mismatch, enum value not allowed, etc. |
| `422` | `unknown_step_type` | Process YAML references a step type the engine doesn't implement |

#### `GET /sop/:name/:id`

Fetch the full current state of an instance plus every step. Poll this while
waiting on long-running work. Response shape is identical to the `POST .../start`
response.

**Errors:**

| Status | `error` | When |
|---|---|---|
| `404` | `not_found` | No instance with that `id` under that process name |

#### `GET /sop/:name/:id/steps`

Compact view — just the steps, no instance envelope. Useful when you only need
step state.

**Response — 200 OK**

```json
{
  "steps": [
    { "step_id": "collect-context", "type": "form",      "state": "completed", "outputs": { "budget": 12000 } },
    { "step_id": "score-lead",      "type": "automated", "state": "completed", "outputs": { "score": 84, "qualified": true } },
    { "step_id": "notify-team",     "type": "notification", "state": "completed" }
  ]
}
```

#### `POST /sop/:name/:id/steps/:step_id/submit`

Submit outputs for an active step. Used for:

- **`form` steps** — human or agent supplies the fields (`sub_state=waiting_for_input`)
- **`judgment` steps** — human or agent supplies the decision (`sub_state=escalated`)
- **`approval` steps** — human approves or rejects (`sub_state=waiting_for_approval`)
- **Retrying `failed` steps** — supply corrected outputs after a failure

For `automated`, `webhook`, `notification`, `wait`, and `subprocess` steps the
engine submits internally — do not call this endpoint for them. Webhook callbacks
arrive via `POST /sop/webhooks/:callback_id`.

**Request body:**

| Field | Type | Required | Meaning |
|---|---|---|---|
| `outputs` | object | yes | Values matching the step's declared outputs. Keys must match `step.outputs[*].name`. |
| `decided_by` | string | no | Who made the decision. Defaults to the token's actor. Conventionally `"human:<id>"`, `"agent:<id>"`, or `"webhook"`. |
| `confidence` | number | no | 0.0–1.0 confidence score. For `judgment` steps, below the process's `confidence_threshold` may trigger escalation. |

**Response — 200 OK**

```json
{
  "step": {
    "step_id": "collect-context",
    "state": "completed",
    "outputs": { "budget": 12000, "timeline": "immediate" },
    "decided_by": "agent:sales-copilot",
    "confidence": 0.93,
    "completed_at": "2026-04-21T13:26:12Z"
  },
  "instance": {
    "state": "completed",
    "outputs": { "score": 84, "qualified": true },
    "completed_at": "2026-04-21T13:26:13Z",
    "steps": [ "...all steps, including ones that auto-advanced after submission..." ]
  }
}
```

The engine may advance through several steps after a single submission (all
`automated` / `notification` / `wait` steps between this one and the next
human-gated step). The response always reflects state after all cascading advances
complete.

**Errors:**

| Status | `error` | When |
|---|---|---|
| `404` | `not_found` | Instance or step not found |
| `422` | `step_not_submittable` | Step is not in an active or failed state |
| `422` | `invalid_inputs` | `outputs` don't match declared schema |
| `422` | `invalid_transition` | Step could not be advanced (rare; usually a race condition) |

#### `POST /sop/:name/:id/cancel`

Cancels an instance. Sets `state` to `"cancelled"`, records the reason, and writes
a `Sop::Event` of type `"instance.cancelled"`. All active steps are marked
`skipped`. No cascading rollback — whatever already happened (account created,
email sent) stays happened.

**Request body:**

| Field | Type | Required | Meaning |
|---|---|---|---|
| `reason` | string | no | Free-form. Stored on the instance and in the cancellation event. |

**Response — 200 OK** — same shape as `GET /sop/:name/:id` with `state: "cancelled"`.

**Errors:**

| Status | `error` | When |
|---|---|---|
| `404` | `not_found` | Instance not found |
| `422` | `invalid_transition` | Instance is already in a terminal state (completed/failed/cancelled) |

#### `GET /sop/instances`

List instances across all processes. Intended for ops dashboards and monitoring.

**Query parameters:**

| Param | Type | Default | Meaning |
|---|---|---|---|
| `state` | string | — | Filter by instance state (`running`, `completed`, `failed`, `cancelled`) |
| `process` | string | — | Filter by process name |
| `limit` | int | 50 | Max rows. Clamped to 200. |
| `offset` | int | 0 | Pagination offset |

**Response — 200 OK**

```json
{
  "instances": [
    {
      "id": "fea4a13c-...",
      "process": { "name": "lead-qualification", "version": "1.0" },
      "state": "running",
      "inputs":  {},
      "outputs": {},
      "metadata": { "actor": "agent" },
      "started_at": "2026-04-21T13:25:45Z",
      "completed_at": null,
      "error": null,
      "links": {}
    }
  ],
  "total": 1,
  "limit": 50,
  "offset": 0
}
```

`steps` is omitted from the list view. Fetch the instance individually if you need them.

#### `POST /sop/webhooks/:callback_id`

Inbound webhook receiver. A `webhook` step creates a `Sop::Callback` with a unique
`callback_id`. The third-party provider POSTs here when it has an answer. The engine
records the payload, merges it into the step's outputs, and advances the instance.

**This endpoint does not require `X-SOP-Token`.** If you need callback-level auth,
encode a secret in the `callback_id` itself (it is a random UUID, so it is
unguessable) or add HMAC verification at the application layer.

The JSON body keys should match the declared `outputs:` of the webhook step that
registered this callback.

**Response — 200 OK:** `{ "status": "received" }`

**Errors:**

| Status | `error` | When |
|---|---|---|
| `404` | `not_found` | No pending callback at that path |
| `409` | `callback_already_resolved` | Callback was already received or marked expired |
| `422` | `invalid_callback_payload` | Payload didn't satisfy declared outputs. Raw payload is still persisted — no data loss. |

#### `POST /sop/triggers/:process_name`

Lets a SaaS provider (Cal.com, Stripe, Typeform, HubSpot, DocuSign, etc.) start
an OpenSOP process instance directly from its own webhook delivery — no host-side
adapter required. Auth is HMAC signature verification, configured per-process in
the YAML (§2.3).

**This endpoint does not require `X-SOP-Token`.** The declared HMAC scheme is the
authentication.

For setup instructions, response codes, and supported provider signatures, see §2.3.

#### Error response shape

All error responses share a common envelope:

```json
{
  "error":   "short_machine_code",
  "message": "human-readable description"
}
```

Possible `error` values:

| Value | HTTP | Source |
|---|---|---|
| `unauthorized` | 401 | Missing/invalid `X-SOP-Token` in strict mode |
| `not_found` | 404 | Process or instance not found |
| `callback_already_resolved` | 409 | Webhook callback already received or expired |
| `invalid_inputs` | 422 | Process inputs or step outputs don't match schema |
| `invalid_transition` | 422 | Cannot advance/cancel from current state |
| `invalid_definition` | 422 | Malformed process definition |
| `unresolved_reference` | 422 | A `from:` reference couldn't be resolved (indicates a YAML bug) |
| `unknown_step_type` | 422 | Process references a step type the engine doesn't implement |
| `step_not_submittable` | 422 | Tried to submit to a step that isn't in `active` or `failed` state |
| `invalid_callback_payload` | 422 | Webhook payload doesn't match declared outputs |
| `server_misconfigured` | 503 | `OPENSOP_API_TOKEN` not set in production |

### 4.3 Server instance lifecycle

```
start() → RUNNING
           │
    ┌──────┼──────────────┐
    ▼      ▼              ▼
 STEP:  STEP:          STEP:
 active waiting        skipped
        │              (condition false)
        ▼
 submit_step()
        │
        ▼
 STEP: completed → next step
                 → early exit (exit_when true) → instance COMPLETED
                 │
                 ▼ (all steps done)
           instance COMPLETED | FAILED | CANCELLED
```

**Instance states:** `pending` → `running` → `completed` | `failed` | `cancelled`

**Step states:** `pending` → `active` → `completed` | `failed` | `skipped`

**Step sub-states (while active):**

| `sub_state` | Meaning |
|---|---|
| `waiting_for_input` | `form` step awaiting `POST .../submit` |
| `escalated` | `judgment` step awaiting submission (LLM low-confidence or no router wired) |
| `waiting_for_approval` | `approval` step awaiting a human decision |
| `waiting_for_callback` | `webhook` step awaiting `POST /sop/webhooks/:callback_id` |
| `waiting_for_subprocess` | `subprocess` step awaiting child instance completion |
| `waiting_for_timer` | `wait` step with a `seconds:` or `until:` condition |

### 4.4 Server data model

```sql
CREATE TABLE sop_processes (
  id         UUID PRIMARY KEY,
  name       VARCHAR NOT NULL,
  version    VARCHAR NOT NULL,
  definition JSONB NOT NULL,        -- full parsed YAML
  owner      VARCHAR,
  tags       TEXT[],
  status     VARCHAR DEFAULT 'active',
  created_at TIMESTAMP NOT NULL,
  UNIQUE(name, version)
);

CREATE TABLE sop_instances (
  id               UUID PRIMARY KEY,
  process_id       UUID REFERENCES sop_processes(id),
  process_name     VARCHAR NOT NULL,
  process_version  VARCHAR NOT NULL,
  state            VARCHAR NOT NULL,
  inputs           JSONB,
  outputs          JSONB,
  metadata         JSONB,
  started_at       TIMESTAMP,
  completed_at     TIMESTAMP,
  error            TEXT,
  created_at       TIMESTAMP NOT NULL
);

CREATE TABLE sop_steps (
  id           UUID PRIMARY KEY,
  instance_id  UUID REFERENCES sop_instances(id),
  step_id      VARCHAR NOT NULL,
  step_name    VARCHAR,
  step_type    VARCHAR NOT NULL,
  state        VARCHAR NOT NULL,
  sub_state    VARCHAR,
  inputs       JSONB,
  outputs      JSONB,
  decided_by   VARCHAR,
  confidence   FLOAT,
  attempt      INTEGER DEFAULT 1,
  position     INTEGER NOT NULL,
  started_at   TIMESTAMP,
  completed_at TIMESTAMP,
  error        TEXT,
  created_at   TIMESTAMP NOT NULL
);

CREATE TABLE sop_events (
  id          UUID PRIMARY KEY,
  instance_id UUID REFERENCES sop_instances(id),
  step_id     VARCHAR,
  event_type  VARCHAR NOT NULL,
  actor       VARCHAR,
  data        JSONB,
  created_at  TIMESTAMP NOT NULL
);

CREATE TABLE sop_callbacks (
  id            UUID PRIMARY KEY,
  instance_id   UUID REFERENCES sop_instances(id),
  step_id       VARCHAR NOT NULL,
  callback_path VARCHAR NOT NULL UNIQUE,
  status        VARCHAR DEFAULT 'pending',
  response      JSONB,
  expires_at    TIMESTAMP,
  created_at    TIMESTAMP NOT NULL
);
```

---

## 5. The Local Execution Backend

### 5.1 What it is

The CLI (`cli/bin/opensop`) includes a self-contained local execution engine.
Local execution is the **default**: `opensop run` executes on your machine with
no server, no network, and no curl required. Remote execution is opt-in via
`--remote` (configured server) or `--server <url>`. The `--local` flag is a
deprecated no-op retained for backwards compatibility.

**Trust boundary:** local steps run arbitrary shell on the host — the same
posture as a Makefile. Only run process files you trust.

**Stack:** Bash 4+ (also tested on 3.2), jq. No daemons, no background
processes, no blocking sleeps.

### 5.2 Process file format (local)

The local engine accepts:
- The full wrapped format (`opensop: "0.6"`, `process: {...}`) — same as the server.
- The flat shorthand format: `{ "name", "inputs", "steps" }` (no version key, no `process` wrapper).

Files use the `.sop.json` extension. YAML files are not parsed locally (the CLI's
`schema validate` subcommand handles YAML validation, but `run` in local mode requires JSON).

### 5.3 Step dispatch (local engine)

The `_local_step_loop` function dispatches on step type:

| Type | Local behavior |
|---|---|
| `automated` | Runs `run:` as a bash script. Context JSON on stdin + `$OSL_CONTEXT`. Non-JSON stdout → `{stdout: "..."}`. Script path resolved relative to process file. |
| `shell` | Runs `run:` via `bash -c`. Same env as `automated`. |
| `noop` | Returns `{}` immediately. |
| `form` | Pauses run. Appends `{status:"waiting", reason:"waiting_for_input"}` to `audit.jsonl`. Returns `"waiting:<index>"`. |
| `approval` | Pauses run. Appends `{status:"waiting", reason:"waiting_for_approval"}` to `audit.jsonl`. Returns `"waiting:<index>"`. |
| anything else | Sets `rc=2`, fails step with "unsupported step type for local execution: \<type\>". Run fails unless `continue_on_error: true`. |

The `executor` field (see §6) is resolved to a default value for audit recording but
does NOT change dispatch behavior.

### 5.4 Run directory artifacts

Every local run creates `$OPENSOP_LOCAL_HOME/runs/<run_id>/`:

| File | Description |
|---|---|
| `manifest.json` | Run state. Rewritten atomically (temp + mv) after every state transition. |
| `audit.jsonl` | Append-only receipt log. One JSON line per step event. Never overwritten. |
| `context.json` | Live checkpoint of accumulated step outputs. Rewritten atomically after every completed step. Resume reads this to re-enter without re-running completed work. |
| `<step-id>.stderr.log` | Temporary stderr capture; folded into the audit receipt at step end, then deleted. |

`OPENSOP_LOCAL_HOME` defaults to the active cell's `.opensop/` when cwd is inside
a cell; otherwise `~/.opensop-local`. An explicit env var always wins.

### 5.5 manifest.json schema

```json
{
  "run_id": "20260610T090000Z-1234-56789",
  "process": "lead-qualification",
  "process_file": "/absolute/path/to/lead-qualification.sop.json",
  "started_at": "2026-06-10T09:00:00Z",
  "status": "running",
  "inputs": { "lead_name": "Alice", "lead_email": "alice@example.com" },

  "ended_at": "...",       // present when status is completed|failed|interrupted

  "cursor": {              // present while status is waiting
    "next_index": 2        // 0-based index of the FIRST step to run on resume
  },

  "waiting": {             // present while status is waiting
    "step": "collect",     // step id of the paused step
    "index": 1,            // 0-based index of the paused step
    "reason": "waiting_for_input",
    "expects": {
      "outputs": ["email", "opt_in"],
      "schema": [...]      // full inputs array for validation
    },
    "since": "2026-06-10T09:00:01Z"
  }
}
```

**`manifest.status` state machine:**

```
running → completed   (all steps finished)
        → failed      (step failed without continue_on_error)
        → waiting     (form/approval/other pause step encountered)
        → interrupted (process killed mid-run; set by EXIT trap)

waiting → running     (local_submit called; cleared before re-entering loop)
        → completed   (via local_submit → _local_step_loop)
        → failed      (via local_submit → _local_step_loop)
        → waiting     (another pause encountered during resume)
```

**`cursor.next_index`** is the 0-based index of the **first step to run on resume**
(the step immediately after the paused step). `waiting.index` holds the paused
step's own index. `local_submit` reads `cursor.next_index` and passes it directly
to `_local_step_loop` as `start_index`.

### 5.6 audit.jsonl receipt schema

Each line is a JSON object:

```json
{
  "run_id": "...",
  "step": "collect",
  "type": "form",
  "executor": "internal",
  "status": "waiting",            // completed | failed | waiting
  "exit_code": 0,                 // present when status is completed|failed
  "started_at": "...",
  "ended_at": "...",              // present when status is completed|failed
  "output": { ... },              // present when status is completed|failed
  "stderr": "...",                // present only when non-empty
  "decided_by": "human:alice"     // present when --decided-by passed to submit
}
```

The waiting receipt (for form/approval) omits `exit_code`, `ended_at`, and `output`.
The completion receipt added by `local_submit` always includes `exit_code: 0`.

### 5.7 Pause and resume protocol

**Pause (local_run encounters a form/approval step):**

1. `_local_step_loop` appends a `"waiting"` receipt to `audit.jsonl` and returns `"waiting:<i>"`.
2. `local_run` writes `manifest.status = "waiting"` with `cursor` and `waiting` blocks.
3. The CLI exits 0 (a clean pause is not a failure).

**Resume (`opensop submit <run_id> <step-id>`):**

1. `local_submit` reads `manifest.json`; asserts `status == "waiting"` and `waiting.step == <step-id>`.
2. Validates submitted outputs against `waiting.expects.schema` (required, type, enum).
3. Injects outputs into `context.json` under the step id.
4. Appends a `"completed"` receipt to `audit.jsonl` (with `decided_by` when `--decided-by` is passed). The type field in this receipt is derived from the process file's step definition, not hardcoded.
5. Flips manifest to `status = "running"`, clears `waiting` and `cursor`.
6. Re-enters `_local_step_loop` at `cursor.next_index` — **never** re-runs steps at a lower index.
7. On another pause: writes a new `waiting` block. On completion/failure: finalizes manifest with `ended_at`.

---

## 6. The `executor` Field

```yaml
steps:
  - id: verify
    type: automated
    executor: external    # optional; internal | external
```

**`executor` is audit metadata only.** It is never used to branch dispatch logic.
Omitting it is fine; the engine derives a default for the audit receipt based on
step type.

**Default values (per type):**

| Type | Default executor |
|---|---|
| `automated`, `shell`, `webhook` | `external` |
| `noop`, `form`, `approval`, `notification`, `wait`, `judgment` | `internal` |
| anything else | `external` |

**Allowed values:** `internal` | `external`. Any other value is rejected at parse
time with a `parse_error` before any steps run.

The server runtime does not yet read `executor` from the definition; the
field is declared in the YAML spec for forward compatibility with audit tooling
that wants to know where a step's work happens.

---

## 7. The Cell Substrate

### 7.1 What a cell is

A cell is any directory containing `.opensop/manifest.yaml`. Cells nest — a cell
may declare a parent cell. The cell chain (active cell + ancestors) provides
a name resolution scope for local process files.

`.opensop/manifest.yaml` schema:

```yaml
name: my-project
parent: ../parent-cell    # relative or absolute path; or "null" for a root cell
```

### 7.2 Cell commands

| Command | Description |
|---|---|
| `opensop init [--name N] [--parent P]` | Create `.opensop/` in cwd. Parent auto-detected from ancestor walk if not given. |
| `opensop scope` | Print the active cell + ancestor chain (nearest first). Fails when cwd is not inside any cell. |
| `opensop annotate <skill> <type> <json>` | Append a policy event to the skill's lineage history in the active cell. |
| `opensop lineage <skill>` | Print a skill's lineage entry (status, metadata, history). |
| `opensop fork <name> [--from <cell>]` | Copy an ancestor cell's skill (`.sop.json`) into the active cell and record `forked_from` snapshot. |

### 7.3 Name resolution

When `opensop run <name>` is called with a bare name (not a file path) in local
mode (the default):

1. Walk up from cwd to find the active cell root.
2. Check `<cell-root>/processes/<name>.sop.json`.
3. Walk ancestor chain (nearest first), check same path.
4. First match wins. Error if none found.

This is nearest-wins resolution, analogous to `$PATH`.

`opensop list` enumerates the full chain with cell name tags.
`opensop list --conflicts` marks shadowed entries (later in chain, same
filename as an earlier entry).

### 7.4 `OPENSOP_LOCAL_HOME`

When cwd is inside a cell and `OPENSOP_LOCAL_HOME` is not set explicitly, it
defaults to `<active-cell-root>/.opensop/`. Explicit env var always wins. Run
directories (§5.4) land under `$OPENSOP_LOCAL_HOME/runs/`.

### 7.5 Lineage schema

`<cell-root>/.opensop/lineage.json` is a JSON object keyed by skill logical name:

```json
{
  "lead-qualification": {
    "logical_name": "lead-qualification",
    "forked_from": {
      "cell": "/abs/path/to/parent",
      "forked_at": "2026-06-10T09:00:00Z",
      "snapshot": { "status": "", "metadata": {} }
    },
    "history": [
      { "at": "2026-06-10T09:01:00Z", "type": "promote", "data": { "to": "m2" } }
    ],
    "status": "active",
    "metadata": {}
  }
}
```

The substrate stores; policies (external) populate via `annotate` and read via
`lineage`. The substrate does not interpret `status` or `metadata`.

---

## 8. The Agent Interface

### 8.1 Agent workflow against the server API

The complete HTTP API is documented in §4.2. The typical agent loop against a
server instance:

1. `GET /sop/` — discover what processes are available.
2. `GET /sop/<name>/schema` — read the full process definition before starting.
3. `POST /sop/<name>/start` — start an instance with the required inputs.
4. `GET /sop/<name>/<id>` — poll for state. When a step is `active` with
   `sub_state=waiting_for_input` (or `waiting_for_approval`, `escalated`), the
   instance is waiting for a submission.
5. `POST /sop/<name>/<id>/steps/<step_id>/submit` — supply the step's outputs to
   advance the instance.
6. Repeat 4–5 until `instance.state` is `completed`, `failed`, or `cancelled`.

### 8.2 CLI agent integration

Agents can use the CLI (`cli/bin/opensop`) to drive OpenSOP without hand-writing HTTP.

Local execution (default — no server required):

```bash
opensop list                                          # discover local processes
opensop suggest "qualify a new inbound lead"          # intent-based lookup
opensop run ./lead-qualification.sop.json \
  --input lead_name="Alice" \
  --input lead_email="alice@example.com" \
  --input source=website
opensop show <run_id>
opensop submit <run_id> collect --output assigned_to="rep-bob"
```

Remote execution (opt-in — requires a configured server):

```bash
opensop --remote list                                 # discover server processes
opensop --remote schema lead-qualification            # inspect full definition
opensop --remote run lead-qualification \
  --input lead_name="Alice" \
  --input lead_email="alice@example.com" \
  --input source=website
opensop --remote status <instance-id>
opensop --remote submit <instance-id> collect \
  --output assigned_to="rep-bob"
```

### 8.3 The `.well-known/opensop` convention (roadmapped)

Long-term: `GET https://api.example.com/.well-known/opensop` → process catalog.
Makes any company running OpenSOP discoverable without prior configuration, the
same way `.well-known/openid-configuration` works for OIDC.

---

## 9. Process Status Model

### 9.1 Purpose

`opensop ps` (local and remote) and any observability view need a stable,
canonical vocabulary for the state of a *process definition* — distinct from
the state of any individual run *instance* (§4.3). This section defines that
vocabulary. It is the contract that A1 (`opensop ps`) and G1 (server status
API) implement against.

### 9.2 Process-level states

A process has exactly one of these states at any moment:

| State | Meaning |
|---|---|
| `open` | Declared and available on-demand; no active scheduler is watching it. Starts when called explicitly (`opensop run`, `POST /sop/:name/start`, or a webhook trigger). A process with a trigger configured but no active scheduler is also `open` (see derivation rules below). |
| `scheduled` | A trigger is configured **and** an active scheduler will fire it. For the server: the Rails dispatcher is running and an enabled schedule row exists. For local: the `opensop serve` daemon (A3, reserved for v0.7.x) is active and watching the process. |
| `running` | One or more instances are currently active (state `running` per §4.3). A process can be both `scheduled` and `running` simultaneously; when displaying, `running` takes precedence as the visible state. |

A process with an `interval` or cron trigger declared in its definition but **no active scheduler** must be reported as `open`, not `scheduled`. Implementations may surface the configured trigger as an informational field (e.g. `"configured_trigger": "interval"` / `null`) alongside the `open` state so that tooling can distinguish "open with no trigger" from "open with a trigger pending a scheduler."

**State derivation rules (local, `opensop ps`):**

1. Read all run manifests under `$OPENSOP_LOCAL_HOME/runs/` for this process.
2. If any manifest has `status ∈ {running, waiting}` → state is `running`.
3. Else if `opensop serve` (A3) is active and the process declares a trigger → state is `scheduled`.
4. Else → state is `open` (even if a trigger is declared in the process file).

**State derivation rules (server, `GET /sop/processes/status`):**

Reserved for v0.7.x — lands with G1 (the server observability terminal). The
endpoint shape is specified in §9.4 below; the implementation is not yet shipped.

### 9.3 Rollup fields

Every process entry in `opensop ps` output and in the server status response
carries these rollup fields, derived from run history:

| Field | Type | Description |
|---|---|---|
| `last_status` | `ok \| error \| never` | Result of the most recent run that reached `completed` or `failed`. `ok` = latest such run was `completed`; `error` = latest such run was `failed`; `never` = no `completed`/`failed` run exists. Runs in `cancelled` or `interrupted` state are **skipped** — they are neither success nor failure — so a cancelled latest run does not change `last_status`. |
| `last_run_at` | ISO 8601 UTC or `null` | Timestamp of the most recently started run, regardless of outcome. `null` when no run exists. |
| `next_run_at` | ISO 8601 UTC or `null` | When the next trigger fires. Non-null only when state is `scheduled` and the active scheduler can provide the value. `null` for `open` and `running` processes, and for any process whose trigger is configured but whose scheduler is not active. |

**Local derivation:** scan all `manifest.json` files for this process under
`$OPENSOP_LOCAL_HOME/runs/`. The most recent `started_at` is `last_run_at`.
`last_status` is derived from the `status` field of the manifest with the
latest `ended_at` whose status is `completed` or `failed` (manifests in
`running`/`waiting`/`interrupted`/`cancelled` state are skipped). Server
derivation applies the same rule to instance state.
`next_run_at` is always `null` in the local engine until A3 (the local
scheduler daemon) ships; until then, a process with a trigger declared is
still reported as `open` with `next_run_at: null`.

**Server derivation:** from `sop_instances`. An enabled schedule row in the
server's dispatcher is what promotes a process to `scheduled`; a trigger
declared in the process file alone is not sufficient. `next_run_at` is
populated by the dispatcher when the process is `scheduled`. See §9.4.

### 9.4 `GET /sop/processes/status` — process status rollup

**Reserved for v0.7.x — not yet implemented. The shape below is the contract;
implementation lands with G1.**

Returns one entry per registered process with its current state and rollup
fields. Intended for `opensop ps --remote` and the server observability view.

**Response — 200 OK (shape)**

```json
{
  "processes": [
    {
      "name": "lead-qualification",
      "version": "1.0",
      "state": "open",
      "last_status": "ok",
      "last_run_at": "2026-08-05T10:00:00Z",
      "next_run_at": null,
      "active_instances": 0
    }
  ]
}
```

| Field | Type | Description |
|---|---|---|
| `name` | string | Process name |
| `version` | string | Latest registered version |
| `state` | `open \| scheduled \| running` | Per §9.2 |
| `last_status` | `ok \| error \| never` | Per §9.3 |
| `last_run_at` | ISO 8601 UTC or `null` | Per §9.3 |
| `next_run_at` | ISO 8601 UTC or `null` | Per §9.3 |
| `active_instances` | number | Count of instances in `running` state |

Authentication: `X-SOP-Token` required (same as all `/sop/*` endpoints).

### 9.5 `opensop ps` — local process status

**Reserved for v0.7.x — not yet implemented (A1).** The description below is
the intended contract; the command does not exist in the current CLI.

`opensop ps` will surface the process status model locally without requiring a
server. `opensop ps --remote` will delegate to `GET /sop/processes/status` on
the configured server.

Intended output columns (tabular, `--json` for machine-readable):

```
NAME                  STATE      LAST STATUS   LAST RUN              NEXT RUN
lead-qualification    open       ok            2026-08-05T10:00:00Z  -
nightly-report        open       never         -                     -
invoice-intake        running    ok            2026-08-05T11:30:00Z  -
```

The column semantics map 1-to-1 with the fields in §9.3. `nightly-report` is
shown as `open` even if it declares an interval trigger, because no local
scheduler (A3) is active.

---

## 10. Reliability Metrics Contract

### 10.1 Purpose

Each run produces a receipt. This section defines the additional per-run fields
that every conforming implementation must capture to support reproducibility
comparison and cost visibility. These fields extend the existing local run
receipt (§5.6, `audit.jsonl`) and are already present in the reference server's
`sop_llm_calls` table (the Rails `Sop::LlmCall` model captures `model`,
`input_tokens`, `output_tokens`, `duration_ms`).

### 10.2 Per-run captured fields

The following fields must be written into each completed step receipt in
`audit.jsonl` (local) and into the server's step event records (server):

| Field | Type | Source | Description |
|---|---|---|---|
| `duration_ms` | integer | wall clock | Elapsed time in milliseconds from step start to step end, inclusive of retries. |
| `model` | string or `null` | step definition | Model identifier used for `llm` steps (e.g. `claude-haiku-4-5`). `null` for non-LLM steps. |
| `tokens_in` | integer or `null` | LLM provider response | Input tokens consumed by this step. `null` for non-LLM steps. |
| `tokens_out` | integer or `null` | LLM provider response | Output tokens produced by this step. `null` for non-LLM steps. |
| `token_source` | string or `null` | computed | For `llm` steps: `"api"` when the provider returned a `usage` block, or `"chars"` when tokens were approximated from output length (stub path or absent usage). `null` for non-LLM steps. |
| `result_hash` | string or `null` | computed | SHA-256 of the **compact, sorted-key** canonicalization of the step's `output` — exactly the bytes of `jq -Sc . <<< "$output"` **with no trailing newline** (as when captured in `$(...)` and piped via `printf '%s'`), through a portable hasher (`sha256sum` → `shasum -a 256` → `openssl`). A fast same/different reproducibility signal; **field-level** comparison uses the `output` object directly (already in the receipt). Value is the 64-char hex digest, or `"unavailable"` when no hasher exists, or `"pending"` for a step paused before producing output. `null`/absent on pre-v0.7 receipts. |

**Local receipt schema extension (adds to §5.6):**

```json
{
  "run_id": "...",
  "step": "score-lead",
  "type": "llm",
  "executor": "external",
  "status": "completed",
  "exit_code": 0,
  "started_at": "2026-08-05T10:00:00Z",
  "ended_at":   "2026-08-05T10:00:03Z",
  "output": { "score": 8, "rationale": "Strong fit." },
  "duration_ms": 2847,
  "model": "claude-haiku-4-5",
  "tokens_in": 312,
  "tokens_out": 47,
  "token_source": "api",
  "result_hash": "9f2b1c0e5a7d3f48b6c1e0a9d2f4b7c8e1a0d3f6b9c2e5a8d1f4b7c0e3a6d9f2"
}
```

**Optionality:** `tokens_in`, `tokens_out`, `token_source`, and `model` are
present only for `llm` steps. `duration_ms` and `result_hash` are present on
every **ordinarily-executed** step event (automated/shell/llm/noop), on every
**waiting** event (`result_hash: "pending"`), and on every **resumed-completion**
event written by `local_submit`.

**Append-only audit semantics (§5.6):** `audit.jsonl` is never mutated. A step
that pauses writes a **waiting** event carrying `duration_ms` (start → pause) and
`result_hash: "pending"`. This is shipped for `form`/`approval`/`wait.until`,
`subprocess` (waiting-for-callback), and webhook `callback` mode. When the step
later resumes, `local_submit` appends a *separate* **completed** event carrying
`duration_ms` (time the submission processing took) and `result_hash` (the real
SHA-256 digest of the submitted output using the same byte contract as §10.5).
The `"pending"` value on the waiting event is permanent — no event is edited or
back-patched. Any reader that wants the final digest reads the completed event.

**`duration_ms` on the resumed-completion event** is the wall-clock milliseconds
to process the submission — from `local_submit` entry (immediately after the
mandatory usage/argument guard) through argument parsing, payload construction,
schema validation, process-file and context loading, output normalisation, and
context merge — up to (but not including) the receipt's own serialisation and
append. The timer starts before any of this work begins; the value is computed
immediately before the completed receipt is constructed, so it necessarily cannot
include the write of the receipt that carries it (`audit.jsonl` append).
This is complementary to the pre-pause `duration_ms` already in the waiting
event; analysis tools may sum both segments for total active time across a pause.

**Note:** this is a CLI-local receipt contract. A server implementation
tracks step timing separately in `sop_llm_calls` and step records; the exact
server-side API for resumed-completion metrics is part of the observability
terminal (G1/A2, reserved for v0.7.x).

**result_hash and PII:** `result_hash` is a digest, not the data, so it exposes
no personal data. The `output` object it hashes is written verbatim (not a
sanitized copy); redaction of output/input fields is a separate concern
addressed in §11.4 (fault-record redaction).

### 10.3 Manifest-level run summary

The run-level `manifest.json` (§5.5) carries a top-level `duration_ms` for
completed, failed, and waiting runs. For a run that finishes without pausing
this is total wall time. For a run that **pauses and resumes**, `local_submit`
recomputes `duration_ms` when the run reaches a terminal state (`completed` or
`failed`) as total wall time from run start to the moment `local_submit`
finalizes the run — full end-to-end elapsed time regardless of how long the
run was paused.

**Precision:** `local_run` writes a `started_at_ms` field (millisecond-epoch
integer) into `manifest.json` alongside the second-granular ISO `started_at`
string. `local_submit` uses `started_at_ms` when present to avoid the 0–999 ms
rounding error that `fromdateiso8601` introduces. For manifests written by older
CLI versions that lack `started_at_ms`, `local_submit` falls back to parsing
`started_at`. If both fields are absent or unparsable, `duration_ms` is written
as `null` rather than an absurd epoch-0–derived value.

```json
{ "run_id": "...", "process": "lead-qualification", "status": "completed",
  "started_at": "...", "started_at_ms": 1754352000123, "ended_at": "...", "duration_ms": 4210 }
```

**Reserved for v0.7.x (not yet implemented):** an aggregated `metrics` block —
`{ total_tokens_in, total_tokens_out, llm_step_count }` summed across the run's
`llm` steps — lands with `opensop bench` (C1b). Until then, consumers that need
per-run token totals aggregate them from the per-step `tokens_in`/`tokens_out`
fields (§10.2). Do not rely on a `manifest.metrics` object on current receipts.

### 10.4 Server — no new columns required

The Rails reference server already captures `model`, `input_tokens`,
`output_tokens`, and timing in `sop_llm_calls`. Conforming servers must expose
these fields on the instance event stream once §10 is implemented. The exact
server API for querying per-run metrics is reserved for v0.7.x — it lands with
the observability terminal (G1/A2).

### 10.5 Reproducibility comparison

The `result_hash` field (§10.2) enables the benchmark harness (`opensop bench`,
C1b) to detect whether two runs of the same process produced the same output
without loading and diffing full JSON blobs. It is a portable SHA-256 of the
**compact, sorted-key** canonicalization of the step's `output`.

A conforming implementation must compute `result_hash` as the SHA-256 hex
digest of the exact bytes produced by `jq -Sc . <<< "$output_json"` **with no
trailing newline** — i.e. capture that value in a command substitution (which
strips the trailing newline) and hash it via `printf '%s' "$canon" | sha256sum`
(falling back to `shasum -a 256` or `openssl dgst -sha256` if `sha256sum` is
absent). Two conforming implementations must produce identical digests for the
same output, so the exact byte sequence (compact, sorted keys, no trailing
newline) is normative. An implementation that cannot invoke any hasher writes
`"unavailable"`.

**Field-level comparison** uses the `output` object directly — it is already
stored verbatim in the receipt. `result_hash` is a fast same/different signal
only; drill into `output` for field-by-field diffing:

```bash
# Compare two runs of the same process field-by-field
jq -S .output run_a/audit.jsonl | diff - <(jq -S .output run_b/audit.jsonl)
```

---

## 11. Security Model

### 11.1 No telemetry

**OpenSOP collects no telemetry.** The CLI (`cli/bin/opensop`) never phones
home. The spec defines no analytics endpoints. No run data, process definitions,
inputs, outputs, or usage patterns are sent anywhere by the engine itself.
Users control where their data goes — it stays on their machine (local mode) or
on their self-hosted server (remote mode).

### 11.2 Shell-step trust boundary

The `shell` and `automated` step types execute arbitrary code on the host:

- `shell` runs `bash -c <run>` with the process context on stdin.
- `automated` runs an external script (any language, any interpreter).

**This is the same trust posture as a Makefile.** Only run process files you
trust. A malicious `.sop.json` can exfiltrate environment variables, read
filesystem paths the user can access, or make network calls. The local engine
imposes no sandbox.

**Mitigations a conforming implementation should apply:**

| Control | Description |
|---|---|
| Path restriction | Resolve `automated` script paths relative to the process file's directory (and its parent). Reject absolute paths pointing outside the cell root. |
| Environment hygiene | The engine must not inject the `OPENSOP_API_TOKEN` or any server credential into the subprocess environment. Step context is passed via `OSL_CONTEXT` and stdin only. |
| No implicit network | `shell`/`automated` steps do not receive network credentials by default; any outbound call is the script author's responsibility. |

**The server profile does not expose `shell` steps.** The `shell` step type is
local-only. A conforming server must reject process definitions that declare
`type: shell`.

### 11.3 Secrets in a `serve`/daemon context

When `opensop serve` (A3) runs as a daemon or scheduled process:

- Secrets must be supplied via environment variables, not embedded in process
  files. The `${env.SECRET_NAME}` interpolation in webhook URLs and headers
  (§3.10) is the intended pattern.
- Daemon process files (`.sop.json`) must not store secret values. A
  conforming implementation should warn at parse time if a field value matches
  common secret patterns (e.g. a token-like string in a literal field value,
  rather than in an `${env.*}` reference).
- The `OPENSOP_API_TOKEN` environment variable controls access to the server's
  `/sop/*` API. It must be set in any network-accessible deployment. See §4.2
  (Authentication) for the fail-closed behavior when this variable is unset.

### 11.4 Fault-record redaction

Fault records (produced when a step fails, used by `opensop heal`) may contain
step inputs and partial outputs. These can include PII (e.g. names, emails) if
the process operates on personal data.

**Rules for fault records:**

1. Fault records are local files and must not be pushed to version control.
   Conforming implementations should include `**/fault.json` and
   `.opensop/faults/` in `.gitignore` templates.
2. Before a fault record is shared externally (e.g. via a future
   `opensop heal --share`), a conforming implementation must provide a
   redaction mechanism. The **field-level annotations that drive redaction**
   (e.g. marking a process input as personal data, or declaring a `format`)
   are **not yet part of the §2.2 process schema** — they are specified in
   v0.7.x together with the fault/heal work (D2). Until then, treat entire
   fault records as sensitive.
3. Until the redaction mechanism ships, the implementation must warn the user
   before writing a fault record that contains input data, and keep such
   records local (rule 1).

### 11.5 Stream and API authentication

When a server exposes a streaming endpoint (e.g. SSE for live instance events):

- The stream endpoint must require the same `X-SOP-Token` authentication as
  all other `/sop/*` endpoints.
- The server must not expose instance inputs or step outputs on an
  unauthenticated stream channel.

**Reserved for v0.7.x:** the specific SSE endpoint shape (`GET
/sop/instances/stream`) lands with G1/A2. The authentication requirement stated
here applies to any conforming implementation that exposes a stream.

### 11.6 What is out of scope for this spec

The following are security properties of specific implementations, not of the
spec itself:

- Transport security (TLS). Use a reverse proxy or your platform's ingress.
- Secret management (vault, secrets manager, `.env` files). The spec uses
  `${env.X}` as the reference mechanism; how those env vars get populated is
  outside the spec.
- Input sanitization beyond schema type-checking. Process definitions declare
  field types (§2.4); implementors should apply appropriate escaping when
  rendering inputs into prompts or shell commands.
- Rate limiting and DDoS protection on the `/sop/*` API.

### 11.7 Execution-trace provenance

A harness execution trace (`schemas/execution-event-*.json`) is evidence, not
narration. This section states the one rule that keeps it honest.

Provenance describes how a fact was established, never who established it. An event or field MUST NOT be labeled `observed` unless the fact it asserts — including any cross-reference to another event — was mechanically witnessed at the time it occurred; a value or link reconstructed after the fact is `inferred` regardless of the emitter's authority, and MUST carry `inferred_by` and `inference_basis`. When a reconstructed value cannot be stated with its basis, omit it: an absent field is honest evidence of a gap; a wrong label is a forgery of certainty.

An emitter with stronger first-party standing than the process it is reconstructing from — for example a harness that spawned the subprocess whose transcript it is now parsing — does not get a lighter labeling rule. Custody over how a fact was obtained can make a reconstruction more *reliable*; it cannot make the reconstruction stop being a reconstruction. That distinction is recorded in `inference_basis`, never by upgrading the label.

**The three labels:**

| Label | Meaning |
|---|---|
| `observed` | Captured mechanically, with zero agent cooperation and no opportunity for the agent to shade it. |
| `declared` | Asserted by the agent itself, in real time — contemporaneous, but true only insofar as the agent is honest and complete. |
| `inferred` | Reconstructed after the fact by an adapter or harness from something else; the weakest of the three, and MUST carry `inferred_by` + `inference_basis`. |

**Per-field overrides.** An event's top-level `provenance` is the label its own envelope facts carry. A single field may have been established differently than the rest of the event — most often a cross-reference or derived value bound by adapter-side inference inside an otherwise mechanically-observed event. `field_provenance` is a sparse object, keyed by field name, that overrides the label for just that field:

```json
"field_provenance": {
  "patch": { "provenance": "inferred",
             "inferred_by": "codex-adapter/0.5",
             "inference_basis": "ordinal-window adjacency" }
}
```

A field absent from `field_provenance` inherits the event-level label. Overrides run in both directions: a field on an otherwise-`observed` event may be `inferred` (an adapter-bound cross-reference inside a mechanically-captured event), and, symmetrically, a field may carry a stronger label than the event's own — a single override never raises the *event* above its event-level label, only the one fact it names.

**Conformance.** A conformance checker MUST take, as an event's effective provenance for any fact it relies on, the weakest label touching that fact — the weaker of the event-level `provenance` and any `field_provenance` override that names it — and MUST report accordingly rather than defaulting to the event-level label alone. `adapters/conformance.py` is the reference checker.

Normative shape: `schemas/execution-event-0.5.json`. Background and the reference evidence-requirement mechanism this feeds: `adapters/EVIDENCE-CONTRACT.md`, `adapters/conformance.py`.

---

## 12. Roadmapped Features

Features listed here are defined in this spec but not yet implemented in either
profile. The server parser rejects them unless noted.

| Feature | Roadmap note |
|---|---|
| `subprocess` fan-out (`fan_out:` modifier) | Phase 4 |
| `post_review:` process hook | Phase 5 |
| Inter-instance shared state (`shared_state_writes:`, `instance.shared_state.<key>`) | Phase 5 |
| `trigger.type: schedule` (cron) | Reserved for v0.7.x — lands with A3; parser rejects today |
| `trigger.type: interval` scheduler consumption | Reserved for v0.7.x — lands with A3; parser stores `interval_seconds` but no scheduler runs yet |
| `trigger.at: [...]` (multi-time daily) | Reserved for v0.7.x — lands with A3; parser rejects today |
| Webhook `response_mode: poll` | Not yet implemented; executor raises StepFailure |
| Subprocess actual child instance creation | Currently stubbed |
| Notification actual delivery | Currently stubbed |
| `judgment` LLM router | Currently stubbed; all judgments escalate to human |
| `async: true` on steps | Deferred to v0.3 |
| Template `extends:` | Deferred to v0.3 |
| `GET /sop/processes/status` server rollup | Reserved for v0.7.x — lands with G1 (§9.4) |
| Instance stream / SSE (`GET /sop/instances/stream`) | Reserved for v0.7.x — lands with G1/A2 (§11.5) |
| Fault semantics + `opensop heal` | Reserved for v0.7.x — lands with D2 (§11.4) |
| Run-level metrics API (server) | Reserved for v0.7.x — lands with G1/A2 (§10.4) |
| `opensop ps` — local process status command | Reserved for v0.7.x — not yet implemented (A1); spec shape in §9.5 |
| `opensop serve` — local scheduler daemon | Reserved for v0.7.x — not yet implemented (A3); required before local processes report `scheduled` state |

---

## 13. Examples

All examples use generic placeholders. No real credentials, no real PII.

### 13.1 Minimal local process

```json
{
  "name": "greet",
  "inputs": { "name": "World" },
  "steps": [
    { "id": "say-hello", "type": "shell", "run": "jq -r '\"Hello, \" + .name' <(cat)" }
  ]
}
```

Run: `opensop run ./greet.sop.json --input name=Alice`

### 13.2 Form pause and resume

```json
{
  "name": "collect-contact",
  "steps": [
    { "id": "intro", "type": "shell", "run": "echo starting" },
    {
      "id": "collect",
      "type": "form",
      "inputs": [
        { "name": "email", "type": "string", "required": true },
        { "name": "opt_in", "type": "boolean", "required": false }
      ]
    },
    { "id": "confirm", "type": "shell",
      "run": "jq -r '\"Got: \" + .collect.email' <(cat)" }
  ]
}
```

```bash
# Start — pauses at collect
opensop run ./collect-contact.sop.json --json
# → { "status": "waiting", "waiting": { "step": "collect", ... } }

# Resume
opensop submit <run_id> collect \
  --output email=alice@example.com \
  --output opt_in=true
# → { "status": "completed" }
```

### 13.3 Server process with LLM + webhook

```yaml
opensop: "0.7"

process:
  name: lead-intake
  version: "1.0"
  description: "Score an inbound lead and notify the CRM"

  inputs:
    - { name: lead_name,  type: string, required: true }
    - { name: lead_email, type: string, format: email, required: true }
    - { name: source,     type: enum,   values: [website, referral, cold], required: true }

  steps:
    - id: score
      type: llm
      model: claude-haiku-4-5
      prompt: |
        Score this lead 1-10.
        Name: {{ lead_name }}
        Source: {{ source }}
      expected_output_schema:
        score: number
        rationale: string
      outputs:
        - { name: score, type: number }
        - { name: rationale, type: string }

    - id: notify-crm
      type: webhook
      webhook:
        method: POST
        url: "${env.CRM_URL}/leads"
        headers:
          Authorization: "Bearer ${env.CRM_API_KEY}"
        response_mode: sync
      inputs:
        - { name: score, from: steps.score.outputs.score }
        - { name: lead_name, from: process.inputs.lead_name }
      outputs:
        - { name: crm_lead_id, type: string }
```

---

## Appendix A — Version history

| Version | Key additions |
|---|---|
| 0.1 | Initial spec: process model, 8 step types, instance lifecycle, API surface, server data model |
| 0.2 | `llm` step, `tools:`, collection outputs, `exit_when:`, `loop:` step, interval trigger (parser-only), `post_review:` hook (roadmapped), shared state (roadmapped), `validation:` on `automated` |
| 0.6 | Local execution backend (genuine local execution, no server), `.sop.json` flat format, run-dir artifacts (manifest/audit/context), pause/resume state machine, cell substrate (init/scope/annotate/lineage/fork), `shell` and `noop` local-only step types, `executor` audit field, `--conflicts` for list |
| 0.7 | Process status model (§9): canonical process states (`open`/`scheduled`/`running`) and rollup fields (`last_status`, `last_run_at`, `next_run_at`). Reliability metrics contract (§10): per-step `duration_ms`, `model`, `tokens_in`, `tokens_out`, `result_hash`, `token_source` in run receipts; top-level manifest `duration_ms`; resumed-completion `duration_ms` + `result_hash` on completed events written by `local_submit` (C1a follow-up); `duration_ms` + `result_hash:"pending"` on subprocess and webhook-callback waiting events (C1a follow-up); manifest total-duration-on-resume recomputed as full wall time from run start (C1a follow-up); the aggregated `metrics` block is reserved for v0.7.x. Security model (§11): no-telemetry statement, shell-step trust boundary, daemon secrets posture, fault-record redaction rules, stream auth requirement. Stream protocol, self-heal semantics, scheduler-trigger promotion, and server metrics API reserved for v0.7.x. `/sop/*` HTTP contract unchanged. |
| 0.7.x (additive) | Optional `recipe` object (§2.8), a Process field: `recipe.source` (canonical origin), `recipe.install` (one-line install hint), `recipe.tags` (discovery tags). Distribution metadata only — ignored by the execution engine, additive and non-breaking; ignored by v0.7.x-capable parsers (older strict parsers may not recognize it — a known compatibility boundary). No HTTP API change. No CLI parsing required for MVP (later slice). |
| 0.7.x (rename) | `recipe` object renamed to `sop` (§2.8): `sop.source`, `sop.install`, `sop.tags`, same semantics as the fields above. `recipe` is retained as a deprecated alias — conforming parsers MUST still accept it, and `sop` wins if both are present. Distribution metadata only, still ignored by the execution engine. Non-breaking. No HTTP API change. |
| 0.7.x (additive) | Optional `effects` field (§3.2), a Step field: a plain string describing what the step does to the world (e.g. `"publishes a post to LinkedIn"`). Presence, not content, is the signal that a step is irreversible and must not be silently auto-retried. Additive and non-breaking; process-level effects are derived (union of step `effects`), not a separate stored field. Enforced by the CLI's `opensop heal --apply`, which refuses to re-run a step declaring `effects` unless `--force-effects` is passed. No HTTP API change. |
| 0.7.x (additive) | Four optional agent-work Process fields (§2.9), all additive, non-breaking, and ignored by the execution engine: `evidence` (§2.9.1) — declares event-type and field-level evidence a trace of this process's execution MUST contain for a conformance claim about it to be checkable, from a closed vocabulary keyed to `schemas/execution-event-0.5.json`; checked post-hoc by a separate conformance checker (reference implementation: `adapters/conformance.py`, design doc: `adapters/EVIDENCE-CONTRACT.md`), never by the engine; absence is vacuous conformance, stated explicitly, mirroring how `effects`' absence is treated. `agent_contract` (§2.9.2) — declares the closed two-kind (`planner`/`worker`) role, scope ownership, spawn permission, and lateral-communication boundary of the agent executing this process; mints no further roles. Enforcement is optional and external to the engine, but a harness that elects to enforce a declaration it cannot back MUST refuse the run rather than execute it unenforced; and `lateral_communication: forbidden` MUST NOT be reported as verified from a trace, since a trace can show a spawn tree well-formed but never show a side channel absent. No enforcement *mechanism* is specified — that mapping belongs to a harness and its backend, not to this format. `prompt` (§2.9.3) — a versioned reference (`id` + `version`) to the prompt given to that agent, never the prompt text itself; the actual composed prompt is recorded, at execution time, in `session_started.effective_prompt` (`schemas/execution-event-0.5.json`). `isolation` (§2.9.4) — advisory declaration of the execution substrate (e.g. `repository: independent-checkout`) a conforming runtime should provide; not enforced by the local engine. No HTTP API change. No CLI parsing required for MVP. |
| 0.7.x (additive) | §11.7 execution-trace provenance principle (provenance describes how a fact was established, never who established it) plus execution-event schema 0.5's `field_provenance` sparse per-field override map. Execution-event schemas (`schemas/execution-event-*.json`) version independently of this process-format spec version. Additive and non-breaking: `field_provenance` is optional on every event; existing 0.4-shaped events remain valid. No HTTP API change. |

## Appendix B — Flat vs. wrapped envelope quick reference

```
FLAT (local shorthand):                     WRAPPED (server / YAML):
{                                           opensop: "0.7"
  "name": "greet",                          process:
  "inputs": {},                               name: greet
  "steps": [...]                              version: "1.0"
}                                             inputs: [...]
                                              steps: [...]
```

The local engine reads both. The server requires the wrapped form for registration.
`opensop schema validate` checks the wrapped form only.
