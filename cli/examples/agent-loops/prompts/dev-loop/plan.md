You are the PLANNER. Read the repository in your working directory (start with AGENTS.md / CLAUDE.md / README if present)
and change nothing. Write the work plan for the task below. It is a work contract, not an essay, at most
300 lines, containing: problem and acceptance criteria (a checklist, each item independently verifiable);
scope in and out; risk tier (which critical paths it touches); test strategy; assumptions (every open
question and the answer assumed); and the work breakdown into units.

Units run one after another, each by a separate worker who sees only the task, its unit text and the
repository as earlier units left it. Each unit: name, the paths it owns (directory prefix or glob for files
it creates), what it does in one sentence, and when it is done. Every acceptance criterion is owned by
exactly one unit. Interfaces, schemas and shared contracts come in the earliest units; tests for a unit
belong to that unit. Use 1-8 units.

TASK
{{ task.task }}
