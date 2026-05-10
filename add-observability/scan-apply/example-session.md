# `scan-apply` example session — what the user sees

A walked-through example of running `scan-apply --confidence high`
against a cparx-shaped project, derived from the verification scan in
`scan-report-cparx-example.md`. This is documentation of the UX, not
executable code.

---

## Setup

The user has just run `add-observability init` in their cparx
worktree, then `add-observability scan` to validate. The scan
identified 6 high-confidence gaps and produced `.scan-report.md`. They
now run:

```
add-observability scan-apply
```

Default flags: `--severity high`, `--mode per-file`.

---

## Phase 1 output

```
Reading .scan-report.md (last scan: 2026-05-10 14:32 UTC, 4 minutes ago)
Found 6 high-confidence gaps across 3 files.

Plan:
  backend/cmd/api/main.go (4 gaps: C1×1, C2×2, C3×1)
  backend/internal/llm/client.go (1 gap: C2)
  backend/cmd/seed-mock-docs/upload.go — DEMOTED to medium, not in this run
```

---

## Phase 4 — first group

```
─── File: backend/cmd/api/main.go (4 gaps) ─────────────────────

C1.1 — Missing observability.Middleware in chi router

  --- backend/cmd/api/main.go (current)
  +++ backend/cmd/api/main.go (proposed)
  @@ -237,4 +237,8 @@
       r := chi.NewRouter()
       r.Use(chimw.RequestID)
       r.Use(chimw.RealIP)
  -    r.Use(chimw.Logger)
       r.Use(chimw.Recoverer)
  +    // AgenticApps spec §10.4 #1 — handler-entry span + traceparent
  +    // propagation. Mounted inside Recoverer so panics still produce 500s.
  +    r.Use(observability.Middleware)
  +    r.Use(chimw.Logger)

C2.1 — http.DefaultClient.Transport not wrapped

  --- backend/cmd/api/main.go (current)
  +++ backend/cmd/api/main.go (proposed)
  @@ -30,3 +30,7 @@
   func main() {
  +    observability.Init()
  +    http.DefaultClient.Transport = observability.NewTracingTransport(http.DefaultTransport)
  +
       port := getenv("PORT", "8080")

C2.2 — service.SupabaseAdmin uses bare http.Client

  --- backend/cmd/api/main.go (current)
  +++ backend/cmd/api/main.go (proposed)
  @@ -198,5 +198,8 @@
       supabaseAdmin := &service.SupabaseAdmin{
           BaseURL:        supabaseURL,
           ServiceRoleKey: supabaseKey,
           AppURL:         appURL,
  -        HTTPClient:     &http.Client{Timeout: 10 * time.Second},
  +        HTTPClient: &http.Client{
  +            Timeout:   10 * time.Second,
  +            Transport: observability.NewTracingTransport(http.DefaultTransport),
  +        },
       }

C3.1 — boot pgxpool.New error not captured

  --- backend/cmd/api/main.go (current)
  +++ backend/cmd/api/main.go (proposed)
  @@ -58,4 +58,10 @@
       pool, err := pgxpool.New(ctx, dbURL)
       if err != nil {
  +        observability.CaptureError(ctx, err, observability.Envelope{
  +            Event:    "boot_db_init_failed",
  +            Severity: observability.SeverityFatal,
  +        })
           log.Fatal(err)
       }

These 4 changes will also add this import:
  +    "github.com/agenticapps/cparx/backend/internal/observability"

Apply these 4 changes? [a]pply / [s]kip / [q]uit
```

User replies: `a`

```
Applying 4 changes to backend/cmd/api/main.go...
✓ C1.1 applied
✓ C2.1 applied
✓ C2.2 applied
✓ C3.1 applied
✓ import added

backend/cmd/api/main.go is in working tree. Review with `git diff`.
```

---

## Phase 4 — second group

```
─── File: backend/internal/llm/client.go (1 gap) ────────────────

C2.3 — Custom transport not composed with TracingTransport

  --- backend/internal/llm/client.go (current)
  +++ backend/internal/llm/client.go (proposed)
  @@ -69,3 +69,5 @@
       cfg.BaseURL = "https://openrouter.ai/api/v1"
  -    cfg.HTTPClient = &http.Client{Transport: newTransport()}
  +    cfg.HTTPClient = &http.Client{
  +        Transport: observability.NewTracingTransport(newTransport()),
  +    }
       return &Client{oai: openai.NewClientWithConfig(cfg)}

This change will also add this import:
  +    "github.com/agenticapps/cparx/backend/internal/observability"

Apply this 1 change? [a]pply / [s]kip / [q]uit
```

User replies: `a`

```
Applying 1 change to backend/internal/llm/client.go...
✓ C2.3 applied
✓ import added
```

---

## Phase 7 — verification

```
Running post-apply verification...
$ go build ./...
(no output — clean)

✓ Project still builds.
```

---

## Phase 8 — summary

```
scan-apply complete.
Applied:    5
Skipped:    0
Failed:     0
Stale:      0

The 7 medium-confidence business-event findings remain in
.scan-report.md. They need human review — only you know whether each
function is the canonical state-changing event worth recording. See
the report's "Medium-confidence findings" section.

Files modified:
  backend/cmd/api/main.go
  backend/internal/llm/client.go

Next: review with `git diff`, run your test suite, commit on a
feature branch per the project's PR workflow.
```

---

## What if the user said `s`?

If the user replied `s` to the first group:

```
Skipping all 4 changes in backend/cmd/api/main.go.
```

Then proceed to the second group. The skipped findings remain in
`.scan-report.md` under "High-confidence gaps" for a future run.

## What if the user said `q`?

```
Aborted. 0 of 5 changes applied. .scan-report.md unchanged.
```

The session exits without modifying any files or the report. The user
can re-run later.

## What if an Edit fails mid-run?

Suppose the user applied the C1.1 fix manually in their editor between
the scan and this apply session:

```
─── File: backend/cmd/api/main.go (4 gaps) ─────────────────────

[diffs shown]

Apply these 4 changes? [a]pply / [s]kip / [q]uit
> a

Applying 4 changes...
⚠ C1.1 failed: old_string not found in file (likely already applied
  or file modified since scan).
✓ C2.1 applied
✓ C2.2 applied
✓ C3.1 applied

1 of 4 changes failed. The failed change was marked stale in
.scan-report.md. Re-run `add-observability scan` to refresh, or apply
the change manually.
```

The other findings in the group still apply — a single stale finding
doesn't abort the group's work.
