# OpenSOP — Claude Code Project Guide

This repo is the **OpenSOP standard**: the specification ([`SPEC.md`](./SPEC.md)), the manifesto ([`MANIFESTO.md`](./MANIFESTO.md)), and the local-first CLI ([`cli/`](./cli/)). The spec also defines an optional server profile (§4); there is no maintained reference server — the profile is specified for anyone who wants to implement it.

---

## What lives here

| Path | What it is |
|---|---|
| `SPEC.md` | The OpenSOP 0.9.1 specification — the process format and local-first CLI contract; also defines an optional server profile (§4) any conforming server must implement |
| `MANIFESTO.md` | The thesis: why processes are infrastructure |
| `cli/` | The local-first CLI (`bin/opensop`, single bash file) |
| `cli/CLAUDE.md` | CLI-specific conventions — start here for CLI work |
| `docs/` | User-facing docs: `AGENTS.md` (consolidated agent guide) |
| `CONTRIBUTING.md` | PR workflow + private process library guidance |

---

## CLI work

All CLI work starts in `cli/`. Read `cli/CLAUDE.md` before touching `cli/bin/opensop`. Key points:

- `cli/bin/opensop` is a single bash file (~1600 lines). No build step. The file is the binary.
- Test gate: `bash -n cli/bin/opensop && bash cli/test/test.sh` — run this before committing.
- Local is the default backend (v0.9.1+). `--remote`/`--server` routes to a server's `/sop/*` API.
- When you add or change a subcommand, update `cmd_help`, `README.md`'s subcommand table, and `cli/CHANGELOG.md` in the same commit.

---

## Spec work

`SPEC.md` is the contract shared between this repo and any conforming server. There is no maintained reference server, so spec changes are not gated on a second repo:

1. Open an issue or PR here describing the spec change and its rationale.
2. If the CLI implements the changed behavior locally, update the CLI in the same PR or immediately following.
3. If the change touches the **server profile** (§4, and the stream/auth requirements in §11.5), say so explicitly in the PR. Nobody implements that profile today, so the spec is the only place the decision is recorded — an unstated change there is invisible until someone tries to build against it.

The `/sop/*` endpoint surface defined in `SPEC.md` §4.2 is the sole API contract. Don't let README, docs, or CLI help text describe endpoints or semantics that differ from the spec.

---

## How change ships

Non-trivial changes follow this loop:

1. **Branch off `main`.** Never commit to `main` directly. Branch naming: `feature/...`, `fix/...`, `chore/...`, `docs/...`.
2. **Implement** the change. For CLI work, follow the improvement loop in `cli/CLAUDE.md`. For spec work, follow the coordination steps above.
3. **Self-rate 1–10** across: correctness, simplicity, test coverage, naming, spec fidelity (does it match `SPEC.md`?), public-repo hygiene (no PII, no secrets, no internal identifiers). If any axis is below 7, name the gap and fix it.
4. **Open a PR** via `gh pr create`. PR description must include: what changed and why (1–3 bullets), self-rating scores, improvement applied or follow-up deferred, test plan.

Trivial changes (typos, copy edits, single-line config fixes, comment-only) can go directly.

---

## Public-repo hygiene (non-negotiable)

This repo is public. Every keystroke is potentially indexed and read by strangers.

Never commit:

| Category | Examples |
|---|---|
| PII | Real names, emails, phone numbers, postal addresses |
| Secrets | API keys, tokens, passwords, signed URLs, private endpoints |
| Internal identifiers | Customer/company names from non-public contexts, internal team names, `*.internal` URLs |
| Tool output | Logs with any of the above, stack traces with internal hostnames |

Use generic placeholders in examples: `alice@example.com`, `Acme Corp`, `https://api.example.com/v1`, `sk-...REDACTED...`. When in doubt, redact.

---

## Core principles

- **Simplicity first.** Minimal-impact changes, no speculative abstractions.
- **Root causes, not workarounds.** Fix the underlying issue; no temporary patches.
- **Verify before claiming done.** Run tests; never assert green without proof.
- **Plan before building.** For multi-step work, write the plan first. If it goes sideways, replan rather than push through.
- **Spec is the source of truth.** If the CLI, docs, or README disagree with `SPEC.md`, fix the discrepancy — don't paper over it.
