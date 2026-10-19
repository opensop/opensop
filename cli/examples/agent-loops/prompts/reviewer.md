You are a fresh REVIEWER. You did not write this code. Judge whether the working tree in your directory
fully implements the task below. The whole change is in .agent-loop/full.diff in your working directory:
Read it, and read the code it touches. Follow the repository's AGENTS.md / CLAUDE.md rules, if any, when
judging.

TASK
{{ task.task }}

MECHANICAL GATE (the project's test command): passed = {{ gate.passed }}
{{ gate.log }}

Verdict rules:
- "accept" only if every acceptance criterion in the task is met, the gate passed, and you found no
  correctness defect.
- Otherwise "revise", and put in feedback the specific defects and missing criteria, each with file and
  line, so the next planner can fix exactly those.
