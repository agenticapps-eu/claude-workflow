// WARNING — healthz snippet is a TEMPLATE, not a library.
//
// Before mounting:
//
//  1. Copy this file into your routes layer (e.g. internal/routes/healthz.go)
//     and mount the returned handler with mux.HandleFunc("/healthz", h).
//  2. ADAPT the dependency probes to YOUR project's actual dependencies.
//     Unadapted probes for non-existent deps will report degraded. Zero
//     probes configured → endpoint returns 503 (fail-closed).
//  3. Review SECURITY: per-check breakdown leaks internal topology. For
//     public endpoints, consider `?detail=true` opt-in (the T14 runbook
//     describes the gating pattern).
//
// Do NOT import this file directly from elsewhere in your app.
//
// ─────────────────────────────────────────────────────────────────────────────
//
// healthz_snippet.go — copy-only healthz handler for go-fly-http.
//
// Per phase-22 CONTEXT D9 the healthz endpoint is NOT wrapped by the
// observability middleware (no span overhead on the heartbeat). Per PLAN R06
// the handler is fail-closed when zero probes are configured: an unadapted
// snippet reports degraded with a clear `reason` field rather than reporting
// "ok" and lulling the operator into thinking dependencies are being
// monitored.
//
// Probe interfaces are deliberately minimal so the operator can satisfy them
// with anything — *sql.DB satisfies dbProbe (it has PingContext), the stdlib
// http.Client satisfies upstreamProbe (it has Get), and bespoke wrappers can
// supply the same two methods if they need redaction or auth threading.
//
// Adaptation example:
//
//	mux := http.NewServeMux()
//	mux.HandleFunc("/healthz", HealthzHandler(HealthzDeps{
//		DB:       sqlDB,                 // *sql.DB
//		Upstream: http.DefaultClient,    // probes its own /healthz route
//	}))
package {{PACKAGE_NAME}}

import (
	"context"
	"encoding/json"
	"net/http"
	"time"
)

// ─── Constants ────────────────────────────────────────────────────────────────

// defaultHealthzProbeTimeout is the per-probe deadline applied when
// HealthzDeps.ProbeTimeout is zero. 2 s matches the TS stacks' default.
//
// D-03 (narrowed for Go per codex MEDIUM-5 / R-rev-3): Go's handler-latency
// approach differs from the TS AbortController pattern: the DB probe wraps
// r.Context() in context.WithTimeout so cancellation flows through the driver;
// the upstream probe uses a goroutine + select with time.After (no signal path
// on the stdlib http.Client.Get surface). Both honour ProbeTimeout == 0 → 2 s.
const defaultHealthzProbeTimeout = 2 * time.Second

// ─── Probe interfaces ─────────────────────────────────────────────────────────

// dbProbe is the minimal surface HealthzHandler needs from a database
// handle. *sql.DB satisfies it.
type dbProbe interface {
	PingContext(ctx context.Context) error
}

// upstreamProbe is the minimal surface HealthzHandler needs from an upstream
// HTTP client. *http.Client satisfies it; bespoke clients only need a
// `Get(url) (*http.Response, error)` method.
type upstreamProbe interface {
	Get(url string) (*http.Response, error)
}

// HealthzDeps bundles the optional probes a healthz handler can run.
// Leave fields nil to skip a probe; a probe set to nil never contributes
// to the `checks` map. Zero probes configured → fail-closed (R06).
type HealthzDeps struct {
	// DB is probed via PingContext using a timeout-bounded context derived
	// from the request context. context.DeadlineExceeded → "timeout" sentinel.
	DB dbProbe
	// Upstream is probed via Get("https://internal/healthz") (adapt the URL
	// in the impl below if your upstream uses a different path). Any 5xx
	// response, or any returned error, flips the probe to false. A probe that
	// does not return within ProbeTimeout → "timeout" sentinel (race-only via
	// time.After; stdlib http.Client.Get has no signal path).
	Upstream upstreamProbe
	// ProbeTimeout is the per-probe deadline. Zero → defaultHealthzProbeTimeout (2 s).
	ProbeTimeout time.Duration
}

// ─── Handler ─────────────────────────────────────────────────────────────────

// HealthzHandler constructs an http.HandlerFunc that aggregates the deps'
// probes into a single JSON response.
//
// Returns:
//
//	200 + {"status":"ok","checks":{...:true}}              all probes passed
//	503 + {"status":"degraded","checks":{...}}             one+ probes failed
//	503 + {"status":"degraded","reason":...,"checks":{}}   no probes (R06)
//
// Per-probe errors are swallowed and recorded as `false` or `"timeout"`;
// one probe failing never short-circuits the others.
func HealthzHandler(deps HealthzDeps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		checks := map[string]any{}

		probeTimeout := deps.ProbeTimeout
		if probeTimeout == 0 {
			probeTimeout = defaultHealthzProbeTimeout
		}

		if deps.DB != nil {
			// DB probe: context.WithTimeout so the driver honours cancellation.
			// context.DeadlineExceeded → "timeout" sentinel (R-rev-3 / D-03).
			ctx, cancel := context.WithTimeout(r.Context(), probeTimeout)
			defer cancel()
			if err := deps.DB.PingContext(ctx); err == nil {
				checks["db"] = true
			} else if err == context.DeadlineExceeded {
				checks["db"] = "timeout"
			} else {
				checks["db"] = false
			}
		}

		if deps.Upstream != nil {
			// Upstream probe: race-only via goroutine + time.After.
			// stdlib http.Client.Get has no AbortSignal/context path on the
			// upstreamProbe interface, so we use a goroutine race.
			type result struct {
				resp *http.Response
				err  error
			}
			done := make(chan result, 1)
			go func() {
				resp, err := deps.Upstream.Get("https://internal/healthz")
				done <- result{resp, err}
			}()
			select {
			case res := <-done:
				switch {
				case res.err != nil:
					checks["upstream"] = false
				case res.resp == nil:
					checks["upstream"] = false
				default:
					checks["upstream"] = res.resp.StatusCode < 500
					if res.resp.Body != nil {
						_ = res.resp.Body.Close()
					}
				}
			case <-time.After(probeTimeout):
				checks["upstream"] = "timeout"
			}
		}

		w.Header().Set("Content-Type", "application/json")

		// R06 — fail-closed when no probes are configured.
		if len(checks) == 0 {
			w.WriteHeader(http.StatusServiceUnavailable)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"status": "degraded",
				"reason": "no probes configured — adapt healthz_snippet.go to your dependencies",
				"checks": map[string]any{},
			})
			return
		}

		allOK := true
		for _, v := range checks {
			if v != true {
				allOK = false
				break
			}
		}
		status := "degraded"
		code := http.StatusServiceUnavailable
		if allOK {
			status = "ok"
			code = http.StatusOK
		}
		w.WriteHeader(code)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status": status,
			"checks": checks,
		})
	}
}
