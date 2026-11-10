---
name: Bug report
about: Something in the CLI or the spec doesn't behave as documented
title: ""
labels: bug
---

**What happened**

<!-- One or two sentences. -->

**What you expected**

<!-- Link the README / SPEC.md / docs line if the behaviour is documented. -->

**Reproduce**

<!-- The smallest .sop.json and the exact commands. Use placeholder data:
     no real names, emails, tokens or internal hostnames. -->

```bash
opensop run ./repro.sop.json --input k=v
opensop status <run_id> --json
```

**Environment**

- `opensop --version`:
- OS and `bash --version`:
- `jq --version`:
- Agent CLI and version, if an `llm` step is involved:

Security issue? Don't file it here. See [SECURITY.md](../../SECURITY.md).
