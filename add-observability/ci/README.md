# CI integration — AgenticApps spec §10.9.3

The reference GitHub Actions workflow `observability.yml` ships alongside the
`add-observability` skill at v0.3.0 (`implements_spec: 0.3.0`). It implements
spec §10.9.3's four CI obligations:

1. Runs the delta scan (§10.9.1) on every PR.
2. Compares the delta scan's high-confidence-gap count against the baseline
   file from the PR's merge-target branch.
3. Fails the PR if the count would increase.
4. Surfaces the new findings as a PR comment.

Migration `0011-observability-enforcement` copies this file into each project's
`.github/workflows/` when promoting from scaffolder v1.9.3 → v1.10.0.

---

## v1.10.0 status — known limitation

The workflow's delta-scan and full-scan steps invoke the `claude` CLI:

```yaml
claude /add-observability scan --since-commit "${BASE_SHA}"
```

This requires Claude Code to be installable in the CI runner. **As of
2026-05, Claude Code's CI installation story is not fully supported on
hosted GitHub runners.** Until the v1.11.0 standalone Node scanner port
ships, projects have three workarounds:

1. **Manual pre-PR scan.** Run `claude /add-observability scan --since-commit main`
   locally before opening the PR. If the gap count increases, fix locally
   before pushing.

2. **Self-hosted GHA runner.** A developer machine with Claude Code
   installed, configured as a self-hosted runner, can execute the workflow
   as written. See [GitHub's self-hosted runner docs](https://docs.github.com/en/actions/hosting-your-own-runners).

3. **Wait for v1.11.0 Node scanner port.** A standalone Node CLI that
   re-implements the scan procedure (no Claude Code dependency). Tracked
   as a follow-up issue on `agenticapps-eu/claude-workflow`.

Until one of the above is in place, the workflow ships dormant: it will
fail with `claude: command not found` on standard hosted runners. Adopt
it pre-emptively (it sits in `.github/workflows/` ready to activate) or
gate it on `[skip ci]` until your runner is ready.

---

## Threat model

### What the workflow exposes

The `pull_request` trigger fires when a PR opens or updates. On hosted
runners, the workflow:

- Checks out the PR's head SHA (which is **attacker-controlled** if the
  PR is from a fork).
- Runs the `claude` binary on the checked-out source.
- Writes `.observability/delta.json` to the runner.
- Posts a comment to the PR if the gate fails.

### Mitigations baked into this workflow

1. **`pull_request` trigger (NEVER `pull_request_target`).** The
   `pull_request` event runs in the context of the PR's head SHA but with
   **no access to repository secrets**. The `pull_request_target` event
   runs against the base branch's code with full secret access — the
   wrong choice when reading PR-contributed content.

   **DO NOT change `pull_request` to `pull_request_target`** in this
   workflow. It would create a path for a malicious PR to exfiltrate
   secrets through prompt injection in source files. This is one of the
   highest-severity GitHub Actions vulnerabilities documented.

2. **Top-level `permissions: contents: read` (minimal).** The PR-comment
   job elevates to `pull-requests: write` for one step only. No write
   tokens are exposed to the scan steps that ingest attacker content.

3. **Environment-variable indirection for all `${{ }}` interpolation
   inside `run:` blocks.** GitHub Actions [security hardening guide](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
   documents how `${{ github.* }}` expressions inlined into shell can be
   exploited if the source value is attacker-influenced. We lift every
   such value into a step-level `env:` first, then reference `$BASE_SHA`
   (etc.) in shell — POSIX quoting handles untrusted bytes safely from
   that point on.

4. **Pinned action SHAs.** Actions are pinned by 40-char commit SHA, not
   floating tag — `marocchino/sticky-pull-request-comment@0ea0beb...`,
   not `@v3`. A floating tag is rewritable by the action maintainer and
   was the vector in the [tj-actions/changed-files compromise (2024)](https://github.com/advisories/GHSA-mrrh-fwg8-r2c3).
   See "Updating pinned SHAs" below for the maintenance pattern.

### Residual risk

`claude` (or any LLM-backed scanner) reads PR-contributed source code.
A malicious PR could place [prompt-injection payloads](https://owasp.org/www-project-top-10-for-large-language-model-applications/Archive/0_1_vulns/Prompt_Injection)
in source files that the scanner ingests. The blast radius is limited
by mitigations #2-4: no secrets, no write tokens, no remote network
access except for `marocchino/sticky-pull-request-comment` (pinned).
Worst case: a malformed comment posted on the PR. That's still
undesirable for projects with sensitive content.

**Opt-out for projects that don't trust fork PRs:** add a job-level
guard to the scan job:

```yaml
jobs:
  scan:
    if: github.event.pull_request.head.repo.full_name == github.repository
    # ... rest of job
```

This restricts the workflow to PRs from the same repo (internal
contributors). Forks won't trigger the scan; the gate is silently
disabled for them. Project owners decide whether that's an acceptable
trade-off.

---

## Opt-out path (§10.9.3 explicit-not-silent)

To disable enforcement temporarily without removing the workflow:

```bash
# Empty the baseline file (and commit the change)
echo '{}' > .observability/baseline.json
git add .observability/baseline.json
git commit -m "chore: disable observability CI gate temporarily"
```

On the next PR, the workflow's "Read base baseline" step will log:

```
::warning::baseline.json on base branch is malformed — enforcement disabled for this PR
```

and skip the gate (Compare-delta-vs-baseline becomes a no-op). The
warning is visible in the workflow run summary and the PR Checks tab —
**not silent**. Per spec §10.9.3.

To re-enable: run `claude /add-observability scan --update-baseline` on
main and commit the regenerated `baseline.json`.

The same opt-out path works for deletion (`rm .observability/baseline.json`).
The "Read base baseline" step's `git show` fails, the warning fires,
the gate is disabled.

---

## Baseline merge conflicts (high-frequency at adoption time)

The baseline file is committed alongside `policy.md` per spec §10.9.2.
This means: every PR that lands a conformance change updates
`baseline.json` on main. The next PR opened against main sees a
baseline.json conflict at rebase time.

**Resolution: regenerate, not merge.** Resolving the conflict by
hand-picking count fields produces stale data. The correct path:

```bash
git rebase origin/main
# baseline.json conflict here — resolve by regenerating:
git checkout origin/main -- .observability/baseline.json
claude /add-observability scan --update-baseline
git add .observability/baseline.json
git rebase --continue
```

For high-traffic repos, consider adding `.observability/baseline.json` to
your project's `.gitattributes` with `merge=ours` to auto-pick the new
baseline on rebase (then regenerate manually before pushing). This is
optional — spec §10.9.2 doesn't mandate it.

---

## Updating pinned SHAs (Dependabot example)

Add this to `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: monthly
    groups:
      observability-actions:
        patterns:
          - "actions/checkout"
          - "marocchino/sticky-pull-request-comment"
```

Dependabot will open PRs that update the pinned SHAs to match the latest
tag's commit (and update the `# v6.0.2` comment alongside). Review the
PR diff to confirm only the SHA changed.

---

## Customisation

This file is **scaffolder-owned**. Migration 0011 overwrites it on each
scaffolder update; pre-existing local edits are backed up to
`observability.yml.bak.<timestamp>` for manual reconciliation.

To customise without losing changes on the next update:

- Fork the action contents into a sibling workflow file (e.g.
  `.github/workflows/observability-custom.yml`) and modify that one.
  Disable the scaffolder copy by emptying the trigger:

  ```yaml
  on: {}   # disabled — using observability-custom.yml instead
  ```

- Or, contribute the customisation upstream so it becomes part of the
  reference workflow for all projects.

---

## References

- Spec: [`agenticapps-workflow-core/spec/10-observability.md`](https://github.com/agenticapps-eu/agenticapps-workflow-core/blob/main/spec/10-observability.md) §10.9
- ADR-0013 (migration framework): `claude-workflow/docs/decisions/0013-migration-framework.md`
- ADR-0014 (observability architecture): `agenticapps-workflow-core/adrs/0014-observability-architecture.md`
- Sticky-PR-comment action: <https://github.com/marocchino/sticky-pull-request-comment>
- GHA security hardening: <https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions>
