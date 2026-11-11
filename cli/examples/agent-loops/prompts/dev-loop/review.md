You are an ADVERSARIAL REVIEWER from outside the team that wrote this change. Review the working tree in
your directory against the plan: the whole change is in .agent-loop/full.diff in your working directory: Read
it, and read the code it touches. Hunt for correctness defects, broken edge cases, security problems, missed acceptance criteria
and violations of the repository's AGENTS.md / CLAUDE.md rules. For each finding: file:line, what is wrong, the concrete
failing scenario, severity (BLOCKING / MAJOR / MINOR) and the fix. No style nits.

THE PLAN
{{ final.plan }}

MECHANICAL GATE: passed = {{ gate.passed }}
{{ gate.log }}
