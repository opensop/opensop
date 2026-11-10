# Security Policy

OpenSOP is an open standard for processes as files, plus a local CLI that runs them. Processes run scripts on your machine, drive coding-agent CLIs with chosen permissions, evaluate conditions, and call external systems — so security bugs in the CLI or ambiguities in the spec can have real blast radius. We take vulnerability reports seriously.

## Reporting a vulnerability

**Please do NOT open a public issue for security reports.**

Use one of these channels, in order of preference:

1. **GitHub private vulnerability reporting** (preferred) — open [a private report](https://github.com/opensop/opensop/security/advisories/new) (Security tab → "Report a vulnerability"). This keeps the report private and gives us an audit trail.
2. **Email** — `abkuri88@gmail.com` with subject prefix `[OpenSOP security]`. PGP key available on request.

A good report includes:

- Affected version (commit SHA or tag).
- A clear description of the vulnerability and its impact.
- Reproduction steps — the simpler, the better. A failing test or a minimal `.sop.json` is gold.
- Any suggested fix or mitigation, if you have one.

## Response timeline

We aim for:

- **Acknowledgement** within 72 hours.
- **Initial assessment** (severity, scope, reproduction confirmed) within 7 days.
- **Fix or mitigation** for high-severity issues within 30 days. Lower-severity issues land on the next release cycle.

If a report is out of scope (e.g. social engineering, physical attacks, denial-of-service via brute compute), we'll tell you why and close the advisory.

## Scope

This repo is the spec and the CLI. It ships no server.

In scope (this repo):

- `cli/bin/opensop` — the local execution backend: shell step execution, local file access, `run:` path resolution, subprocess depth enforcement, and how `llm` CLI providers map `permission` onto each agent CLI's sandbox.
- `cli/install.sh` and `opensop upgrade` — download and checksum verification.
- `SPEC.md` — the format and API contract: ambiguities or underspecified behavior that would lead a conforming implementation to be insecure.
- Sandbox / privilege boundaries between user-supplied `.sop.json` process definitions and the host environment (local CLI execution).

Out of scope:

- Server implementations of the SPEC §4 profile, including their authentication (`X-SOP-Token`) and deployment. Report those to whoever runs the server.
- The intended trust boundary: a `.sop.json` you choose to run executes its `shell`/`automated` steps on your machine, like a `Makefile`. Running an untrusted process file is not a vulnerability in OpenSOP.
- Vulnerabilities in third-party tools the CLI calls (`jq`, `curl`, agent CLIs) — please report those upstream.
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
| Latest `v0.10.x` tag | ✅ |
| Older `v0.x` tags | ❌ — please upgrade |

Once 1.0 ships we'll expand this matrix to include the previous minor.

## Hall of fame

Reporters who find verified vulnerabilities will be credited here unless they prefer otherwise.
