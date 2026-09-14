# OpenSOP roadmap

OpenSOP is Process as Infrastructure for agentic processes. The CLI (v0.8.0) is local-first: `opensop run/list/search` execute locally against `.sop.json` with no server; remote is opt-in via `--remote`. The SPEC is at v0.6. This roadmap keeps the public repo honest about what ships next.

## Shipped

- YAML process parser (SPEC v0.6; accepts 0.1/0.2 for legacy)
- Instance executor with 10 step-type executors
- REST API under `/sop/`
- Admin UI (Hotwire + Tailwind + ViewComponent)
- RSpec coverage
- Real step execution for `form`, `automated`, `shell`, `noop`, `webhook`, `llm`, `loop`
- Modeled state transitions for `judgment`, `approval`, `subprocess`, and `wait`
- CLI v0.8.0 — local-first default, `--remote` opt-in, `--local` deprecated no-op

## Next

- Real outbound webhook delivery (HTTParty + ActiveJob background call)
- LLM-backed `judgment` steps with confidence thresholds and escalation
- Human approval UI for `approval` steps
- Real `subprocess` execution (child instance spawn + parent pause)
- Real `notification` delivery (email, Slack, SMS)
- Process metrics and run dashboards
- Example SOP library for common ops and engineering workflows
- More agent-harness examples: PR review, dependency bumping, CI re-runs, release notes

## Later

- Process Designer UI
- Version diff/replay UI
- Runtime adapters for other execution backends
- Hosted playground for trying OpenSOP without local setup
- Compatibility tooling for importing runbooks from Markdown, Notion, or Confluence

## Good first issues

- Improve error messages for invalid field references
- Add screenshots or GIFs to the README quickstart
- Document how to run OpenSOP behind a reverse proxy
- Add an example agent workflow that writes receipts without side effects
