# Enforcement — AgenticApps spec §10.9 (local-first)

The `add-observability` skill at v0.3.0 supports two enforcement layers:

| Layer | Path | Status in v1.10.0 |
|---|---|---|
| **§10.9.1 delta scan + §10.9.2 baseline file** (MUSTs) | local — `claude /add-observability scan --since-commit main` before opening a PR | **fully implemented** |
| **§10.9.3 reference CI workflow** (SHOULD) | GitHub Actions YAML — `observability.yml.example` in this directory | **ships as opt-in example** |
| **§10.9.4 pre-commit hook** (MAY) | not shipped | deferred to v1.11.0+ |

Hosts conformance: §10.9.1 and §10.9.2 are MUSTs and are satisfied. §10.9.3 is SHOULD; the host ships an example workflow but does NOT install it via migration 0011, because Claude Code's CI installation story is not mature enough on hosted GitHub runners (2026-05) for it to work out-of-the-box. Projects pick the layer that fits their CI environment.

---

## Local enforcement workflow (the primary path)

The canonical pre-PR command:

```bash
claude /add-observability scan --since-commit main
```

This produces two artefacts at the project root:

- `.scan-report.md` — human-readable findings, grouped by checklist item and confidence bucket.
- `.observability/delta.json` — machine-readable summary with `counts.high_confidence_gaps` (the number that matters for the conformance question).

### How to interpret the result

1. **Open `.observability/delta.json`** (or `cat .observability/delta.json | jq '.counts'`).
2. **Open `.observability/baseline.json`** on `main` (`git show main:.observability/baseline.json | jq '.counts'`).
3. The PR adds new high-confidence gaps iff `delta.counts.high_confidence_gaps > 0`. Specifically: the project total after this PR lands would go from `baseline.counts.high_confidence_gaps` to `baseline.counts.high_confidence_gaps + delta.counts.high_confidence_gaps`.

If `delta.counts.high_confidence_gaps == 0`, the PR is conformance-clean for high-confidence rules. Medium-confidence findings are heuristic and don't gate.

If `delta.counts.high_confidence_gaps > 0`, fix the gaps before opening the PR:

```bash
claude /add-observability scan-apply --confidence high
```

This walks each finding with per-file diff + consent prompt. After applying, `.observability/baseline.json` is regenerated automatically (§10.9.2 line 219 obligation).

### When to update the baseline

Run the manual baseline refresh from `main` (or whatever your trunk branch is) after a conformance-affecting PR merges:

```bash
git checkout main && git pull
claude /add-observability scan --update-baseline
git add .observability/baseline.json
git commit -m "chore: refresh observability baseline"
```

Or — equivalently — let `scan-apply` regenerate it automatically the next time someone fixes findings.

### Suggested team norms

Without a CI gate, enforcement depends on team discipline. Three norms that make Option 4 work:

- **Reviewer checklist line**: "Did the author confirm `delta.counts.high_confidence_gaps == 0`?" Add it to your PR template.
- **Pre-push muscle memory**: alias `gpp = 'claude /add-observability scan --since-commit main && jq .counts .observability/delta.json && git push'`. The scan output is the gate.
- **Periodic full-scan audit**: monthly, run `scan --update-baseline` from `main`, eyeball any drift in `baseline.counts`, commit the refreshed baseline.

The honor system isn't enforcement-by-fiat, but it's the trade-off Option 4 buys: zero CI infrastructure, zero LLM cost per PR, zero CI threat surface.

---

## Optional: reference CI workflow (advanced opt-in)

`observability.yml.example` in this directory is a fully-spec-conformant §10.9.3 GHA workflow. It's NOT installed by migration 0011 in v1.10.0 because:

1. **Claude Code's CI installation isn't first-class yet** (no `actions/setup-claude@vN`). Hosted GitHub runners would need a custom bootstrap step.
2. **Cost**: every PR run consumes LLM tokens. For a busy repo, the spend is non-trivial.
3. **Latency**: an LLM-driven walk is slower than a deterministic scanner.
4. **Determinism**: LLM stochasticity can produce slightly different findings on identical code, complicating CI gate comparisons.
5. **Prompt-injection threat**: PR-contributed source files become LLM input — see "Threat model" below.

If you have a self-hosted GHA runner with Claude Code installed, or you've otherwise solved the install/cost/threat questions, you can adopt the example:

```bash
cp ~/.claude/skills/agenticapps-workflow/add-observability/enforcement/observability.yml.example .github/workflows/observability.yml
```

Once installed, behaviour is per spec §10.9.3:

1. Runs the delta scan on every PR.
2. Compares delta high-count against the base-branch baseline.
3. Fails PR if the count increases.
4. Posts a sticky PR comment on failure.

The example workflow is SHA-pinned, env-var-indirected, concurrency-controlled, and uses `pull_request` (not `pull_request_target`). The threat-model section below documents the assumptions.

### Threat model (when adopting the example)

The `pull_request` trigger fires on PRs from any source, including forks. On hosted runners, the workflow:

- Checks out the PR's head SHA (which is **attacker-controlled** for fork PRs).
- Runs the `claude` binary on the checked-out source.
- Writes `.observability/delta.json` to the runner.
- Posts a sticky comment to the PR if the gate fails.

Mitigations baked into `observability.yml.example`:

1. **`pull_request` trigger (NEVER `pull_request_target`).** The `pull_request` event runs in the context of the PR's head SHA but with **no access to repository secrets**. The `pull_request_target` event runs against the base branch's code with full secret access — the wrong choice when reading PR-contributed content. **DO NOT change `pull_request` to `pull_request_target`.**

2. **`permissions: contents: read`** at the top level. The PR-comment job elevates to `pull-requests: write` for a single step only.

3. **Environment-variable indirection** for every `${{ github.* }}` interpolation inside `run:` blocks. Closes the standard GHA shell-injection class.

4. **Pinned action SHAs** (40-char hex):
   - `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd` (v6.0.2)
   - `marocchino/sticky-pull-request-comment@0ea0beb66eb9baf113663a64ec522f60e49231c0` (v3.0.4)

5. **Residual risk**: `claude` reads PR-contributed source code. A malicious PR could place [prompt-injection payloads](https://owasp.org/www-project-top-10-for-large-language-model-applications/) in source files. Mitigations limit the blast radius (no secrets, no write tokens) but the comment-posting step could be subverted. Opt-out for projects that don't trust fork PRs:

   ```yaml
   jobs:
     scan:
       if: github.event.pull_request.head.repo.full_name == github.repository
   ```

   Restricts the workflow to PRs from the same repo (internal contributors only).

### Opt-out from the CI gate (after adopting)

Delete or empty `.observability/baseline.json`. The workflow logs `::warning::enforcement disabled — no baseline on base branch` and skips the gate. Per §10.9.3, this is the explicit-not-silent opt-out path.

### Baseline merge conflicts

Every conformance-affecting PR that lands on `main` updates `baseline.json`. The next PR to rebase will see a conflict on that file. Resolution: **regenerate, don't hand-merge.**

```bash
git rebase origin/main
# baseline.json conflict here
git checkout origin/main -- .observability/baseline.json
claude /add-observability scan --update-baseline
git add .observability/baseline.json
git rebase --continue
```

### Updating pinned SHAs

Add to `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: monthly
```

Dependabot opens PRs that update the SHAs alongside the `# vN.Y.Z` comment annotations.

---

## v1.11.0 follow-up

A **standalone Node scanner port** is the highest-priority follow-up. It:

- Reimplements the scan procedure as a pure deterministic CLI (Node.js, ~1000 lines).
- Reads the same `meta.yaml` + `checklist.md` + `detectors.md` data files the markdown skill reads — single source of truth, no drift.
- Removes the `claude`-in-CI dependency entirely.
- Makes the example workflow installable on any hosted GHA runner.

When the Node port ships at v1.11.0, projects can flip from "local-only" Option 4 to "real CI gate" Option 3 by adopting the example workflow without any LLM-in-CI overhead. The CLI is the CI-grade implementation; the markdown skill is the dev-machine richer-judgment implementation.

---

## References

- Spec: [`agenticapps-workflow-core/spec/10-observability.md`](https://github.com/agenticapps-eu/agenticapps-workflow-core/blob/main/spec/10-observability.md) §10.9
- Phase plan: `.planning/phases/14-spec-10-9-enforcement/`
- Migration: `migrations/0011-observability-enforcement.md`
- ADR-0013 (migration framework): `claude-workflow/docs/decisions/0013-migration-framework.md`
