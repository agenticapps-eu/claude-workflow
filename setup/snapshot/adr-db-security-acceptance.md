# ADR Template — Database Security Acceptance

Use this template when accepting a Critical or High severity finding from
`database-sentinel:audit` instead of fixing it. The acceptance must be
recorded in a project ADR (e.g. `docs/decisions/NNNN-db-acceptance-...md`)
or appended as a "Database Security Acceptance" section inside an existing
ADR that documents the broader decision.

Without this acceptance record, Critical / High `database-sentinel` findings
BLOCK branch close per the post-phase security sub-gate
(`templates/config-hooks.json` → `post_phase.security.sub_gates`).

---

## Database Security Acceptance

- **Finding:** [database-sentinel ID and description, e.g. `RLS-007: profiles.email column readable without RLS check`]
- **Severity:** [Critical / High]
- **Why we are not fixing now:** [Reason — pre-launch deadline, dependency chain, scope cut, etc.]
- **Compensating control:** [What mitigates the risk in the meantime — application-layer check, monitoring rule, scope restriction, etc.]
- **Owner:** [Name of person accountable for the eventual fix]
- **Re-audit date:** [Date when the acceptance expires and the finding must be re-evaluated, YYYY-MM-DD]

---

## Usage notes

- An acceptance is **time-boxed**: the re-audit date is mandatory, not optional. An acceptance that has passed its re-audit date is treated as a renewed Critical/High finding and re-blocks branch close.
- The compensating control must be **concrete and verifiable**, not aspirational. "We trust the application layer" is not a control; "the API endpoint at `/api/profiles/:id` enforces `req.user.id === id` before returning email" is a control.
- One acceptance per finding. Do not bundle.
- The owner is a person, not a team — single point of accountability.
