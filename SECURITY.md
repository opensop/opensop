# Security Policy

OpenSOP is an open standard and runtime that exposes business processes as APIs. Processes run automated scripts, evaluate conditions, and call external systems — so security bugs in the engine can have real blast radius. We take vulnerability reports seriously.

## Reporting a vulnerability

**Please do NOT open a public issue for security reports.**

Use one of these channels, in order of preference:

1. **GitHub Security Advisory** (preferred) — go to the [Security tab](https://github.com/opensop/opensop/security/advisories/new) and click "Report a vulnerability." This keeps the report private and gives us an audit trail.
2. **Email** — `abkuri88@gmail.com` with subject prefix `[OpenSOP security]`. PGP key available on request.

A good report includes:

- Affected version (commit SHA or tag).
- A clear description of the vulnerability and its impact.
- Reproduction steps — the simpler, the better. A failing spec is gold.
- Any suggested fix or mitigation, if you have one.

## Response timeline

We aim for:

- **Acknowledgement** within 72 hours.
- **Initial assessment** (severity, scope, reproduction confirmed) within 7 days.
- **Fix or mitigation** for high-severity issues within 30 days. Lower-severity issues land on the next release cycle.

If a report is out of scope (e.g. social engineering, physical attacks, denial-of-service via brute compute), we'll tell you why and close the advisory.

## Scope

This repo is the spec and the CLI. Server/runtime security belongs in the reference server repo.

In scope (this repo):

- `cli/bin/opensop` — the local execution backend: shell step execution, local file access, `run:` path resolution, subprocess depth enforcement.
- `SPEC.md` — the format and API contract: ambiguities or underspecified behavior that would lead a conforming implementation to be insecure.
- Sandbox / privilege boundaries between user-supplied `.sop.json` process definitions and the host environment (local CLI execution).

Out of scope — this repo ships no server, so these belong to whoever implements the server profile:

- The Rails server engine — parsing, instance execution, step executors, REST API, admin UI.
- Authentication and authorization (`X-SOP-Token`, basic auth on `/ui`).
- Default server deployment configuration (`Dockerfile`, `bin/deploy`, `config/`).
- Issues that require the attacker to already have valid `X-SOP-Token` AND admin credentials.
- Vulnerabilities in third-party gems — please report those upstream. We'll bump the dep once a fix is published.
- Issues only reachable in a custom downstream fork's private processes.

## Disclosure

We follow coordinated disclosure:

1. We work with the reporter to confirm and fix the issue privately.
2. Once a patched release is out, we publish the advisory with credit to the reporter (unless they prefer anonymity).
3. We backport fixes to supported versions where reasonable.

## Supported versions

OpenSOP is pre-1.0. The following are supported for security fixes:

| Version | Supported |
|---|---|
| `main` | ✅ |
| Latest `v0.2.x` tag | ✅ |
| Older `v0.x` tags | ❌ — please upgrade |

Once 1.0 ships we'll expand this matrix to include the previous minor.

## Hall of fame

Reporters who find verified vulnerabilities will be credited here unless they prefer otherwise.
