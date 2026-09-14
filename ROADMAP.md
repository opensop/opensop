# OpenSOP roadmap

OpenSOP is Process as Infrastructure for agentic processes. The CLI (v0.9.0) is local-first: `opensop run/list/search` execute locally against `.sop.json` with no server; remote is opt-in via `--remote`. The spec is at v0.8. This roadmap keeps the public repo honest about what ships next.

## Shipped

- SPEC 0.8 — agent-work Process fields (`evidence`, `agent_contract`, `prompt`, `isolation`) and trace provenance, plus bare-form `opensop schema validate`
- CLI 0.9.0 — local-first execution against `.sop.json`, `--remote` opt-in
- `sops/` — a library of example SOPs to fork and run

## Next — harness graduation gates

An experimental execution-event harness exists as scaffolding, not wired into the CLI. It ships as a separate companion, not inside `cli/`, and only once it earns graduation:

1. The event schema unchanged across two consecutive milestones.
2. The delta list worked off, and a second trial clean.
3. The adapter survives a real vendor CLI version bump, with ingest failing loudly rather than degrading into a thin trace that still looks authoritative.
4. An explicit packaging decision.
