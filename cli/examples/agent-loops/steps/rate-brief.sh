#!/usr/bin/env bash
# rate-brief.sh: composes the rater's prompt.
#   cycle 0   a full rating: plan, gate result, adversarial review, the whole change.
#   cycle 1+  a DELTA judgment: the previous rating verbatim plus the fix diff, and
#             nothing about the gate, the finding counts or what was left open, so
#             the rater checks the fixes instead of re-litigating the first round.
set -euo pipefail
jq -c '
  def waiver: "A MAJOR may be waived only on one of three grounds, and you must name which: it falls in what the plan declared out of scope; it existed before this change and the change does not touch it; or it argues against an assumption or scope decision the plan records. Nothing on a critical path may be waived. In `blocking` and `major` count only findings that stand: unfixed and not waived. Never reclassify a BLOCKING as MAJOR.";
  if .loop.index == 0 then {brief: (
    "You are a fresh RATER. You did not write or review this change. Judge it against the plan'"'"'s acceptance criteria. The whole change is in .agent-loop/full.diff in your working directory: Read it, and read the code it touches. Score correctness, simplicity, test coverage, naming and spec fidelity 1-10 each (telemetry only; they gate nothing). Label every finding BLOCKING, MAJOR or MINOR with file:line and the concrete fix. Judge each adversarial-review finding too: confirm it, downgrade it, or reject it with a reason. A failed mechanical gate is a BLOCKING finding. " + waiver
    + "\n\nTHE PLAN\n" + .final.plan
    + "\n\nMECHANICAL GATE: passed = " + (.gate.passed | tostring) + "\n" + .gate.log
    + "\n\nADVERSARIAL REVIEW\n" + .review.findings)}
  else {brief: (
    "You are a fresh RATER doing a DELTA JUDGMENT of a fix round. Below is the previous rating, verbatim. The fix is in .agent-loop/delta.diff in your working directory (everything changed since that rating): Read it, and read the code it touches. For each prior BLOCKING and MAJOR finding, verify it was actually addressed; then flag anything the fix broke. Do not re-review code the fix did not touch. Label every finding that stands, prior or new, BLOCKING, MAJOR or MINOR with file:line and the concrete fix. " + waiver
    + "\n\nTHE PREVIOUS RATING\n" + .rate.findings)}
  end'
