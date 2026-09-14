# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`cli/` (this directory, inside the `opensop` repo) is the **primary execution surface** for OpenSOP: a single bash file, `bin/opensop` (~7,000 lines, 388 KB), that runs processes **locally** against `.sop.json` files with no server, no network, and no account required. There is no build step, no package manager, no compiled artifact — the file *is* the binary. It can also talk to an optional OpenSOP server via `--remote` or `--server <url>`. Read it top-to-bottom to understand it; it's organized into banner-delimited sections.

## Commands

```bash
bin/opensop <cmd> [args]        # run the CLI from the repo (no install needed)
bash -n bin/opensop             # syntax check — run after every edit
bash test/test.sh               # the test suite (golden test of the --local engine)
shellcheck bin/opensop          # lint (optional; see known warnings below)
bin/opensop --version           # must equal OPENSOP_CLI_VERSION at bin/opensop:19
```

- **Tests:** `test/test.sh` is a plain bash script, not a framework — it runs the `examples/greet.sop.json` process through `bin/opensop` and asserts on receipts. There is no per-test selector; to exercise one path, craft a small `.sop.json` and run `bin/opensop run <file> --json` the way the test does. It needs only `bash` + `jq` (no server, no curl). Always extend it when you touch the local engine — cover the **failure path**, not just the happy path (a happy-path-only test once hid a critical `set -e` bug).
- **There is no CI.** `bash -n bin/opensop && bash test/test.sh` is the only gate, and it is manual — run it yourself before committing; nothing else will.
- **Known shellcheck warnings** are pre-existing and not blockers: `C_CYAN` unused, and `SC2254` (unquoted `$plural`/`$noun` in `build_payload_object`'s `case`). Don't "fix" these without intent.

## Architecture

**Two backends behind one CLI.** Every command is dispatched from `main()` (bottom of the file). The default backend is **local** (v0.8+): commands run against local `.sop.json` files with no server, no network, no curl. `--remote` or `--server <url>` sets `REMOTE_MODE=true` and routes dual commands to call `api_call` (the single curl chokepoint) against a configured server's `/sop/*` REST API. `--local` is a deprecated no-op (local is now the default) — still accepted for script compatibility. Dual commands branch at their top: `if [[ "$REMOTE_MODE" != true ]]; then local_X "$@"; return $?; fi`. `runs` and `show` are always local. Understanding any feature means knowing which backend it lives in.

**File layout** (banner sections, in order): constants → output/error helpers → config → HTTP core (`api_call`) → local instance cache → one `cmd_*` per subcommand → the local execution engine (`local_*`) → `main()` dispatch.

**Output & error contract (cross-cutting — every command must honor it).**
- `OUTPUT_MODE` is `auto|json|pretty`. `auto` resolves TTY-aware via `_resolve_output_mode` (pretty in a terminal, compact JSON when piped). Route normal output through `emit_pretty_or_json`.
- Errors go through `die "<message>" "<code>" "<hint>"` (or `err`). In `--json` mode these emit `{error, message, hint?}` to **stderr**; otherwise a colored prose line. Use an existing error code (`config_missing`, `missing_dependency`, `network_error`, `instance_not_found`, `usage_error`, `file_not_found`, `invalid_json`, `unknown_command`, `unknown_flag`, `parse_error`, `cli_error`) — agents parse these.
- `_error_mode` only switches to JSON when `--json` was *explicitly* passed; bare TTY errors stay prose. Server HTTP ≥400 responses are passed through **verbatim** plus `_meta.http_status`.

**Remote state lives server-side; the only local state is a cache.** `~/.opensop/instances.tsv` maps `id → process name` so most commands take just an instance ID. It's primed from list/history/instances responses and rebuilt on a miss via `lookup_name`. Safe to delete.

**Local execution engine contract.** A `.sop.json` process runs `automated`/`shell`/`noop` steps in order. Each step receives the accumulated JSON context on **stdin** and in **`$OSL_CONTEXT`**; its JSON stdout is merged back under the step id (non-JSON stdout becomes `{stdout: "..."}`). Per-step append-only receipts are written under `$OPENSOP_LOCAL_HOME/runs/<id>/` (`manifest.json`, `audit.jsonl`, `context.json`; default `~/.opensop-local`). **Trust boundary:** local steps execute arbitrary shell on the host — same posture as a Makefile.

## Bash invariants (this script bites if you ignore them)

- The script runs under **`set -euo pipefail`**. In the local engine, any command substitution that runs a user step **must** be guarded (`out=$(...) || rc=$?`) — a bare `out=$(failing)` aborts the whole CLI before the failure is recorded. This is load-bearing, commented at the call sites.
- **`set -u` + empty arrays** is a recurring footgun: `"${arr[@]}"` on an empty array throws "unbound variable" on older bash. Guard with `(( ${#arr[@]} ))` before expanding.
- Targets **bash 4+**; macOS ships 3.2. Don't use 4-only features without need, and test with a real bash 4+.

## Adding or changing a command (improvement loop)

When you add or change a subcommand, treat it as not done until it clears this loop:

1. **Implement** `cmd_<name>` (remote) or `local_<name>` (local) in the right section.
2. **Wire `main()` in two places**: the curl-gate `case` (local-only commands skip `require_curl`) and the dispatch `case`.
3. **Update the surfaces that document it**: `cmd_help` text, the README subcommand table, and a `CHANGELOG.md` entry under `[Unreleased]`.
4. **Honor the contracts above**: output via `emit_pretty_or_json`, errors via `die "msg" "code" "hint"`.
5. **Test the failure path**, not just success — add assertions to `test/test.sh`. Run `bash -n bin/opensop && bash test/test.sh`.
6. **Rate it 1–10** against this list (correctness, `set -e`/`set -u` safety, output/error contract, docs updated, failure-path tested). If it's below ~8, name the gap and fix it, then re-rate. Only ship at ≥8.

## Releasing

Versions are tagged and mirrored to GitHub Releases (`v0.1.0` … current). To cut one:

1. Bump `OPENSOP_CLI_VERSION` (`bin/opensop:19`).
2. Regenerate `bin/opensop.sha256` (`make checksum`) whenever `bin/opensop` changes; the installer and `opensop upgrade` both verify the download against it. A stale or missing checksum causes the default `curl … | bash` install to fail.
3. Promote `CHANGELOG.md`'s `[Unreleased]` to `## [X.Y.Z] — <date>` and add the compare link at the bottom (`[X.Y.Z]: .../compare/<prev>...vX.Y.Z`).
4. Commit (`bin/opensop` + `bin/opensop.sha256` in the same commit), then `git tag -a vX.Y.Z`, push the branch and the tag.
5. `gh release create vX.Y.Z --latest --notes-file <changelog-section>`.
6. Paste the `bin/opensop.sha256` digest into the GitHub Release notes (a second published surface for the digest — note it is same-account, so it aids reproducibility, not authenticity against account compromise).

Follow [Semantic Versioning](https://semver.org/) and [Keep a Changelog](https://keepachangelog.com/). A change to flag meaning (e.g. `--local`) is **breaking** — call it out.

## Agent integration

Agents use this CLI to run processes **locally** — no server, no HTTP — for the core loop. `docs/CLAUDE-INTEGRATION.md` is the canonical integration guide (run existing processes; recognize reusable multi-step work as a candidate `.sop.yaml`; author + register). The `--remote` path is opt-in for shared orchestration against a running OpenSOP server. For discovery prefer `opensop search` / `opensop suggest` (intent-based) over scanning `opensop list`.
