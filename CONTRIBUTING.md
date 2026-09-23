# Contributing to OpenSOP

OpenSOP is a public standard: the spec ([`SPEC.md`](./SPEC.md)), the manifesto ([`MANIFESTO.md`](./MANIFESTO.md)), and the local-first CLI ([`cli/`](./cli/)). The spec defines an optional server profile (§4); there is no maintained reference server.

---

## What lives here

| Concern | Lives in | How to contribute |
|---|---|---|
| **Spec** | `SPEC.md` | Propose changes via issue + PR; coordinate with the rails server repo |
| **CLI** | `cli/bin/opensop`, `cli/test/test.sh` | Fix bugs, add subcommands, improve local execution |
| **Agent guide** | `docs/AGENTS.md` | Keep accurate with CLI and spec changes |

---

## Contributing to the spec (SPEC.md)

`SPEC.md` is the contract shared between this repo and any conforming server. Changes must be coordinated:

1. **Open an issue** here describing the proposed change and its rationale. Include the current behavior, the proposed behavior, and which step types or endpoints are affected.
2. If the change touches the **server profile** (§4), say so explicitly. Nobody implements that profile today, so the spec is the only record of the decision.
3. Update `SPEC.md` to reflect the new version. When proposing a format change, describe it as an extension of the current version — check the version at the top of `SPEC.md` rather than assuming.

---

## Contributing to the CLI (cli/)

The CLI is a single bash file: `cli/bin/opensop`. No build step, no compiled artifact — the file is the binary.

### Setup

No setup needed. The CLI requires only `bash 4+` and `jq`.

```bash
# Syntax check (run after every edit)
bash -n cli/bin/opensop

# Full test suite
bash cli/test/test.sh
```

### Workflow

1. **Open an issue** for non-trivial changes.
2. **Branch from `main`**: `git checkout -b fix/short-description`.
3. **Make the change** with tests. Cover the failure path, not just the happy path.
4. **Run the gate**: `bash -n cli/bin/opensop && bash cli/test/test.sh` — both must pass.
5. **Update the surfaces that document the change**: `cmd_help` text, `cli/README.md` subcommand table, `cli/CHANGELOG.md` under `[Unreleased]`.
6. **Open a PR** against `opensop/opensop:main`. Answer: what's the problem, how does this solve it, what did I test.

### Standards

- **No `eval` with user input.** The `ConditionEvaluator` pattern exists for safe expression evaluation.
- **`set -euo pipefail` throughout.** Guard any command substitution running user-supplied steps: `out=$(...) || rc=$?`.
- **bash 4+.** macOS ships 3.2 — don't use 4-only features without documenting the requirement.
- **Output contract.** Normal output goes through `emit_pretty_or_json`. Errors go through `die "msg" "code" "hint"`.

---

## Secret scanning

Two layers, both running [gitleaks](https://github.com/gitleaks/gitleaks):

- **Local pre-commit hook** (after `bin/install-git-hooks`) — blocks commits containing detected secrets.
- **CI on every PR** (`.github/workflows/secret-scan.yml`) — the source of truth.

Allowlist entries for known-safe placeholders (test fixtures, doc examples) live in `.gitleaks.toml`.

---

## Forking for private process libraries

Many teams run OpenSOP with their own private processes. The recommended topology:

```
opensop/opensop          ← public, spec + CLI + example processes (this repo)
your-org/opensop-private    ← your private fork, tracks spec + CLI changes + hosts your processes
```

### First-time fork setup

```bash
git remote rename origin private
git remote add public https://github.com/opensop/opensop.git
git remote -v
# private  https://github.com/your-org/opensop-private.git
# public   https://github.com/opensop/opensop.git
```

Add a `processes/<your-org>/` directory for your private processes and gitignore it in the public repo (it's already reserved upstream — check `.gitignore`). In your private fork, remove that ignore line.

### The upstream-first rule

**Spec and CLI changes always land in public first.**

1. Branch from `main` in your local clone.
2. Make the change + tests.
3. Push to **public** and open a PR against `opensop/opensop`.
4. Get the PR reviewed and merged upstream.
5. Pull the merge into your local `main` and push to your private fork.

### Keeping your fork in sync

```bash
git checkout main
git pull public main
git push private main
```

### Private processes

- **Private processes live only in your fork.** Store them in a dedicated directory (e.g. `processes/<your-org>/`) that's gitignored in the public repo.
- **Never commit private processes to a branch that pushes to `public`.**
- **Treat the spec and CLI as stable API.** If a change would break your private processes, raise it in the upstream PR.

---

## Reporting issues

- **Bugs:** open an issue on `opensop/opensop` with repro steps and expected behavior.
- **Security:** please don't open public issues for security reports. See [`SECURITY.md`](SECURITY.md) for the disclosure policy.
- **Spec proposals:** open a discussion first — the process format is a contract.

---

## License

OpenSOP is Apache 2.0. By contributing, you agree your contributions will be licensed under the same terms.
