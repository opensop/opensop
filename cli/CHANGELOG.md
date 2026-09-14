# Changelog

All notable changes to opensop-cli are documented here.

This project follows [Semantic Versioning](https://semver.org/) and the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

---

## [Unreleased]

## [0.9.1] — 2026-09-23

### Added

- **`heal --apply` refuses to re-run a step with declared `effects` (SPEC §3.2, additive v0.7.x).** A step can fail from the CLI's point of view while having already succeeded remotely (classic case: an HTTP request lands but the response times out) — blindly re-running it can double-post, double-send, or double-spend. Steps now carry an optional `effects` field: a plain string describing what the step does to the world (e.g. `"publishes a post to LinkedIn"`). Presence of the field, not its content, is the signal. `opensop heal <run_id> --apply` now refuses (exit non-zero, no re-run, no audit event) when the failed step declares `effects`, printing the declared string and the escape hatch. A new `--force-effects` flag permits the re-run explicitly; when used, the audit `heal` event's `note` records that an effectful step was knowingly re-run. Bare `heal` (diagnosis mode) no longer blandly recommends `--apply` for such a step — it surfaces the effects string and recommends `--apply --force-effects` instead, both in the printed "next steps" and in the `debug_prompt` baked into the fault record at failure time. Not an interactive prompt: agents have no TTY, so this is a refusal plus a documented flag. Steps without `effects` heal exactly as before (no regression). +cases in `test/test.sh`.

### Changed

- **`opensop pull` now addresses the `opensop/sops` library, not `opensop/opensop`.** The SOP library is moving out of the main repo into its own public repo, and recipes are now per-slug folders instead of flat files. `OPENSOP_RECIPES_BASE` now defaults to `https://raw.githubusercontent.com/opensop/sops`, and the fetch path drops the `recipes/` segment and adds a `<slug>/` folder: `${OPENSOP_RECIPES_BASE}/${ref}/${author}/${slug}/${slug}.sop.json` (was `.../recipes/${author}/${slug}.sop.json`). `OPENSOP_RECIPES_BASE` itself still overrides the base exactly as before — only the default value and the path shape under it changed. The example recipes that ship in this repo under `recipes/opensop/` moved from `recipes/opensop/<slug>.sop.json` to `recipes/opensop/<slug>/<slug>.sop.json` to match; they remain in-repo examples and CLI test fixtures, not the published library.
- **Vocabulary standardization: "recipe" → "SOP" everywhere, with deprecation paths for the two published surfaces.** The project is OpenSOP, the library is `github.com/opensop/sops`, and the artifact is an SOP — "recipe" was a second name for the same thing and is retired. The in-repo example directory moved from `recipes/` to `sops/` (`sops/opensop/<slug>/<slug>.sop.json`; `sops/README.md`); every doc, help string, and the embedded `SKILL.md` now say "SOP"/"SOPs" instead of "recipe"/"recipes". `opensop pull`, `opensop import`, and `opensop info` all read/print the renamed fields. No behavior change beyond wording — see Deprecated below for the two surfaces that needed a compatibility path instead of a silent rename.

### Deprecated

- **`OPENSOP_RECIPES_BASE` → `OPENSOP_SOPS_BASE`.** `OPENSOP_SOPS_BASE` is the current name for `opensop pull`'s base URL and takes precedence. `OPENSOP_RECIPES_BASE` is still honoured when `OPENSOP_SOPS_BASE` is unset, and now prints a one-line deprecation warning to stderr (stdout stays clean for `--json` consumers). The default base URL is unchanged: `https://raw.githubusercontent.com/opensop/sops`.
- **SPEC §2.8: the `recipe` object → `sop`.** The distribution-metadata object on a process (`source`/`install`/`tags`) is renamed `sop` (`sop.source`, `sop.install`, `sop.tags`); `recipe` is retained as a deprecated alias that conforming parsers MUST still accept. If a document declares both, `sop` wins. Still purely distribution metadata — ignored by the execution engine either way. `opensop info`, `opensop pull`'s summary output, and `opensop import` all resolve both spellings.

### Fixed

- **Subprocess parent auto-continuation (#107).** When a `subprocess` step's child run contains a form/approval/wait step, the parent run was left permanently in `waiting` state after the child completed — the parent never received the child's output and downstream steps never ran. Three changes fix this, plus three adversarial hardening fixes applied in follow-up review:
  - Child manifests now record `parent_run_id`, `parent_step_id`, and `parent_step_index` at creation time so the child knows how to walk back to its parent.
  - A new `_local_continue_parent` helper is called by `local_submit` whenever a run reaches a terminal state. It reads the parent linkage, merges the child's final `context.json` into the parent context under the subprocess step id, appends a `completed` audit receipt for the subprocess step, and re-enters `_local_step_loop` from the next step onward. On child failure it propagates a `failed` receipt and marks the parent `failed` without running downstream steps. Recursion handles nested subprocesses in both directions (completions and failures walk all the way up to the root — grandparent, great-grandparent, etc.).
  - `local_submit` calls `_local_continue_parent "$run_dir"` after finalizing a terminal run manifest.
  - **Failure cascade (#107 hardening 1):** the child-`failed` path and any resumed-parent-`failed` path now both recurse via `_local_continue_parent` so failure propagates to the top-level run at any nesting depth. Previously only the completed path cascaded; a grandchild failure left the grandparent permanently `waiting`.
  - **Durable idempotency (#107 hardening 2):** replaced the permanent `mkdir` lock with two-level locking: a short-lived concurrency lock dir (released on function RETURN via `trap`) and a durable completion marker file (`.sp-cont-<step>.done`) written only after ALL state is committed. A crash or failed `jq`/`mv` leaves no `.done`, so the next submit retries cleanly. The per-step precondition (parent still `waiting` at this step) guards against double receipt append on retry.
  - **Fail-closed on missing snapshot (#107 hardening 3):** `_local_continue_parent` now requires the parent's `process.snapshot.json`. If it is absent or unreadable the parent is failed with a clear audit receipt and the mutable `process_file` is never executed — eliminating a drift attack vector where deleting the snapshot and mutating the original file could cause the wrong definition to run on continuation.
  - **Checked writes (Fix A):** every required mutation in `_local_continue_parent` now checks its exit status (audit appends, manifest finalize, waiting-manifest rewrite, recursive cascade). On any write failure the function returns 1 without writing `.done`, so the next submit retries cleanly. Previously several paths ignored write failures and wrote `.done` anyway, leaving the parent permanently stranded on a disk-full or I/O error.
  - **Idempotent receipt append (Fix B):** before appending a `completed` or `failed` audit receipt for `parent_step_id`, `_local_continue_parent` checks whether a terminal receipt already exists in the parent's `audit.jsonl`. If one is found the append is skipped (but continuation proceeds normally). This prevents duplicate receipts on crash-retry when the receipt was written but the manifest flip was interrupted.
  - Durability boundary (documented, not changed): the `.done` marker + waiting-step guard provide normal-operation idempotency. A SIGKILL between the manifest flip and `.done` can leave a run in `running` state with no live worker. Recovery is the same as any other interrupted local run (re-submit or `opensop heal`). The local engine is best-effort — same posture as a Makefile. Full crash-consistency across all mutation points requires an engine-wide explicit resumable state machine and is out of scope here.
  - +29 assertions across 9 new test scenarios (original 5 + 3 hardening + 1 new U8c-4): end-to-end continuation, downstream propagation, multiple child pause cycles, idempotency, failure propagation, 3-level failure cascade (deepest child fails → top run fails), mid-level failure cascade, durable idempotency (no double receipts, no lock remnant), fail-closed on missing snapshot (sentinel never written), and idempotent receipt (pre-seeded receipt → exactly 1 terminal receipt after continuation).
  - **Cascade-retry-safe (Fix 1, #107).** When `_local_continue_parent` is re-entered for a child whose parent is already terminal (completed or failed) but `.done` is absent — the scenario where a grandparent cascade previously failed leaving a stranded grandparent — the function now detects the terminal parent via a new three-way precondition branch (Case B) and re-drives only the grandparent cascade, then writes `.done`. Previously the single-condition guard (`parent != waiting`) returned 0 immediately, permanently stranding the grandparent `waiting` after any transient write failure during the grandparent cascade. +5 assertions (U8c-5): 3-level chain completes, `.done` re-written on retry, grandparent re-driven from `waiting` to `completed`, no duplicate receipts at parent level.
  - **Fail-closed idempotent receipt (Fix 2, #107).** The missing-snapshot fail-closed branch now applies the same idempotent-receipt guard already used by the child-completed and child-failed paths before appending its `failed` receipt. Previously the append was unconditional, so a retry after a partial write (receipt written, manifest flip interrupted, no `.done`) would produce a duplicate `failed` receipt for the subprocess step. +3 assertions (U8c-6): fail-closed fires correctly, exactly 1 receipt on first invocation, exactly 1 receipt after idempotent retry.
  - **Recursion-safe explicit lock release (#107, structural fix).** `_local_continue_parent` previously released its concurrency lock via `trap ... RETURN`. Bash's RETURN trap is a single global string: a recursive call (Case B cascade or terminal cascade) overwrites the outer invocation's trap with the inner lock path — so the inner lock is released twice and the outer lock is never released. A leaked `.sp-cont-<step>.lock` directory causes every subsequent retry to silently return 0 (the `mkdir` guard fires), permanently stranding the cascade. The function is now split into a wrapper (`_local_continue_parent`) that acquires the lock, calls the body, and releases the lock explicitly with `rmdir` after the body returns — on both success and failure paths — and a body (`_local_continue_parent_body`) that does all the work. Recursion always goes through the wrapper so each ancestor level gets its own acquire/release cycle. No `trap ... RETURN` anywhere in this logic. +5 assertions (U8c-7): normal 3-level cascade leaves no lock dirs; stranded-GP retry via trampoline leaves no lock dirs; grandparent completes after retry.
  - **Distinguish lock contention from acquisition errors (#107).** `mkdir` lock failure no longer unconditionally returns success: expected contention (the lock dir already exists) stays a safe no-op, but a genuine acquisition error (permission / missing path / fs — the lock path is absent or occupied by a non-directory) now surfaces a warning and returns non-zero instead of silently leaving the parent `waiting`. (Concurrent-owner-fails recovery remains a best-effort-durability limitation tracked engine-wide in #109.) +2 assertions (U8c-8).

- **test(cli): make the upgrade BASH_SOURCE[0] test hermetic and effective (#104).** The section-(4) upgrade test previously invoked `"$cli" upgrade` directly (where `$cli` is the repo's own `cli/bin/opensop`). On a machine with network access and a valid published checksum, the upgrade could succeed and silently overwrite the working-tree binary with published `main`. Now the test runs a throwaway copy of the binary (the intended `BASH_SOURCE[0]`) and injects a stub `curl` that serves a controlled fixture binary + matching checksum from local temp files — no network, and the repo binary is never a candidate target. The upgrade is driven to a real success and the test asserts it replaced the throwaway copy (not the PATH decoy, not the repo binary), so a `command -v opensop` regression is actually caught.

- **Resumed runs are now drift-proof (#101) — heal and subprocess coverage extended.** Three adversarial gaps closed on top of the original fix:
  - *gap 1* — `heal --apply` now executes from the per-run `process.snapshot.json` (snapshot preferred over `manifest.process_file`); editing, reordering, or deleting the process file after a failure no longer changes what gets retried. Deleting the file no longer makes heal impossible. +3 regression tests (modify / reorder / delete-original scenarios).
  - *gap 2* — Subprocess child runs now snapshot the child definition to `process.snapshot.json` in the child run dir at creation time, and execute from that snapshot with the child's original directory as the `_local_step_loop` 5th-arg override. A paused child resumed via `local_submit` is now as drift-proof as a paused parent. Child manifest also records `process_dir`. +2 regression tests (modify-child-run: / reorder-child-steps while paused).
  - *gap 3* — `local_run` now records `process_dir` (the canonical absolute original process directory) in `manifest.json` at run creation. `local_submit` and `heal --apply` read it on resume so relative scripts (`steps/build.sh`) resolve correctly even if the original process file has been moved or deleted. Legacy manifests without `process_dir` derive it from `dirname(process_file)` without requiring the file to exist. +1 regression test (original file deleted; automated step with relative run: resolves and runs from snapshot).
  - Original fix: `local_run` snapshots the normalized process definition to `process.snapshot.json` at run creation. `local_submit` reads the step plan from that snapshot on every resume. +5 regression tests covering modify / insert / reorder / delete drift and multi-cycle pause/resume.

## [0.9.0] — 2026-08-12

### Fixed

- **Local `automated` steps now match SPEC §3.3 (#74).** (1) The script shebang is honored: an executable step script runs via its own interpreter (Ruby, Python, …) instead of being forced through `bash` — the repo's own `.rb` example steps (`processes/examples/steps/*.rb`) now run locally. Non-executable scripts still run via `bash` (backward compatible). (2) A step's declared `inputs[]` (`from:` references to `steps.<id>.outputs.<field>` or `process.inputs.<field>`) are now resolved and merged OVER the accumulated context before piping, so a script can read its declared input by name while scripts that reach into `.<step-id>.<output>` keep working unchanged. +3 regression tests.

### Added

- **7 new seed recipes** under `recipes/opensop/`: `lead-qualification`, `meeting-action-items`, `incident-postmortem`, `pr-review-gate`, `customer-onboarding`, `content-publish-approval`, `weekly-status-digest`. All pass `opensop dry-run` and use only safe step types (form, judgment, approval, llm, shell with echo/jq only).

- **Slice 4 — agent-adoption docs + embedded skill update (content-only, no new commands).**

  - **Embedded SKILL.md** (`_skill_embedded_content` in `bin/opensop`): updated to document
    the full command surface including `pull`, `import`, and `info` (added in Slice 3).
    Added a "Recipes / the library" section that explains how to discover, pull, and import
    shareable recipes, with a CRITICAL SAFETY note: pulled/imported recipes are untrusted
    code — read the `run` commands directly (dry-run previews the flow only, not command
    bodies) and get user confirmation before running.
    Updated `description` frontmatter to mention recipe pulling. Length kept near existing
    level (no bloat).

  - **`docs/AGENTS.md`**: added two new sections:
    - §11 "Adopt OpenSOP in your agent — AGENTS.md block": a copy-pasteable markdown
      snippet for users to drop into their project's `AGENTS.md` (or CLAUDE.md /
      .cursorrules / etc.) so any AGENTS.md-honoring runtime knows where SOPs live,
      how to discover/run/inspect/heal processes, how to author and onboard, how to
      pull/import recipes safely, and how to self-check with `opensop doctor`.
    - §12 "Runtime → skill path table": documents all supported runtimes and their
      canonical SKILL.md install paths (mirrors `opensop skill paths`), the one-command
      install (`opensop skill install --runtime <flavour>`), and a "Which mechanism?"
      note explaining SKILL.md vs. the AGENTS.md block and when to use each.

  - **`cli/README.md`**: updated the "Use with Claude Code" section to point to
    `docs/AGENTS.md` as the canonical agent guide (replacing the stale
    `docs/CLAUDE-INTEGRATION.md` pointer); added "Adopt OpenSOP in your agent runtime"
    with the `skill install` one-liner per flavour; added a "SOP library" subsection
    with `pull` / `info` / `dry-run` examples and the never-auto-run safety note.

- **Slice 3 — `opensop pull`, `opensop import`, `opensop info`: recipe sharing.**
  Anyone can now share and pull reusable `.sop.json` processes from the new
  in-repo SOP library (`recipes/`).

  - `opensop pull <author>/<slug>[@<ref>]` — download a recipe from the
    `recipes/<author>/<slug>.sop.json` path in the opensop GitHub repo.
    Defaults to `main`; accepts a branch name or immutable commit SHA for
    pinning (`opensop pull opensop/daily-standup-notes@a1b2c3d`). Writes to
    `./<slug>.sop.json` by default; `--output <path>` overrides. No-clobber
    without `--force`. Prints a summary (name, version, step count + types,
    source, sha256) and a "review before running" note. **Never executes the
    file.** `--verify <sha256>` enforces a hash the user supplies out-of-band
    for real integrity checking. Requires curl (gated in main()).
    Set `OPENSOP_RECIPES_BASE` to override the base URL (supports `file://`
    for offline testing).

  - `opensop import [<file>|-]` — read a recipe from a local file or stdin
    (`-`). Validates it parses as a process, writes to `./<name>.sop.json`
    (from the process name, sanitised) or `--output <path>`, no-clobber
    without `--force`. Prints the same summary; **never executes the file.**
    Fully local — no curl required.

  - `opensop info <file.sop.json>` — print a recipe's `recipe.*` metadata
    (source, install hint, tags) plus the process summary. Thin read-only
    wrapper; no curl, no writes.

  - Three seed recipes added under `recipes/opensop/`:
    - `daily-standup-notes` — form + shell: collect standup answers and
      format a Markdown summary.
    - `triage-bug-report` — form + judgment + shell: structured bug intake
      and prioritised triage summary.
    - `release-checklist` — approval + noop + shell: gated release checklist
      requiring explicit approval of each item before proceeding.

  All seed recipes are valid `.sop.json` files that pass `opensop dry-run`.
  They use only safe step types (form, judgment, approval, noop, shell with
  only echo/jq). They include the `recipe` object (`source`, `install`,
  `tags`) per SPEC §2.8.

  Safety contract (non-negotiable): both `pull` and `import` **write only**.
  Neither ever executes the recipe. The sha256 printed is for
  pinning/identification (file and hash share one GitHub origin — they
  confirm transfer integrity, not third-party authenticity).

  `OPENSOP_RECIPES_BASE` env var (new): overrides the base URL used by
  `opensop pull`. Default: `https://raw.githubusercontent.com/opensop/opensop`.
  Set to a `file://` URL pointing at a local directory tree with the same
  `<ref>/recipes/<author>/<slug>.sop.json` layout for offline testing.

- **Slice 2 — `opensop skill` and `opensop doctor`: agent runtime skill integration.**
  Any agent runtime that adopts OpenSOP as a SKILL.md skill (the cross-vendor Agent
  Skills standard) can now install and inspect the embedded skill in one command:

  - `opensop skill show` — print the embedded SKILL.md to stdout without writing
    anything to disk (useful for agents reading it programmatically).
  - `opensop skill install <dir>` — write the embedded SKILL.md to `<dir>/opensop/SKILL.md`
    (creates dirs as needed; `--force` to overwrite; `--json` for machine output).
  - `opensop skill install --runtime <flavour>` — resolve the canonical install path
    from the embedded flavour registry and install there.  Supports `--scope user|project`
    for runtimes that have both paths.  Registry: `claude` → `.claude/skills/opensop`;
    `codex`/`agentskills` → `.agents/skills/opensop`; `hermes` → `.hermes/skills/opensop`;
    `openclaw` → `skills/opensop`; `openhands` → `.openhands/skills/opensop`;
    `goose` → `~/.config/goose/skills/opensop`.  Rules-only runtimes (`cline`, `cursor`,
    `continue`, `aider`) print guidance to add an AGENTS.md/rules block instead (exit 0,
    no file written).  Unknown flavour → `usage_error` listing valid names.
  - `opensop skill paths [--json]` — print the full flavour→path registry (TTY table
    or JSON object).  This is the authoritative place an agent queries to learn where
    its runtime expects the skill file.
  - `opensop doctor [--json]` — self-check: opensop version + PATH resolution, jq
    presence, bash ≥4, and per-flavour skill installation status.  Exits non-zero only
    on a CRITICAL failure (jq missing or bash too old); missing skills are informational.

  The SKILL.md content is embedded as a heredoc inside `bin/opensop` itself —
  no sibling files are needed.  Single-file `curl` installs pick it up automatically.
  The embedded skill uses the Agent Skills 6-field portable subset (YAML frontmatter:
  `name`, `description`, `license`, `allowed-tools`, `metadata`, `compatibility`) and
  includes a SAFETY section covering the trust boundary around `.sop.json` shell steps.

- **C1a follow-up: reliability metrics on resumed steps.** Completes the deferred
  piece of §10 (SPEC v0.7). Three behaviors now ship:

  1. **Resumed-completion `duration_ms` + `result_hash`**: the **completed** event
     appended by `local_submit` now carries `duration_ms` (time from submit start
     to receipt write) and `result_hash` (SHA-256 of the canonical output, using
     the exact byte contract from C1a — same `_sha256` helper, same `jq -Sc` +
     `printf '%s'` no-trailing-newline pipeline). Result is reproducible: same
     submitted output → same 64-char hex digest across runs.

  2. **Manifest total duration on resume**: when `local_submit` brings a run to
     a terminal state (`completed` or `failed`), `manifest.duration_ms` is
     recomputed as total wall time from `manifest.started_at` (via jq's
     `fromdateiso8601`). Previously only the pre-pause segment was recorded.

  3. **Subprocess/callback waiting events**: `subprocess` (child-paused propagation)
     and webhook `callback` mode waiting events now carry `duration_ms` (start →
     pause) and `result_hash: "pending"` — matching the contract already shipped for
     `form`/`approval`/`wait.until` in C1a.

  SPEC §10.2 and §10.3 "reserved for v0.7.x" caveats removed; spec now matches
  the shipped CLI. Note: this is a CLI-local receipt contract; no Rails counterpart
  required (Rails tracks step timing separately in `sop_llm_calls`).

- **C2: `bench/demo/` — reproducible comparison video.** Graduates the C2 terminal
  recording from the `spike/c0-bench` branch onto main. The demo replays verified
  outputs from the 60-run benchmark (3 arms × 2 models × 10 runs) without making
  API calls. `bench/demo/demo.sh` is the driver; `make demo` re-renders the GIF and
  MP4 from scratch (requires `asciinema`, `agg`, `ffmpeg`). The pre-rendered
  `comparison.gif` (~406 KB) and `comparison.mp4` (~783 KB) are committed for
  offline viewing (demo media later pruned; regenerate via make demo in cli/bench/demo/). Honesty label: all outputs are recorded from real measured runs —
  not simulated. Full methodology: `bench/NUMBERS.md`. Added a "Demo" section to
  `cli/README.md` linking `bench/demo/`.
- **E1: `opensop onboard` — first-run experience.** Turns a process a user already runs into an
  OpenSOP process and proves the reliability gain.

  - **Step 1 (Orient + scaffold):** if no process file is given, writes a starter `my-process.sop.json`
    in cwd with a valid `opensop 0.6` structure (one `llm` step with `expected_output_schema`).
    Points the user at `docs/AGENTS.md §6` (openSOP-ize) for the *transformation* of an arbitrary
    prose skill — the bash CLI does not attempt to auto-convert arbitrary prompts.

  - **Step 2 (Validate):** runs `dry-run` on the process file (local_dry_run reuse; no new code
    path). Injects placeholder values for required inputs so validation checks *structure* (schema,
    step graph, format) rather than input presence. Reports inputs, step count, and step types.
    Exits non-zero with a clear message if validation fails — onboarding does not proceed on an
    invalid process.

  - **Step 3 (Compare):** invokes `opensop bench` (built-in extract-action-items task only)
    inside a subshell so bench's `die()`/`exit 1` never terminates onboard.
    `--stub` is forwarded for offline testing. When no API key is present, bench exits non-zero;
    onboard surfaces the key-missing message and continues gracefully (the comparison step is
    skipped, not fatal). `--json` embeds the full bench scoreboard in the summary.

  - **Step 4 (Next steps):** prints `run` / `show` / `fork` / `lineage` / `annotate` commands and
    pointers to `docs/AGENTS.md §6` and `EVOLUTION.md`.

  - **Side-effect safety:** onboard never executes the user's process. The comparison uses the
    bench's controlled task only (`bench/fixtures/`).

  - **`--json` summary shape:**
    ```json
    {
      "scaffolded": true|false,
      "process_file": "./path/to/file.sop.json",
      "validated": true|false,
      "bench_result_or_skipped": "completed"|"skipped",
      "bench_result": { ...bench scoreboard JSON... } | null
    }
    ```
    On validation failure: `{...,"validated":false,"bench_result_or_skipped":"skipped","error":"validation_failed"}`.

  - **Registry:** `onboard` registered in `_registry_raw` (category `onboarding`, backend `local`);
    wired in `main()` dispatch; help examples added; README subcommand table updated.

  - **Tests (18 new assertions in `test/test.sh`):** no-arg scaffold produces valid `.sop.json` +
    dry-run passes; invalid JSON exits non-zero with clear error; valid + `--stub --n 1 --json`
    produces parseable summary with `bench_result.arms`; no-key path exits 0 with
    `bench_result_or_skipped=skipped` (graceful, no hang); `--task <dir>` is rejected with
    `unknown_flag` (trust-boundary regression test).

### Security

- **Honest threat-model documentation; removed unshipped signing promise.**
  Added "Install verification & threat model" section to `cli/README.md` explaining
  exactly what SHA-256 checksum verification protects against (transfer corruption)
  and what it does not (a compromised source, since the binary and checksum share
  the same GitHub origin). Removed the promise "GPG signing is planned" from
  `install.sh`, `bin/opensop` (`cmd_upgrade`), and the README — we won't ship a
  promise we haven't implemented. The die-message and hint text in both tools now
  point to the README threat-model section instead. A note clarifying the
  same-origin limitation is added to the header comment of `install.sh` and to the
  Security block of the `cmd_upgrade` comment in `bin/opensop`.

- **E1 trust-boundary fix: removed `--task <dir>` from `opensop onboard`.**
  `onboard --task <dir>` forwarded an untrusted directory into `cmd_bench`, which sources
  `.env.local` and executes `shell`/`automated` steps from processes in that directory —
  arbitrary code execution on the host. This directly contradicted onboard's advertised
  side-effect-safety guarantee. Fix: `--task` is no longer accepted by `onboard`; the
  comparison step always runs against the built-in, immutable bench fixture
  (`cli/bench/`). Users who need to benchmark a custom task use `opensop bench <task>`
  directly — that command carries its own explicit trust posture. The `unknown_flag` error
  code is returned for any remaining `--task` usage.

- **Committed `bin/opensop.sha256`** so the default `curl … | bash` installer and
  `opensop upgrade` can verify downloads without `--allow-unverified`. The file
  contains the SHA-256 digest of `bin/opensop` in `sha256sum` two-field format
  (`<digest>  opensop`). Regenerate it with `make checksum` whenever `bin/opensop`
  changes; commit both files together. GPG/cosign release signing is tracked as a
  follow-up and is not yet implemented.

### Added

- **A2: `opensop watch` — live-refreshing terminal dashboard (SPEC §9).**
  A self-refreshing observability terminal for process status. Architecture
  decision: bash CLI feature, not a Rails web page; the server only provides data.

  - **Data derivation reuse:** extracts the §9.4 enumeration/rollup logic from
    `local_ps` into `_ps_collect_local_entries` (shared top-level helper), and the
    remote fetch from `cmd_ps` into `_ps_collect_remote_entries`. No SPEC §9 logic
    is duplicated — `cmd_watch` calls these same helpers.

  - **Redraw loop:** on each tick, clear + reprint (TTY guard: `is_tty` before
    calling `clear`; `{ clear 2>/dev/null || true; }` makes it TERM-safe). Interval
    defaults to 2s; `--interval N` sets an explicit positive-integer period.

  - **Header line (pretty mode):** each refresh prints `source: <local|URL>
    interval: Ns  <UTC timestamp>` above the process table so the dashboard is
    self-describing without scrolling back.

  - **`--json` mode:** emits compact NDJSON — one status array per refresh on
    its own line, no ANSI escapes, no clear. Safe to pipe to `jq -c .[]`.

  - **`--remote`:** delegates to `_ps_collect_remote_entries` →
    `GET /sop/processes/status` (G1 endpoint). Local is the default.

  - **Clean INT handling:** trap INT before the loop; in pretty mode print a
    trailing newline; in JSON mode emit nothing. No stray output in either mode.

  - **`--once` (hidden test hook):** run exactly one iteration and exit. Lets
    `test/test.sh` verify the output shape without delivering SIGINT from bash.

  - **Columns:** NAME · STATE (green running / blue scheduled / dim open) ·
    LAST STATUS (green ok / red error / dim never) · LAST RUN · NEXT RUN.
    Rendered by the shared `_ps_emit` helper.

  - **Registry:** registered in `_registry_raw` (category `inspection`,
    backend `dual`). Wired in `main()`. Help examples + README row + this
    CHANGELOG entry added in the same commit.

- **A1: `opensop ps` — process status view (SPEC §9).** Surfaces the §9 process
  status model locally without requiring a server.

  - **State derivation (local, §9.2):**
    - Discovers processes via the active cell chain (same path as `opensop list`).
    - For each process, scans `$OPENSOP_LOCAL_HOME/runs/*/manifest.json`.
    - `status = "running"` if any manifest has `status ∈ {running, waiting}`.
    - Otherwise `status = "open"`. `"scheduled"` is never emitted locally because
      `opensop serve` (A3) is not yet implemented — a process with a configured
      trigger remains `open` (per §9.2: "no active scheduler → open").

  - **Rollup fields (§9.3):**
    - `last_status` — `ok` if the manifest with the latest `ended_at` has
      `status == "completed"`; `error` if `"failed"`; `"never"` if no terminal
      run exists. Manifests in `running`, `waiting`, `cancelled`, or `interrupted`
      states are skipped (per §9.3).
    - `last_run_at` — most recent `started_at` across all manifests for the
      process; `null` when none exist.
    - `next_run_at` — always `null` locally until A3 ships.

  - **`--remote`:** fetches `GET /sop/processes/status` (G1 endpoint, shape §9.4)
    and renders the same table.

  - **`--follow`:** clear-and-reprint loop every 2s; Ctrl-C exits cleanly.
    No SSE or keyboard TUI — simple polling (per plan A1 spec).

  - **Output contract:** `--json` emits a compact JSON array matching the §9.4
    shape `[{name, status, last_status, last_run_at, next_run_at}]`. Pretty mode
    (TTY default) renders a five-column table: `NAME / STATE / LAST STATUS /
    LAST RUN / NEXT RUN`. Both paths honor `emit_pretty_or_json` / `OUTPUT_MODE`.

  - **Registry:** `ps` registered in `_registry_raw` as `category: inspection`,
    `backend: dual`.
- **D2: Fault records + `opensop heal` — faults and one closed heal loop (SPEC §11.4).**

  When a local step fails (without `continue_on_error`), the engine now writes a fault record
  to `$OPENSOP_LOCAL_HOME/runs/<run_id>/fault.json` and records the path in `manifest.json`
  under `fault_file`. The fault record contains: `run_id`, `faulted_at`, `process_file`,
  `step.id` + `step.type`, `exit_code`, `inputs` (the accumulated context at failure), `output`
  (the step's error output), and a machine-readable `debug_prompt` — an agent-actionable
  description of what failed, what inputs were received, and how to apply a fix.

  **Per SPEC §11.4:** fault records may contain process input data (PII risk). The engine warns
  the user on every fault write. Fault records are excluded from version control via `.gitignore`
  entries (`**/fault.json`, `.opensop/faults/`) in both `cli/` and the repo root. Do not push
  fault records.

  **`opensop heal <run_id>`** — diagnosis mode: print the fault record and `debug_prompt` for a
  failed run in human-readable form. `--json` emits the raw structured fault record (for agent
  consumption). Errors if the run is not failed, or if no fault file exists.

  **`opensop heal <run_id> --apply [--input k=v ...]`** — the one closed loop: re-run the
  previously-failed step using the current process definition and any caller-supplied input
  corrections, then continue the run from there. Before re-running:
  - Appends a `heal` event to `audit.jsonl` (fields: `event:"heal"`, `step`, `healed_at`, `note`).
  - If cwd is inside an OpenSOP cell, appends a `heal` annotation to the process's lineage entry.
  If the re-run succeeds, the run continues to completion (or the next pause). If the re-run fails
  again, a fresh fault record is written and the command exits non-zero. The label "self-healing"
  applies only to this `--apply` loop; `heal` without `--apply` is diagnosis only.

  Registry entry: category `execution`, backend `local`. Wired in `main()`.
- **C1b: `opensop bench` — 3-arm reliability comparison command.** Runs the
  honest comparison from the C0 spike as a shipped, productized subcommand.

  - **3 arms:** `skill` (naive prose prompt), `json_only` (same ask + JSON
    demand, no scope rule — isolates format from scope), `opensop` (runs
    `.sop.json` process via `opensop run`, gets schema-validation + retries).
    Exact prompts are in `cli/bench/prompts/`.
  - **Scoring:** reliability = schema-valid AND field-level match against
    `cli/bench/fixtures/expected.json`. Case-insensitive (owner, task) set
    equality via `jq -S`; order-independent. Reuses `cli/bench/measure/checker.sh`
    from the C0 spike. Prints schema-valid and field-match counts separately so
    the "format alone doesn't buy reliability" story is legible.
  - **Metrics per arm over N runs (default 10):** reliability (field_match/N),
    schema_valid count, median duration (ms), median output tokens. LLM output
    tokens read from C1a audit receipts for the opensop arm; character count for
    direct-call arms.
  - **No API key needed for offline self-test:** `opensop bench --stub` runs
    the full scoring path using hardcoded stub responses (no network calls,
    no key). Live runs require `ANTHROPIC_API_KEY`.
  - **Graceful fail when key missing:** exits non-zero with `config_missing`
    error and a clear message pointing to `--stub` and the env-var setup.
  - **`--json` output:** machine-readable scoreboard
    `{model, n_per_arm, stub, arms: [{arm, reliability, ...}], methodology}`.
  - **Built-in default task:** `cli/bench/fixtures/` (synthetic
    Alice/Bob/Carol/Dave meeting notes), `cli/bench/processes/`,
    `cli/bench/prompts/`, `cli/bench/schema/` — brought from the C0 spike
    verbatim (already placeholder-clean).
  - **Registered** in `_registry_raw` (category `bench`, backend `local`);
    wired in `main()` dispatch; help examples added; README subcommand table
    updated.

- **C1a: Reliability metrics in local run receipts.** Each executed step's audit entry carries:
  - `duration_ms` — wall-clock milliseconds for that step (via `date +%s%3N`; falls back to
    seconds×1000 on non-GNU date). Present even when a step fails. Steps that pause
    (`form`/`approval`/`wait.until`) record `duration_ms` to the pause and `result_hash:"pending"`.
  - `result_hash` — SHA-256 of the canonicalized step output (`jq -Sc .`) via a portable hasher
    (`sha256sum` → `shasum -a 256` → `openssl`; `"unavailable"` if none, never fatal under `set -e`).
    Stable across two runs with identical outputs; used by `diff` as the reproducibility signal.
  - *Known follow-up:* metrics on **resumed** steps (after `submit`) land in a later change; the
    non-interactive `automated`/`llm`/`shell` path (what `bench` relies on) is fully covered.
  - `model`, `tokens_in`, `tokens_out`, `token_source` — LLM-only fields. `token_source`
    is `"api"` when Anthropic's `usage` block is present, or `"chars"` (output char count)
    when the stub path is active or usage is absent.
  - `manifest.json` gains `duration_ms` (total run wall time) for completed, failed, and
    waiting runs.
  - `diff` updated: compares `result_hash` instead of `duration_ms` per step (duration is
    inherently variable; the hash is the correct reproducibility signal). Backward-compatible
    — existing receipts without these fields still diff cleanly (`null` == `null`).
- **Install/distribution (I1).**

  - `cli/install.sh` — curl-pipe installer.  Detects bash version (warns with
    `brew install bash` steps on macOS 3.2), verifies `jq` is present, and installs
    the single-file binary to `~/.local/bin` by default (or any `--prefix`-given
    directory).  Idempotent: re-running replaces the binary in-place.  A specific
    release can be pinned with `--version X.Y.Z`.  Prints a `$PATH` hint when the
    install directory is not yet on the user's path.
    Platform matrix: **Linux** — full support; **macOS** — full support with bash 4+
    (`brew install bash`; macOS ships bash 3.2 which is not supported); **Windows** — WSL only.

  - `opensop upgrade` — new subcommand.  Re-fetches the latest release of the
    single-file script from `github.com/opensop/opensop` and replaces the
    installed binary.  Prints old → new version on success.  Flags: `--pin X.Y.Z`
    to target a specific tag; `--dry-run` to preview without writing.  Registered in
    the command registry (category `config`, backend `local`; requires `curl`).

### Security (install/upgrade hardening — adversarial review)

- **[high] Checksum verification before install/replace.** Both `install.sh` and
  `opensop upgrade` now fetch a companion `<binary>.sha256` file from the same
  release location.  If present, the download's SHA-256 is verified (portable:
  `sha256sum` → `shasum -a 256` → `openssl dgst`) before any file is touched.
  A mismatch aborts immediately without modifying the installed binary.  If no
  checksum file is published yet, the operation refuses with a clear error unless
  `--allow-unverified` is passed explicitly.  GPG signing of releases is planned
  as a follow-up; SHA-256 verification is the current security posture.

- **[high] `--pin` version match enforced.** When `--pin X.Y.Z` is requested, the
  embedded `OPENSOP_CLI_VERSION` of the downloaded binary is checked against the
  requested pin.  A mismatch aborts before installing.

- **[high] Upgrade targets the running script (`BASH_SOURCE[0]`), not PATH.**
  `cmd_upgrade` now derives its target from `BASH_SOURCE[0]` (the actual executing
  file), canonicalized through symlinks via `readlink -f` / Python fallback.
  A decoy `opensop` earlier on PATH can no longer redirect the upgrade to the
  wrong binary.  The resolved path must be a regular file; non-files are rejected.

- **[high] Atomic same-filesystem replace; truncation window eliminated.**
  Temp files are now created inside the destination directory (not `/tmp`), so
  `mv` is always a same-filesystem atomic rename.  The `cp`-over-live-binary
  fallback (which had a corruption window) is removed from both `cmd_upgrade`
  and `install.sh`.

- **[medium] Executable permissions preserved.**  The temp file (created with
  mode `0600` by `mktemp`) is `chmod`-ed to match the existing target's mode
  before the atomic rename.  System installs at `/usr/local/bin` (typically
  `0755`) no longer lose group/other read+execute bits.  Default is `0755` when
  no existing file is present.  Fixed in both `cmd_upgrade` and `install.sh`.

- **Robust help engine (B1).** `cmd_help` is now driven by a single command registry
  (`_registry_raw`) that holds each subcommand's name, summary, usage, category, and
  backend. All help output is rendered from this one table — no more duplicated command
  descriptions.

  - `opensop help <command>` — per-command detail: usage, backend label, and copy-paste
    examples for every subcommand. Unknown command exits non-zero with `usage_error` and a
    hint pointing back to `opensop help`.
  - `opensop help agents` — concise agent-oriented orientation: discover (search/suggest),
    run locally, read receipts, resume paused steps, and pointers to `docs/AGENTS.md` and
    `docs/CLAUDE-INTEGRATION.md`.
  - `opensop help --json` (and `opensop --json help`) — emits a JSON array of
    `{command, summary, usage, category, backend}` objects built from the same registry.
    Agents can parse this to self-discover the full CLI surface without screen-scraping.

### Fixed

- **`suggest` aborted with empty output and exit 1 on strict-`set -e` bashes (`--local` and `--remote`).**
  The threshold-parse loop in both `local_suggest` and `cmd_suggest` used `(( i++ ))`.
  A standalone `(( i++ ))` returns **exit status 1** when `i` is `0` (the post-increment
  yields the old value `0`, which `((…))` reports as false). Under `set -euo pipefail` on
  bashes that abort on arithmetic-evaluating-to-zero (common on Linux; Apple's bash 3.2 does
  not), this killed `suggest` on the first loop iteration before any output — reproducing as
  `opensop suggest "…" --local --json` exiting 1 with empty stdout. `search` was unaffected
  because it has no such loop, which is why a no-match `search` passed while `suggest` failed
  in the same run. Replaced both occurrences with the assignment form `i=$((i + 1))`, which
  always returns 0. Added a source-level guard in `test/test.sh` forbidding standalone
  `(( var++ ))` / `(( var-- ))` increments so the footgun cannot reappear.

- **`register --server <unreachable>` exited 0 instead of failing.**
  `cmd_register` ran its own `curl` with `… || true`, discarding curl's exit
  code, and `-w "%{http_code}"` prints `000` when no connection is made. Both
  the fallback check (`4xx`) and the error check (`>= 400`) are false for `000`,
  so an unreachable server fell through to the success path and exited 0 — the
  CLI silently reported a registration that never happened. Now curl's exit code
  is captured (no `|| true`) and a non-zero exit or an HTTP `000` code is treated
  as a `network_error` (mirroring `api_call`), applied to both the JSON-wrapped
  POST and the raw-YAML fallback. The regression test isolates `OPENSOP_HOME` so
  `--server` is the only URL source and asserts the `network_error` code, rather
  than passing for the wrong reason when a developer `~/.opensop` is present.

- **`--server <url>` was silently overridden by a configured `~/.opensop`.**
  `load_config` `source`d the config file *after* `--server` had set `OPENSOP_URL`,
  so a plain `OPENSOP_URL=…` assignment in the file clobbered the explicit flag —
  requests went to the configured server instead of the one the user named. Now
  `load_config` captures any flag/env value before sourcing and restores it after,
  establishing the precedence **flag (`--server`) / env var > config file**. (This
  also restores the intended `OPENSOP_URL` env override, which the unconditional
  `source` had likewise defeated.)

- **`run` crashed on array-form `inputs` declarations.**
  `local_run` merged declared defaults with provided values via `(.inputs // {}) * $i`,
  which fails with `jq: array ([…]) and object ({…}) cannot be multiplied` when
  `inputs` is declared as an array of `{name,type,default?}` (valid per SPEC v0.6)
  rather than an object. The array form is now normalised to a name → default object
  (taking each entry's `default`, if present) before the merge, so both declaration
  shapes run. `opensop run <array-form-process> --input k=v` now completes instead of
  exiting 5.

## [0.8.0] — 2026-06-11

> **BREAKING:** The default backend is now **LOCAL**. Commands that previously hit a remote server by default now run locally (no server, no curl). Scripts relying on the old default-remote behaviour must add `--remote` (uses the configured `OPENSOP_URL`) or `--server <url>`. The `--local` flag is now a deprecated no-op and can be omitted — it is still accepted for script compatibility but prints a deprecation note to stderr.
>
> **Migration:** any invocation of the form `opensop <cmd> [args]` that expected remote behaviour must become `opensop --remote <cmd> [args]` or `opensop --server <url> <cmd> [args]`.

### Changed (breaking)

- **Default backend flipped from REMOTE to LOCAL (U2a — Phase 2).**
  `REMOTE_MODE` (default `false`) controls routing for all dual commands (`run`, `list`, `search`, `suggest`, `dry-run`, `status`, `steps`, `submit`, `cancel`, `diff`, `instances`, `compass`, `history`). `--remote` sets `REMOTE_MODE=true` and uses the configured `OPENSOP_URL`; `--server <url>` sets the URL for the invocation and implies `--remote`. `--local` is now a deprecated no-op alias — accepted without error but prints `note: --local is now the default and can be omitted` to stderr (suppressed in `--json` mode). `register` with no `--remote`/`--server` exits with `usage_error` directing users to pass one of these flags. `curl` is only invoked in REMOTE mode. Config (`~/.opensop`) is only loaded in REMOTE mode — local runs are fully self-contained.

### Changed (non-breaking)

- **Vocabulary unified on "run(s)" (U2b).**
  User-facing messages, help text, and TTY output now say "run(s)" consistently instead of "instance(s)" for the local-default world. The `instances` command name is unchanged (it is an established verb), but its description now reads "list runs". Affected: `cmd_instances` pretty header, `local_instances` pretty header, `cmd_submit` TTY confirmation, resume hints, and usage-error strings in local engine functions.

### Added (Phase 1 — local parity for all dual commands)

- **`opensop cancel <run_id> [--reason TEXT]` — cancel a running or waiting local run (P1f).**
  `cmd_cancel` branches to `local_cancel` when `REMOTE_MODE != true` (default; no server, no curl).
  Only `running` or `waiting` runs can be cancelled — submitting cancel on a `completed`,
  `failed`, or already-`cancelled` run is rejected with a `usage_error` (mirroring the
  runtime's invalid-transition behaviour). On success: manifest `status` is set to
  `"cancelled"`, the `waiting` and `cursor` blocks are cleared, `ended_at` is written,
  and a `{type:"cancel", status:"cancelled", reason?}` receipt is appended to
  `audit.jsonl`. Output shape mirrors `cmd_cancel` (pretty: `ok "cancelled …" + reason
  line`; JSON: updated manifest piped through `emit_pretty_or_json`).

- **`opensop diff <run_id1> <run_id2>` — compare two local runs (P1e).**
  `cmd_diff` branches to `local_diff` when `REMOTE_MODE != true` (no server, no curl).
  `local_diff` reads each run's `manifest.json` (for `state`/`inputs`/`metadata`),
  `audit.jsonl` (for per-step receipts), and `context.json` (for final outputs), then
  emits an identical shape to the remote diff response:
  `{a:{id,state,started_at}, b:{id,state,started_at}, differences:[{path,a,b}], identical:true|false}`.
  Compared fields mirror the remote: top-level `state`, `inputs`, `outputs` (final
  context), `metadata`; per-step `state`, `sub_state`, `outputs`, `decided_by`,
  `exit_code`, `duration_ms`. Same-process guard is enforced (diff across different
  processes → `cli_error`). Unknown `run_id` → `die` with `instance_not_found`.
  Pretty rendering mirrors `cmd_diff`'s TTY table (bold path, red a:, green b:).

- **`opensop instances`, `opensop compass`, `opensop history --process <name>` — local admin views (P1d).**
  `cmd_instances`, `cmd_compass`, and `cmd_history` branch to `local_instances`,
  `local_compass`, and `local_history` when `REMOTE_MODE != true` (no server, no curl).
  `local_instances` enumerates `$OPENSOP_LOCAL_HOME/runs/*/manifest.json`, applies
  `--state`/`--process` filters and `--limit`/`--offset` pagination entirely in jq,
  and emits `{instances:[{id, process:{name}, state, started_at}], total:N}` — an
  identical shape to the remote `cmd_instances` response. `local_compass` applies the
  same group-by-process jq logic as remote `cmd_compass`, producing
  `{by_runs, by_recency, by_failure_rate}` from the local run corpus. `local_history`
  delegates to `local_instances --process <name>`, mirroring how `cmd_history`
  delegates to `cmd_instances`. All three route through `emit_pretty_or_json`; the
  pretty paths mirror their remote counterparts' TTY rendering (coloured state, ranked
  tables). Empty stores return empty arrays/zero totals, not errors.

- **`opensop status <run_id>` and `opensop steps <run_id>` — local run inspection (P1c).**
  `cmd_status` and `cmd_steps` branch to `local_status`/`local_steps` when
  `REMOTE_MODE != true`. Both read `$OPENSOP_LOCAL_HOME/runs/<run_id>/manifest.json`
  and `audit.jsonl` (no server, no curl). `local_status` emits a JSON shape
  identical to the remote GET `/sop/:name/:id` response
  (`{id, process:{name}, state, started_at, completed_at, waiting, steps}`),
  including per-step `{step_id, type, state, sub_state}` derived from audit
  receipts. `local_steps` emits `{run_id, steps:[...]}` with the full receipt
  fields (`exit_code`, `output`, `started_at`, `ended_at`). Both route through
  `emit_pretty_or_json`; the pretty path mirrors `cmd_status`'s TTY rendering
  (colored state, glyph per step). Unknown `run_id` → `die` with `instance_not_found`.

- **`opensop dry-run <name|file.sop.json>` — local process preview with input validation (P1b).**
  `cmd_dry_run` branches to `local_dry_run` when `REMOTE_MODE != true`. The local
  implementation resolves the process file via `_find_skill_in_cells` (bare name →
  cell chain) or an explicit path, normalises the `.sop.json`'s `inputs` field to
  array form, validates provided `--input`/`--inputs` against the declared schema
  (required/type/enum/email-format — same jq logic as the remote validator), and
  prints the step walkthrough via `walk_steps_preview`. No run directory is created.
  Output shape (pretty prose / `{process, valid, validation_errors, steps}` JSON)
  is identical to remote `cmd_dry_run`.

- **`opensop search <kw...>` — ranked text search over the cell-chain process corpus (P1a).**
  `cmd_search` branches to `local_search` when `REMOTE_MODE != true`. A shared
  helper `_enumerate_local_processes` walks the active cell + ancestors (nearest
  first, nearest-wins dedup by basename — same precedence as `list --conflicts`),
  reads each `.sop.json`, and builds a `{processes:[...]}` object compatible with
  the existing `score_processes` jq scorer. `local_search` scores against that
  corpus, returns the top 5, and produces an output shape identical to remote
  `cmd_search` (pretty table in a TTY, `{query, results}` JSON when piped).

- **`opensop suggest "<task>" [--threshold N]` — intent scoring over the cell-chain process corpus (P1a).**
  `cmd_suggest` branches to `local_suggest` when `REMOTE_MODE != true`. Uses the
  same `_enumerate_local_processes` corpus and the same top-1 + confidence formula
  as the remote path. Output shape (pretty prose / `{task, match}` JSON) is
  identical to remote `cmd_suggest`. `--threshold` is supported.

---

## [0.7.0] — 2026-06-10

### Changed

- **`webhook` `response_mode` is now required** (no default). Omitting it is a
  validation error in both `schema validate` and the local engine — removes the
  prior silent local-`sync` / runtime-`callback` divergence.
- **`webhook` callback mode fires the outbound request, then pauses** (runtime
  parity), instead of pausing without notifying the endpoint.
- **`webhook` fallback body (no `body_template`) resolves declared step inputs
  via `from:`** (InputResolver parity) instead of a bare context lookup — no
  longer over-shares the full accumulated context to the endpoint.
- **`${process.inputs.X}` supports nested dot-paths** in webhook templates.

### Added

- **`subprocess` step type — recursive local execution (U8).**
  The CLI exceeds the runtime here: the runtime only stubs subprocess (`StepExecutors::Subprocess`
  returns `waiting_for_callback`), but the local engine fully executes child processes. Fields:
  `process` (required — logical name resolved via `_find_skill_in_cells`, or an explicit path);
  `inputs[]` (optional array of `{name, from}` mappings resolved against the parent context —
  supports `steps.<id>.outputs.<field>`, `<stepid>.<field>` shorthand, bare context keys, and
  literal string fallback). Child runs are stored flat at `$OPENSOP_LOCAL_HOME/runs/<child_run_id>/`
  (same as top-level runs) to prevent exponentially growing paths from recursive processes; a
  symlink `<parent_run>/subprocess/<step-id>/<child_run_id>` is created for at-a-glance
  inspectability. Recursion depth is guarded by `OSL_DEPTH` (max 16): each subprocess arm
  increments the counter and refuses at `>= 16`, turning a self-referencing process into a
  `failed` receipt rather than an infinite loop or path explosion. Result mapping: child
  `completed` → the child's final `context.json` is merged into the parent context under the
  step id (all child step outputs accessible via `parent_ctx[step_id][child_step_id]`); child
  `waiting` → propagates as parent `waiting_for_callback` with `child_run_id` and `child_run_dir`
  recorded in the audit receipt for per-level resume; child `failed` → parent step fails
  (respects `continue_on_error`). `executor` defaults to `internal`. 10 new assertions covering:
  happy path (parent calls 1-step child, context merged), inspectable run dir, audit receipt
  (type=subprocess/executor=internal), 'after' step sees child output; failure paths: missing
  process file, missing 'process' field, failing child halts parent, depth guard rejects
  self-referencing process, `continue_on_error` lets parent complete despite failing child.

- **`opensop submit <run_id> <step-id> --local` — resume a paused run (U3).**
  Completes the local state machine. `cmd_submit` branches to `local_submit` when
  `LOCAL_MODE=true`. `local_submit` asserts the run is `waiting` on the named step,
  validates submitted outputs against `manifest.waiting.expects.schema` (required /
  type / enum checks — same logic as the dry-run validator), injects outputs into
  `context.json` under the step id, appends a `"completed"` receipt to
  `audit.jsonl` (includes `decided_by` when `--decided-by` is passed), flips
  manifest back to `"running"`, then re-enters `_local_step_loop` at
  `cursor.next_index` (the step after the pause point — never re-runs completed
  steps). Finalizes manifest on completion, failure, or a second pause. Exits 0 on
  completion; non-zero on failure. Does not require curl — the full
  form/noop/automated path works with jq only.

- **`form` step type — pause/resume state machine (U2).**
  A `form` step pauses the local run: `_local_step_loop` appends a `"waiting"`
  receipt to `audit.jsonl` (reason: `"waiting_for_input"`, byte-parity with the
  runtime's `StepExecutors::Form`) and returns `"waiting:<index>"`. `local_run`
  transitions the manifest to `status:"waiting"` and writes the full pause
  envelope: `cursor:{next_index}` and `waiting:{step, index, reason, expects,
  since}`. `expects.outputs` lists field names; `expects.schema` carries the full
  inputs array. No `ended_at` is written while waiting. The run exits 0 (a clean
  pause is not a failure). A TTY prints the resume hint:
  `opensop submit <run_id> <step-id> --local --output k=v`.
  The `_local_finalize_trap` already gates on `status=="running"` so a waiting
  manifest is never flipped to `"interrupted"` on EXIT. Prerequisite for U3
  (resume at cursor).

- **`opensop list --local --conflicts`.** Inside a cell, marks the first
  occurrence of each filename across the cell chain as `← active` and
  subsequent ones as `← shadowed by [cell-name]`. Same data as plain
  `list` — just annotated with PATH-style resolution preview. Deferred
  from v0.6 PR #9; lands here as post-release polish.

- **`webhook` step type — outbound HTTP with sync/callback modes (U7).**
  Mirrors `StepExecutors::Webhook` (`webhook.rb`) + `Opensop::Templating` (`${...}`
  dialect). Fields inside the nested `webhook:` block: `url` (required), `method`
  (default `POST`; `GET|POST|PUT|PATCH|DELETE`), `headers` (object), `body_template`
  (path relative to the `.sop.json` directory; else inputs-as-JSON), `response_mode`
  (`sync|callback|poll`). Template dialect: `${env.X}`, `${process.inputs.X}`,
  `${callback_url}`, bare `${X.Y.Z}` (→ accumulated context). Implemented in pure jq
  (no shell eval, no external renderer). **sync mode**: `require_curl` inside this arm
  only; fires a real curl call (or the `OSL_WEBHOOK_STUB` seam); asserts 2xx (else step
  fails); parses the response body as a JSON object into step outputs (empty body → `{}`);
  non-JSON body is a step failure. **callback mode**: appends a `waiting` audit receipt
  (`reason: "waiting_for_callback"`, `callback_id` included for tracing), then pauses
  the run via the same `waiting:<index>` protocol as `form`/`approval`/`wait.until`;
  operator resumes manually with `opensop submit <run_id> <step-id> --local --output k=v`
  (no inbound HTTP receiver — documented limitation of the local backend). **poll mode**:
  exits 2 with `"response_mode: poll is not implemented yet (see SPEC §8 roadmap)"`
  (byte-parity with the runtime's `raise StepFailure`). `executor` defaults to
  `external` (already in the per-type default map). Test seam: `OSL_WEBHOOK_STUB=
  "<code>:<body>"` (e.g. `OSL_WEBHOOK_STUB='200:{"result":"ok"}'`) skips curl and
  drives the full 2xx/non-2xx/parse pipeline without a real server. 20 new assertions
  covering: sync 2xx success, context threading, audit receipt, executor=external,
  sync non-2xx failure, empty body, non-JSON body, callback pause, waiting.reason,
  callback resume via submit, 'done' step after resume, poll rejection, missing url.

- **`llm` step type — synchronous LLM call via Anthropic Claude (U6).**
  Mirrors `StepExecutors::Llm` + `LlmProviders::Anthropic` exactly. Pipeline:
  (1) load prompt (inline `prompt:` or `prompt_file:` relative to the `.sop.json`
  directory); (2) substitute `{{ var }}` tokens from the accumulated context via
  jq; (3) POST to `https://api.anthropic.com/v1/messages` (headers:
  `x-api-key`, `anthropic-version: 2023-06-01`, `content-type`) with `model`,
  `max_tokens: 4096`, a schema-instructed `system` prompt, and the rendered user
  prompt; (4) extract the first text content block, strip `` ```json `` fences,
  parse as a JSON object; (5) validate against `expected_output_schema` (required
  / type / enum checks); (6) on validation failure, retry up to
  `max_retries + 1` total attempts (default 3) with a corrective preamble — or 1
  attempt when `retry_on_incomplete: false`. On success, the validated object is
  the step output and is threaded into context. On exhaustion, `manifest.status`
  is `"failed"`. `require_curl` is called inside this arm only (curl-free for all
  other step types). `ANTHROPIC_API_KEY` absence is a loud fatal error (parity
  with `LlmProviders::Anthropic#call`). Model must start with `"claude"` (parity
  with `Llm.default_provider_for`). Test seam: `OSL_LLM_STUB=<raw-text>` skips
  the network call and feeds the value directly into the fence-strip + schema
  validation pipeline (parity with `provider_resolver=` in the runtime specs).
  15 new assertions covering the happy path, fence-stripping, `{{ var }}`
  substitution, schema exhaustion, missing key, non-claude model, and
  `retry_on_incomplete: false`.

- **`wait` step type — synchronous and async pause/resume (U5).**
  Mirrors `StepExecutors::Wait` (`wait.rb`) exactly. Three dispatch paths based on
  the step's nested `wait:` block: (a) `wait.seconds` present → synchronous
  completion immediately with `{waited: true, seconds: <n>}` — no actual sleep
  (byte-parity with the runtime's MVP stub); (b) `wait.until` present → async
  pause with `reason: "waiting_for_callback"`, `until` recorded in the audit
  receipt as advisory metadata, resumed via `opensop submit <run_id> <step-id>
  --local`; (c) neither present → synchronous completion with `{waited: true}`.
  The async pause path drops through `local_run`'s `waiting_for_callback` branch
  (already the `*` fallthrough for unrecognised types) and `local_submit` resumes
  it correctly at `cursor.next_index`. Empty `expects.outputs/schema` means submit
  accepts any (or no) output. 16 new assertions covering all three paths including
  the failure path (second submit on a completed run is rejected).

- **`approval` step type — pause/resume state machine (U4).**
  An `approval` step pauses the local run: `_local_step_loop` appends a
  `"waiting"` receipt to `audit.jsonl` (reason: `"waiting_for_approval"`,
  byte-parity with the runtime's `StepExecutors::Approval`) and returns
  `"waiting:<index>"`. `local_run` transitions the manifest to
  `status:"waiting"` and writes the full pause envelope. When the step
  declares no `inputs[]` or `outputs[]`, `expects.outputs` defaults to
  `["decision"]` and `expects.schema` to a required enum field
  `decision: approve|reject`. On submit, the enum constraint is enforced
  (e.g. `decision=maybe` is rejected). `decided_by` is recorded in the
  completion receipt. Full round-trip: run → pause at approval →
  `opensop submit <run_id> <step-id> --local --output decision=approve`
  → remaining steps run and run completes.

- **`required_if` parity (U4).** The runtime's `validate_outputs!`
  supports `required_if:` — a field required only when a condition
  evaluates to true (e.g. `rejection_reason` required only when
  `decision == 'reject'`). The local validator cannot evaluate arbitrary
  condition expressions (no `ConditionEvaluator`), so it skips the
  unconditional required check for any schema field that declares
  `required_if`. Intentionally permissive — never more restrictive than
  the server. The gap is documented in a comment in `local_submit`.

### Changed (internal)

- **Extract `_local_step_loop` from `local_run` (U1 — pure refactor, zero behavior change).**
  The per-step execution kernel is now a standalone function
  `_local_step_loop <run_dir> <proc_file> <start_index> <ctx_json>`.
  It iterates steps from `start_index`, dispatches by type, threads context,
  writes audit receipts, and writes `context.json` after every completed step
  (live checkpoint). Returns one of `"completed"`, `"failed"`, or
  `"waiting:<index>"` via stdout. `local_run` sets up the run dir + manifest,
  delegates to the loop, then finalizes. Prerequisite for U3 (resume at cursor).

- **U3.5 keystone cleanup — cursor semantics, atomic writes, dead-code removal, dynamic type.**
  `cursor.next_index` now consistently stores the index of the **first step to run
  on resume** (paused step index + 1) — both in `local_run`'s waiting branch and
  in `local_submit`'s second-pause path. `local_submit` reads `cursor.next_index`
  directly without a +1 offset. Context checkpoints in `_local_step_loop` and
  `local_submit` are now written atomically (temp + mv) to prevent truncation from
  silently stripping outputs. Removed the duplicated `errors_json` validation block
  in `local_submit` (the dead first block using a here-string input that was
  immediately overwritten) and the unused `proc_file2` variable. The resumed-step
  completion receipt now derives its `type` from the process file
  (`jq ".steps[$wait_index].type"`) instead of hardcoding `"form"`.

## [0.6.0] — 2026-06-08

The cell substrate. Six PRs (#6, #7, #8, #9, #10, #11) added a fractal
addressing primitive, a substrate-level event log per skill, name resolution
across the cell chain, fork with lineage, per-cell receipts, and the
executor field. Backwards-compatible — every pre-v0.6 usage continues to
work; v0.6 features only activate inside a cell.

### Added

- **Cell primitive — `opensop init` and `opensop scope`.** A "cell" is a
  directory marked by `.opensop/manifest.yaml`. `init` creates one in cwd
  (auto-detecting the parent cell when an ancestor `.opensop/` exists);
  `scope` walks up from cwd and prints the active cell + ancestor chain.
  Pure-additive — no existing command behavior changes. Foundation for the
  rest of v0.6.
- **Lineage primitives — `opensop annotate` and `opensop lineage`.**
  Substrate-level event log per skill stored in `.opensop/lineage.json` in
  each cell. `annotate <skill> <event-type> <json>` appends a policy event
  to the skill's history (creates the lineage entry if it doesn't exist).
  `lineage <skill>` prints the entry (status, metadata, history) in the
  active cell, returning an empty default if no events have been recorded.
  Policy-neutral: the substrate stores `status` (open string), `metadata`
  (open object), and `history[].type` (open string); it doesn't interpret
  any of them. This is what evolution policies (e.g. mineralization) sit on
  top of to record promotions, demotions, locks, etc.
- **Fork mechanic — `opensop fork <name> [--from <cell>]`.** Materializes
  a copy of an ancestor cell's skill into the active cell and records a lineage
  entry with `forked_from = { cell, forked_at, snapshot }`. The `snapshot` is
  the parent's `status` and `metadata` captured opaquely — the substrate stores;
  evolution policies decide what to do with it (typical: inherit + mark
  unverified until first run in the child cell). Auto-detects the source via
  walk-up; pass `--from` to override. Refuses to overwrite an existing skill
  in the active cell.
- **Step executor field — `executor: internal|external`.** Steps in a
  `.sop.json` may declare where their work happens: `external` means the work
  is done by a process outside the OpenSOP runtime (script, webhook); the
  runtime orchestrates and receives the receipt. `internal` means the runtime
  handles the step directly. Field is optional; per-type defaults apply when
  absent (`automated`/`shell`/`webhook` → external, `noop`/`form`/`approval`/
  `notification`/`wait`/`judgment` → internal). Invalid values fail with
  `parse_error` at process load time — before any step runs and before a run
  directory is even created. The effective executor (explicit or defaulted)
  is recorded in each step's `audit.jsonl` entry. Formalizes the
  B-mode-vs-A-mode distinction and matches existing production patterns
  (deterministic external scripts producing typed receipts).

### Changed

- **Name resolution across the cell chain.** Two changes to the local
  engine when a cell is active:
  - `opensop run <name> --local` accepts a **bare logical name** (in addition
    to a file path). The name resolves to `processes/<name>.sop.json` in the
    active cell, then in each ancestor cell — nearest wins. Explicit file
    paths still work for backwards compatibility (paths are detected when the
    argument ends in `.sop.json` or contains `/`).
  - `opensop list --local` (no dir arg) now walks the active cell + ancestors
    when invoked from inside a cell, tagging each entry with `[cell-name]`.
    Passing an explicit `dir` keeps the original `find`-based behavior with
    no cell awareness.
- **`OPENSOP_LOCAL_HOME` default is now cell-aware.** When cwd is inside
  an OpenSOP cell AND the user has not explicitly set `OPENSOP_LOCAL_HOME`,
  local-mode receipts (`opensop run --local`, `opensop runs`, `opensop show`)
  now default to `<cell-root>/.opensop/` instead of the global
  `~/.opensop-local`. Receipts land alongside the processes that produced
  them, and each cell has its own receipt history. Outside any cell, the
  default is still `~/.opensop-local`. Explicit `OPENSOP_LOCAL_HOME=…` always
  wins. Backwards-compatible because it only kicks in when a `.opensop/`
  marker exists in cwd's path (no pre-v0.6 user has one).

---

## [0.5.0] — 2026-06-04

### Added

- **Local execution backend (`--local`) — no server.** The CLI now has two
  backends: by default it talks to a running OpenSOP server; with `--local` the
  *same commands* run on-machine against internal files — no Rails, no daemon,
  no network, no `curl` (just `bash` + `jq`). `opensop run <process>.sop.json
  --local` runs `automated`/`shell`/`noop` steps in order, threads a JSON
  context between them (stdin + `$OSL_CONTEXT`, stdout merged under the step id),
  and writes an append-only on-disk receipt per step
  (`$OPENSOP_LOCAL_HOME/runs/<id>/`, default `~/.opensop-local`). This is an
  extension of OpenSOP, not a separate tool.
- **`runs`** — list local runs. **`show <run_id>`** — a local run's manifest +
  per-step receipts (the local analogue of `instances` / `status`).
- **`list --local [dir]`** — discover internal `.sop.json` processes.
- A worked example (`examples/greet.sop.json` + `examples/steps/build.sh`) and a
  golden test (`test/test.sh`).

### Changed

- **BREAKING: `--local` now means *local execution*** (run against internal
  files). It previously aliased `OPENSOP_URL` to `http://localhost:3000`. For a
  local dev **server**, use `opensop config set url http://localhost:3000` or
  `OPENSOP_URL=http://localhost:3000` instead.

### Fixed

- **Failing steps are handled instead of aborting.** Under `set -e`, a non-zero
  step previously aborted the whole CLI before the failure receipt, manifest
  finalization, and `continue_on_error` could run. Step execution is now guarded
  so failures are recorded (`failed` receipt + manifest `status:"failed"`) and
  `continue_on_error` works.
- **`runs` / `show` no longer require `curl`** — they are always-local commands.
- **Interrupted runs no longer stick at `running`.** A killed/crashed run is
  finalized as `interrupted` via an EXIT trap.
- **Step `stderr` is captured** into the receipt (surfaced by `show`); empty
  stderr logs are no longer left behind.
- **Empty/malformed `steps` are rejected** up front instead of "completing"
  trivially. `run_id` hardened against same-second/recycled-PID collisions.
- Trust boundary documented (local steps run as shell — only run process files
  you trust), and failure-path regression tests added to `test/test.sh`.

---

## [0.4.1] — 2026-05-08

### Fixed

- **Cache priming on `history` and `instances`** — both subcommands now
  populate the local `id → process.name` map from every response row.
  Agents who use the discovery layer to find an instance and immediately
  inspect it no longer hit the cache-miss path.
- **Paginated cache-miss fallback in `lookup_name`** — the fallback now
  walks up to 1000 instances (5 pages of 200) before giving up, instead
  of stopping at the first 200. Defensive fix; rarely hit once cache
  priming is in.
- **Multi-word `search` and `suggest`** — queries are now tokenized on
  whitespace and scored per-token, with hyphenated process names also
  tokenized on `-`/`_`. `search "morning briefing"` now correctly
  matches `darwin-morning-briefing`. Single-word queries unchanged.

### Changed

- **Search/suggest corpus widened** — `inputs_summary` and
  `outputs_summary` (already in the `/sop/` discovery response, just
  unused) are now indexed alongside name + description + tags.
  Expected ~30% recall lift on "what produces X?" / "I want Y"
  intent queries. Reported by the Darwin agent.

---

## [0.4.0] — 2026-05-08

### Added

- **Structured CLI-side errors in `--json` mode.** When `--json` is set, every
  `die()`/`err()` call now emits `{"error": "<code>", "message": "<message>",
  "hint": "<hint>"}` to stderr instead of prose. Prose-mode default (TTY) is
  unchanged — fully backward-compatible.
- `_resolve_output_mode()` helper that respects `OUTPUT_MODE` before `main()`
  has finished stripping flags (e.g. very early dependency checks).
- Error codes for all CLI-side failure paths: `config_missing`,
  `missing_dependency`, `network_error`, `instance_not_found`, `usage_error`,
  `file_not_found`, `invalid_json`, `unknown_command`, `unknown_flag`,
  `parse_error`, `cli_error`.
- `hint` field on relevant codes (e.g. `config_missing` hints
  `opensop config set url <URL>`; `missing_dependency` for jq hints
  `brew install jq`).

### Changed

- **HTTP error path in `api_call`:** in `--json` mode, server error envelopes
  now pass through verbatim with a `_meta.http_status` field appended. The
  previous behavior (prose + raw JSON dump) is replaced by a single clean JSON
  object on stderr.
- `register` HTTP error path brought in line with the same `api_call` pattern.
- All `die "..."` call sites updated with explicit codes and hints where
  applicable.
- `file not found` wording normalised to `"file does not exist: <path>"` across
  `register` and `schema validate`.

---

## [0.3.1] — 2026-05-08

### Fixed

- `compass --json` shape now matches docs: top-level keys are
  `{by_runs, by_recency, by_failure_rate}` with consistent field names per
  slice (`{name, total}` / `{name, last_run_at}` /
  `{name, total, failures, rate}`).

---

## [0.3.0] — 2026-05-08

### Added

- `diff <id1> <id2>` — compare two instances of the same process field-by-field.
- `compass` — top processes by run-count, recency, and failure rate.
- `history --process <name> [--limit N]` — recent instances of a specific
  process, newest-first.
- `dry-run <name> [opts]` — client-side preview: validates inputs against the
  process schema and describes each step without creating an instance.
- `register <process.yaml>` — POST a `.sop.yaml` to `/sop/processes/register`.
- `schema validate <file.yaml>` — fully client-side YAML lint using `yq` (v4+)
  with `python3` + PyYAML as a fallback.
- `--local` global flag — overrides `OPENSOP_URL` to `http://localhost:3000`
  for a single call without changing config.

---

## [0.2.0] — 2026-05-08

### Added

- `search <keyword> [...]` — ranked text search over process names,
  descriptions, and tags.
- `suggest "<task description>"` — inverse retrieval: describe a task, get the
  top-matching process back with a confidence score.
- `list --tag <tag>` — client-side filter by tag.
- README worked example (full `lead-qualification` run from start to
  completion).
- Sample `opensop list` output in README.
- Lifted the cache-line note into its own README section.

---

## [0.1.0] — 2026-05-07

### Added

- Initial release.
- 9 subcommands: `list`, `schema`, `run`, `status`, `steps`, `submit`,
  `cancel`, `instances`, `config`.
- Instance-ID local cache (`~/.opensop/instances.tsv`) — maps instance IDs to
  process names so subsequent commands need only the ID.
- TTY-aware output: pretty-printed in a terminal, compact JSON when piped.
- `--json` / `--pretty` global flags.
- `X-SOP-Token` auth header support.
- `NO_COLOR` support.

[0.9.1]: https://github.com/opensop/opensop/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/opensop/opensop/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/opensop/opensop/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/opensop/opensop/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/opensop/opensop/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/opensop/opensop/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/opensop/opensop/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/opensop/opensop/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/opensop/opensop/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/opensop/opensop/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/opensop/opensop/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/opensop/opensop/releases/tag/v0.1.0
