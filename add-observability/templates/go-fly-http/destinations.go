// Destination registry — AgenticApps spec §10.8 multi-destination dispatch.
//
// Phase 21 / P2e. The Go reimplementation of the role-based destination
// registry the TS stacks ship. A role (errors / logs / analytics) maps to a
// named destination adapter (sentry / axiom) so the wrapper routes each
// observability concern without knowing about any specific SDK:
//
//	LogEvent     → logs-role adapter.Emit
//	CaptureError → errors-role adapter.CaptureException
//
// The wrapper builds the registry once in Init() and dispatches through it.
// The stdout mirror in emit() is universal (it is `fly logs`, not a
// "destination") and is therefore always written, independent of the
// registry.
//
// SAFETY (fail-closed): resolveConfig can only ever NARROW a hostile or
// malformed OBS_DESTINATIONS override toward the baked default. errors can
// NEVER be routed to the logs-only Axiom adapter (axiom does not declare the
// errors role) — so `errors=axiom` is rejected and the baked sentry default
// stands.
package {{PACKAGE_NAME}}

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/getsentry/sentry-go"
)

// ─── Role / destination names ────────────────────────────────────────────────

type Role string

const (
	RoleErrors    Role = "errors"
	RoleLogs      Role = "logs"
	RoleAnalytics Role = "analytics"
)

var allRoles = []Role{RoleErrors, RoleLogs, RoleAnalytics}

type destName string

const (
	destSentry destName = "sentry"
	destAxiom  destName = "axiom"
	destNone   destName = "none"
)

// ─── Destination interface ────────────────────────────────────────────────────

// Destination is a named observability sink. Adapters declare which roles
// they serve; the registry only ever routes a role to an adapter that
// declares it (enforced by resolveConfig). Init is called once for a
// configured adapter; Emit / CaptureException are dispatched per event and
// MUST NOT block the caller or panic into application code.
type Destination interface {
	Name() string
	SupportedRoles() []Role
	IsConfigured() bool
	Init()
	Emit(env Envelope, tc *TraceContext)
	CaptureException(err error, env Envelope, tc *TraceContext)
}

// ─── destinationsConfig + baked default ──────────────────────────────────────

type destinationsConfig struct {
	errors    destName
	logs      destName
	analytics destName
}

// bakedDefault is the generator-substituted default. errors→sentry,
// logs→axiom, analytics→none. resolveConfig starts here and only applies a
// legal OBS_DESTINATIONS override on top.
func bakedDefault() destinationsConfig {
	return destinationsConfig{
		errors:    destSentry,
		logs:      destAxiom,
		analytics: destNone,
	}
}

// adapterSupportedRoles is the single source of truth the fail-closed
// resolver reads WITHOUT constructing an adapter. sentry⇒errors+logs,
// axiom⇒logs+analytics (NO errors — this is what rejects errors=axiom).
var adapterSupportedRoles = map[destName][]Role{
	destSentry: {RoleErrors, RoleLogs},
	destAxiom:  {RoleLogs, RoleAnalytics},
}

func destDeclaresRole(name destName, role Role) bool {
	for _, r := range adapterSupportedRoles[name] {
		if r == role {
			return true
		}
	}
	return false
}

func isKnownRole(token string) bool {
	for _, r := range allRoles {
		if string(r) == token {
			return true
		}
	}
	return false
}

func isKnownDest(token string) bool {
	switch destName(token) {
	case destSentry, destAxiom, destNone:
		return true
	default:
		return false
	}
}

// ─── resolveConfig (FAIL-CLOSED) ─────────────────────────────────────────────

// resolveConfig returns the effective role→destination map. It starts from
// the baked default and applies the OBS_DESTINATIONS env override (format
// `errors=sentry,logs=axiom`) ON TOP — but only where the override is BOTH
// well-formed AND legal:
//
//   - A named dest is accepted for a role only if that adapter declares the
//     role (sentry⇒errors+logs, axiom⇒logs+analytics). `errors=axiom` is
//     therefore REJECTED, keeping the baked sentry default + warn.
//   - Unknown role / unknown dest token → ignore + warn per rejected pair.
//   - "none" is always legal for any role (disables that role).
//   - Malformed pair (no "=", empty key/value) → ignore + warn.
//   - Tokens are trimmed + lowercased before matching; last valid wins.
//
// Net guarantee: a malformed/hostile OBS_DESTINATIONS can only ever narrow
// toward the safe baked default; errors can NEVER resolve to axiom.
func resolveConfig() destinationsConfig {
	cfg := bakedDefault()

	raw := strings.TrimSpace(os.Getenv("OBS_DESTINATIONS"))
	if raw == "" {
		return cfg
	}

	warn := func(msg string) {
		logger.Warn("observability: OBS_DESTINATIONS " + msg + "; falling back to baked default for this key")
	}

	for _, pair := range strings.Split(raw, ",") {
		eq := strings.Index(pair, "=")
		if eq == -1 {
			warn(fmt.Sprintf("ignored malformed pair %q", strings.TrimSpace(pair)))
			continue
		}
		roleTok := strings.ToLower(strings.TrimSpace(pair[:eq]))
		destTok := strings.ToLower(strings.TrimSpace(pair[eq+1:]))

		if roleTok == "" || destTok == "" {
			warn(fmt.Sprintf("ignored empty key/value in %q", strings.TrimSpace(pair)))
			continue
		}
		if !isKnownRole(roleTok) {
			warn(fmt.Sprintf("ignored unknown role %q", roleTok))
			continue
		}
		if !isKnownDest(destTok) {
			warn(fmt.Sprintf("ignored unknown destination %q", destTok))
			continue
		}
		// "none" is always legal. A named adapter is legal for the role only
		// if it declares that role — the SAFETY gate that rejects errors=axiom.
		if destName(destTok) != destNone && !destDeclaresRole(destName(destTok), Role(roleTok)) {
			warn(fmt.Sprintf("rejected unsupported mapping %q=%q (adapter does not serve that role)", roleTok, destTok))
			continue
		}

		switch Role(roleTok) {
		case RoleErrors:
			cfg.errors = destName(destTok)
		case RoleLogs:
			cfg.logs = destName(destTok)
		case RoleAnalytics:
			cfg.analytics = destName(destTok)
		}
	}

	return cfg
}

// ─── registry ─────────────────────────────────────────────────────────────────

type registry struct {
	roleMap map[Role]Destination
}

// forRole returns the configured adapter for role, or nil (so an
// unconfigured destination degrades to a no-op rather than a nil-deref).
func (r *registry) forRole(role Role) Destination {
	if r == nil {
		return nil
	}
	return r.roleMap[role]
}

// buildRegistry constructs each distinct named adapter referenced by cfg
// exactly once, calls Init() on those that report IsConfigured(), and maps
// each role to its configured adapter (skipping "none" and unconfigured).
func buildRegistry(cfg destinationsConfig) *registry {
	adapters := map[destName]Destination{}
	configured := map[destName]bool{}

	ensure := func(name destName) Destination {
		if name == destNone {
			return nil
		}
		if a, ok := adapters[name]; ok {
			if configured[name] {
				return a
			}
			return nil
		}
		a := newAdapter(name)
		adapters[name] = a
		if a != nil && a.IsConfigured() {
			a.Init()
			configured[name] = true
			return a
		}
		return nil
	}

	roleMap := map[Role]Destination{}
	for _, role := range allRoles {
		var name destName
		switch role {
		case RoleErrors:
			name = cfg.errors
		case RoleLogs:
			name = cfg.logs
		case RoleAnalytics:
			name = cfg.analytics
		}
		if a := ensure(name); a != nil {
			roleMap[role] = a
		}
	}
	return &registry{roleMap: roleMap}
}

func newAdapter(name destName) Destination {
	switch name {
	case destSentry:
		return &sentryAdapter{}
	case destAxiom:
		return &axiomAdapter{}
	default:
		return nil
	}
}

// ─── module-level registry state (built by Init) ─────────────────────────────

var activeRegistry *registry

// resetForTest tears down the init-once latch and the active registry so a
// test can re-run Init() against a fresh environment. Test-only helper.
func resetForTest() {
	initOnce = sync.Once{}
	activeRegistry = nil
	sentryReady = false
}

// ─── sentryAdapter (errors + logs) ───────────────────────────────────────────

// sentryAdapter lifts the wrapper's existing inline Sentry handling into the
// destination layer. It serves the errors and logs roles. Emit adds a
// breadcrumb (so a subsequent CaptureException carries log context);
// CaptureException records the error with native trace context. All SDK calls
// run on the existing safeFireAndForget goroutine pool so they are drained by
// Flush and can never panic into the request path.
type sentryAdapter struct{}

func (s *sentryAdapter) Name() string           { return string(destSentry) }
func (s *sentryAdapter) SupportedRoles() []Role { return adapterSupportedRoles[destSentry] }

func (s *sentryAdapter) IsConfigured() bool {
	return os.Getenv("{{ENV_VAR_DSN}}") != ""
}

func (s *sentryAdapter) Init() {
	dsn := os.Getenv("{{ENV_VAR_DSN}}")
	if dsn == "" {
		return
	}
	// SENTRY_DEBUG=1 turns on sentry-go's verbose logging so the background
	// HTTP transport surfaces send failures to stderr. Useful during initial
	// DSN-wiring verification; leave unset in production.
	err := sentry.Init(sentry.ClientOptions{
		Dsn:              dsn,
		Environment:      deployEnv,
		Release:          serviceName,
		EnableTracing:    true,
		TracesSampleRate: traceSampleRate,
		SendDefaultPII:   false,
		Debug:            os.Getenv("SENTRY_DEBUG") == "1",
	})
	if err != nil {
		logger.Warn("observability: sentry init failed", "err", err.Error())
		return
	}
	sentryReady = true
}

// Emit adds a breadcrumb so the next CaptureException carries this context.
// Debug events are dropped (they are sampled out of the SDK path).
func (s *sentryAdapter) Emit(env Envelope, _ *TraceContext) {
	if !sentryReady || env.Severity == SeverityDebug {
		return
	}
	sev := env.Severity
	if sev == "" {
		sev = SeverityInfo
	}
	safeFireAndForget(func() {
		sentry.AddBreadcrumb(&sentry.Breadcrumb{
			Category: env.Event,
			Level:    sentryLevel(sev),
			Data:     redactObject(env.Attrs),
		})
	})
}

// CaptureException records err with native Sentry trace context. Moved
// verbatim from the wrapper's previous inline CaptureError body.
func (s *sentryAdapter) CaptureException(err error, env Envelope, tc *TraceContext) {
	if !sentryReady || err == nil {
		return
	}
	safeFireAndForget(func() {
		hub := sentry.CurrentHub().Clone()
		hub.WithScope(func(scope *sentry.Scope) {
			scope.SetTag("event", env.Event)
			scope.SetTag("service", serviceName)
			scope.SetTag("env", deployEnv)
			if tc != nil {
				// Native Sentry trace context — populates the Trace tab and
				// makes `trace:<hex>` queries match in Discover. The SetTag
				// pair below preserves free-form `trace_id:<hex>` search.
				traceCtx := map[string]any{
					"trace_id": tc.TraceID,
					"span_id":  tc.SpanID,
					"op":       env.Event,
					"status":   sentryTraceStatus(env.Severity),
				}
				if tc.ParentSpanID != "" {
					traceCtx["parent_span_id"] = tc.ParentSpanID
				}
				scope.SetContext("trace", traceCtx)
				scope.SetTag("trace_id", tc.TraceID)
				scope.SetTag("span_id", tc.SpanID)
			}
			if env.Attrs != nil {
				scope.SetContext("attrs", redactObject(env.Attrs))
			}
			hub.CaptureException(err)
		})
	})
}

// ─── axiomAdapter (logs + analytics — NO errors) ─────────────────────────────

const axiomWarnCooldown = 60 * time.Second

// axiomAdapter is a logs/analytics sink. It declares NO errors role (see
// adapterSupportedRoles), which is why resolveConfig rejects errors=axiom.
// Emit POSTs a single-element batch to the Axiom ingest endpoint on the
// existing safeFireAndForget goroutine pool (so Flush drains it).
// CaptureException is a no-op by contract.
//
// Never-throw: the egress goroutine recovers from any panic (via
// safeFireAndForget) and routes HTTP errors / non-2xx responses to a
// rate-limited warn — it can never crash the app.
type axiomAdapter struct {
	token     string
	dataset   string
	ingestURL string
	client    *http.Client

	warnMu    sync.Mutex
	lastWarn  time.Time
	suppressed int
}

func (a *axiomAdapter) Name() string           { return string(destAxiom) }
func (a *axiomAdapter) SupportedRoles() []Role { return adapterSupportedRoles[destAxiom] }

func (a *axiomAdapter) IsConfigured() bool {
	return os.Getenv("AXIOM_TOKEN") != "" && os.Getenv("AXIOM_DATASET") != ""
}

func (a *axiomAdapter) Init() {
	a.token = os.Getenv("AXIOM_TOKEN")
	a.dataset = os.Getenv("AXIOM_DATASET")
	if u := os.Getenv("AXIOM_INGEST_URL"); u != "" {
		a.ingestURL = u
	} else {
		a.ingestURL = fmt.Sprintf("https://api.axiom.co/v1/datasets/%s/ingest", a.dataset)
	}
	a.client = &http.Client{Timeout: 10 * time.Second}
}

// warnOnce collapses a burst of delivery failures into a single rate-limited
// log line per cooldown window, reporting how many were suppressed.
func (a *axiomAdapter) warnOnce() {
	a.warnMu.Lock()
	defer a.warnMu.Unlock()
	now := time.Now()
	if now.Sub(a.lastWarn) >= axiomWarnCooldown {
		if a.suppressed > 0 {
			logger.Warn(fmt.Sprintf("axiom: log delivery failing (%d suppressed)", a.suppressed))
		} else {
			logger.Warn("axiom: log delivery failing")
		}
		a.lastWarn = now
		a.suppressed = 0
	} else {
		a.suppressed++
	}
}

// Emit POSTs the envelope as a single-element batch. Fired on the
// safeFireAndForget pool so it is non-blocking, drained by Flush, and
// recover()-guarded against panics. HTTP errors and non-2xx responses route
// to the rate-limited warn — never to the caller.
func (a *axiomAdapter) Emit(env Envelope, tc *TraceContext) {
	if a.client == nil || a.token == "" || a.ingestURL == "" {
		return
	}

	// Build the wire record from the envelope. Mirrors the stdout event shape
	// so Axiom and `fly logs` agree.
	traceID, spanID := "", ""
	if tc != nil {
		traceID, spanID = tc.TraceID, tc.SpanID
	}
	sev := env.Severity
	if sev == "" {
		sev = SeverityInfo
	}
	record := map[string]any{
		"trace_id": traceID,
		"span_id":  spanID,
		"service":  serviceName,
		"env":      deployEnv,
		"event":    env.Event,
		"severity": string(sev),
		"attrs":    redactObject(env.Attrs),
		"ts":       time.Now().UnixMilli(),
	}

	body, err := json.Marshal([]map[string]any{record})
	if err != nil {
		a.warnOnce()
		return
	}

	safeFireAndForget(func() {
		req, err := http.NewRequestWithContext(context.Background(), http.MethodPost, a.ingestURL, bytes.NewReader(body))
		if err != nil {
			a.warnOnce()
			return
		}
		req.Header.Set("Authorization", "Bearer "+a.token)
		req.Header.Set("Content-Type", "application/json")

		resp, err := a.client.Do(req)
		if err != nil {
			a.warnOnce()
			return
		}
		// Drain + close so the connection can be reused; never let a read
		// error escape.
		defer resp.Body.Close()
		_, _ = io.Copy(io.Discard, resp.Body)
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			a.warnOnce()
		}
	})
}

// CaptureException is a no-op — Axiom never captures errors (no errors role).
func (a *axiomAdapter) CaptureException(_ error, _ Envelope, _ *TraceContext) {}
