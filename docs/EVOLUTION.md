# EVOLUTION.md — Mineralization Policy for OpenSOP

> **Design note, not shipped.** There is no `opensop evolve` command and the `m`-tier fields are not in the SPEC; what ships today is `opensop annotate` / `lineage` / `fork` (SPEC §7).

**Status: experimental.** The `m`-tier metadata fields and the `opensop evolve` command are not yet frozen in the SPEC.

---

A skill running in a cell is never done. It starts as prose, grows a structure, and — one step at a time — converts LLM judgment calls into deterministic code. Each conversion lowers cost and raises reliability. This document defines the rules for moving a skill forward, when to pull it back, what fork semantics apply, and how the CLI substrate records it all.

The lineage/annotate/fork substrate this policy builds on is defined in `SPEC.md §7` (The Cell Substrate) — §7.2 the commands, §7.5 the `.opensop/lineage.json` schema. What is *experimental* here is only the mineralization **policy** layered on top: the `m`-tier values, the transition thresholds, and the not-yet-shipped `opensop evolve` command.

**How current state is derived.** `opensop annotate` is append-only — it adds an event to `history[]` and does **not** mutate the entry's top-level `status`/`metadata`. So **history is canonical**, with each field carried forward independently: the current **tier** is the `to` of the most recent event that carries one, and the current **status** is the `status` of the most recent event that carries one (each persists until a later event overrides it). This is why not every payload needs to repeat both fields. Maintaining the derived top-level `status`/`metadata.m` fields is the job of the (experimental, unshipped) `opensop evolve` writer; until it ships, derive from history with the `jq` snippet in the CLI Substrate section below.

---

## Why harden

Two problems compound with scale:

1. **Token cost.** Every LLM call that could be a deterministic function wastes money on every run, forever.
2. **Model-churn debt.** When a model upgrades, every LLM-bounded step needs re-validation. Deterministic steps do not. Skills that never harden accumulate re-validation burden with each model generation.

Mineralization is the hedge: convert non-judgment steps to code, and the upgrade cost collapses toward zero.

---

## Tiers (m0–m6)

**Experimental field.** Record in `lineage.metadata.m` as a string — for example `"4.12"`.

| Tier | Name | What is deterministic | Typical token cost vs m0 | Target reliability |
|---|---|---|---|---|
| `m0` | Soft tissue | Nothing — pure prose instruction | 1.0x | base |
| `m1` | Scaffold | Nothing yet — but the skill is a typed OpenSOP process (steps declared, I/O typed) | ~0.9x | base + structure |
| `m2` | Early mineral | 1–2 non-judgment steps converted to `shell` or `automated` | ~0.7x | rising |
| `m3` | Mid mineral | ~half of non-judgment steps deterministic | ~0.5x | rising |
| `m4` | Late mineral | Most non-judgment steps deterministic; LLM steps are clearly bounded judgments | ~0.3x | high |
| `m5` | Pre-bone | All but the final judgment step(s) are deterministic | ~0.15x | very high |
| `m6` | Bone | All non-judgment steps deterministic; ≥1 bounded LLM judgment step remains by design | ~0.1x | ~0.98 |

**Notation: `m<tier>.<iteration>`**

- `tier` (0–6): the trust level.
- `iteration`: count of successful hardening or re-validation events at the current tier. Resets to `1` on each tier change.
- `m0.1` — first draft. `m4.12` — fourth tier, re-validated 12 times. `m6.247` — bone, re-validated 247 times.

The iteration suffix is what distinguishes a skill that just reached tier 3 (`m3.1`) from one that has been battle-tested there (`m3.89`). Both are at the same trust level; only the evidence record differs.

**Cell scope.** The `m` value is per-cell. A skill at `m5` in one cell is `m1` in another if that cell hasn't run it yet. Evidence does not propagate automatically across cells.

---

## Forward transitions (hardening)

Harden one step at a time. Bulk hardening is forbidden — it bypasses the evidence model.

| Transition | Fire when ALL conditions hold |
|---|---|
| `m0 → m1` | Pattern observed ≥3 times in 30 days in this cell · runs share recognizable structure · skill not marked `one_off: true` |
| `mN → mN+1` (1 ≤ N < 6) | ≥2 successful runs in this cell since the last hardening event · the candidate step produced identical output (modulo whitelisted variance) on the last 3 runs · step not flagged `requires_judgment: true` |
| `→ m6` | All non-judgment steps are deterministic. Stop hardening; only re-validate on model upgrades. |

Each event bumps the iteration counter. Crossing a tier resets it to `.1`.

**Record the transition:**

```bash
opensop annotate <skill> promote '{"from":"m3","to":"m4","step":"parse-output","reason":"identical output on last 3 runs"}'
```

`opensop lineage <skill>` shows the full event history.

---

## Reverse transitions (demotion)

Demotion targets a single step. The skill-level tier drops by one.

**Demote when ANY holds:**

- Step failed twice in a row.
- Schema validation failed once (not a retry — a retry is permitted; a structural failure is not).
- A model upgrade caused the step's output to drift outside whitelisted variance on a regression test. This applies only to LLM-bounded steps. Deterministic steps never need demotion on a model change — that is the point.
- Manual override flags the step broken.

**After demotion:**

- Log the cause.
- Hold ≥5 successful runs in this cell before the step is re-eligible for hardening.
- Demotion is per-cell. A step breaking in one cell does not automatically demote the same skill in a parent or sibling. Cross-cell demotion is always a manual pull.

**Record the demotion:**

```bash
opensop annotate <skill> demote '{"from":"m4","to":"m3","step":"parse-output","reason":"schema validation failed 2026-08-05"}'
```

---

## Fork semantics

When you instantiate a skill from an ancestor cell, the CLI copies the process file and snapshots the parent's policy state:

```bash
opensop fork <skill>                   # nearest ancestor cell
opensop fork <skill> --from /path/cell # specific cell
```

The child's live `status` and `metadata` start empty. `opensop fork` stores the parent's *top-level* `status`/`metadata` in `forked_from.snapshot` — but since `annotate` never populates those (history is canonical), that snapshot is usually empty. **Derive the parent's inherited tier from the source cell's history**, not the snapshot: run the `jq` helper (see CLI Substrate) against the source cell's `.opensop/lineage.json`, then record it in the `fork-inherit` event below. The snapshot becomes authoritative only once the experimental `opensop evolve` writer maintains the top-level fields.

**The Mineralization policy rule:** the child inherits the parent's `m` tier with `status: unverified`. The shape carries its sharpness; only its fit to this cell is untested.

| First event in the child cell | Result |
|---|---|
| Successful run | `status: unverified` → `status: mineralized`; iteration bumps (`m4.12` → `m4.13`) |
| Failed run | Standard demotion applies immediately; `status: fractured` |
| No run in 30 days | Remains `unverified`; appears on the watch list |

A first-run failure means the context doesn't match the shape — not that the shape is broken elsewhere. Do not auto-propagate the failure to the parent.

Apply the `unverified` status after a fork:

```bash
opensop annotate <skill> fork-inherit '{"m":"m4.12","status":"unverified","source_cell":"/path/to/source"}'
```

After the first successful run:

```bash
opensop annotate <skill> promote '{"from":"m4.12","to":"m4.13","status":"mineralized","reason":"first run verified"}'
```

If the first run instead **fails**, record the demotion carrying `status: fractured` (standard demotion applies; tier resets to `.1`):

```bash
opensop annotate <skill> demote '{"from":"m4.12","to":"m3.1","status":"fractured","reason":"first run in cell failed"}'
```

---

## CLI substrate

All policy state lives in `.opensop/lineage.json` in the active cell, keyed by `logical_name`. Do not hand-edit it.

| Command | What it does |
|---|---|
| `opensop annotate <skill> <event-type> '<json>'` | Append a policy event to the skill's history. This is the only path for *appending policy events* (`fork` also writes lineage, creating the child entry + `forked_from` snapshot). |
| `opensop lineage <skill>` | Print the full lineage entry: status, metadata, forked_from, history. |
| `opensop lineage <skill> --json` | Machine-readable. Pipe to `jq` for scripting. |
| `opensop fork <skill>` | Copy from nearest ancestor + snapshot parent state. Child starts empty; apply `fork-inherit` annotation to record the inherited tier. |
| `opensop fork <skill> --from /path/cell` | Copy from a specific non-ancestor cell. |

**Lineage entry shape (relevant fields):**

```json
{
  "logical_name": "extract-action-items",
  "status": "",
  "metadata": {},
  "forked_from": null,
  "history": [
    { "at": "2026-08-05T09:00:00Z", "type": "promote", "data": { "from": "m3.2", "to": "m4.1", "status": "mineralized" } },
    { "at": "2026-08-05T15:00:00Z", "type": "promote", "data": { "from": "m4.1", "to": "m4.13" } }
  ]
}
```

Note that the top-level `status` and `metadata` are **empty here** — `annotate` never wrote them (it only appends to `history[]`). The *derived* current state is **tier `m4.13`** (latest event carrying a `to`) and **status `mineralized`** (latest event carrying a `status`); the `jq` helper below computes exactly that. The top-level fields become a populated cache only once the experimental `opensop evolve` writer ships.

**`opensop evolve status` (experimental command — not yet shipped).** When implemented, it will maintain the derived top-level fields and print a tier table. Until it ships, derive the table from history yourself:

```bash
jq -r '
  to_entries[] | .key as $k | .value.history as $h
  | ($h | map(select(.data.to     // .data.m)) | last | (.data.to // .data.m) // "-") as $tier
  | ($h | map(select(.data.status))            | last | .data.status          // "-") as $status
  | [$k, $status, $tier] | @tsv
' .opensop/lineage.json | column -t
```

---

## Governance

**Archival (per cell):**

| Unused for | Action |
|---|---|
| 30 days | Watch list — log the idle skill, take no action |
| 90 days | Move to `.opensop/archive/` |

Auto-deletion is forbidden. All archives are recoverable.

**`blessed: true` in metadata:** no auto-modification, no auto-archival, demotion requires explicit human override. An `unverified` fork still auto-clears on first successful run even if the parent was blessed — the flag is about the cell's fit, not the shape's lock. Use `blessed` sparingly; overuse freezes the policy.

**Change cadence for this document:**

| Layer | Cadence | Trigger |
|---|---|---|
| Tier definitions and transition rules | Quarterly | Evidence that the thresholds are wrong |
| Substrate field shapes | With SPEC | A SPEC release that freezes them |
| The strategic frame (why harden at all) | Annual or on major model-generation shift | Requires human sign-off |

---

## Quick reference

```bash
# Record that a skill was just promoted from m2 to m3
opensop annotate extract-action-items promote \
  '{"from":"m2.5","to":"m3.1","step":"validate-json","reason":"identical output on 3 consecutive runs"}'

# Demote after a schema failure (tier change resets the iteration suffix to .1)
opensop annotate extract-action-items demote \
  '{"from":"m3.1","to":"m2.1","step":"validate-json","reason":"schema validation failed 2026-08-05"}'

# Fork into a new cell and record inherited tier
opensop fork extract-action-items --from /workspace/shared-cell
opensop annotate extract-action-items fork-inherit \
  '{"m":"m3.1","status":"unverified","source_cell":"/workspace/shared-cell"}'

# Confirm the first run passed — clear unverified
opensop annotate extract-action-items promote \
  '{"from":"m3.1","to":"m3.2","status":"mineralized","reason":"first run in cell verified"}'

# Inspect current state
opensop lineage extract-action-items
```
