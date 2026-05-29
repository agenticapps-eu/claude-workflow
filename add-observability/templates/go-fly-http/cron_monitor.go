// WithCronMonitor — Sentry Crons heartbeat wrapper for go-fly-http handlers.
// See ../../.planning/phases/22-sentry-crons-healthz/CONTEXT.md (D1 separate
// wrapper, D5d Go composition order, D6 3-source slug resolution, D11 multi-
// cron explicit-slug requirement, D12 monitorConfig forwarding).
//
// Composes INNERMOST per D5d:
//
//	chain := middleware(WithCronMonitor(ctx, fn, opts...))
//
// Functional-options API (idiomatic Go). The wrapper:
//   - no-ops when SENTRY_DSN is unset (fail-safe per PLAN R02);
//   - resolves the monitor slug per D6 (explicit > env > auto-derive);
//   - forwards Sentry's MonitorConfig (schedule + maxRuntime) as the 2nd arg
//     on the in_progress checkin only — completion checkins pass nil;
//   - swallows panics from the SDK ingress so the cron never fails because the
//     heartbeat fails. SENTRY_DEBUG=1 surfaces swallowed errors via
//     debugLogFn (R04). Both seams are package-level so tests can swap them.
//
// Spec note (R05): sentry.CaptureCheckIn returns *sentry.EventID, not
// sentry.EventID. The seam below mirrors that signature so the impl can
// nil-check the returned pointer to skip completion checkins after a
// swallowed in_progress checkin.
//
// SDK gap (D-09 / Phase 23): unlike `@sentry/javascript`'s `Sentry.withMonitor`,
// `sentry-go` ships no `WithMonitor` equivalent — only the lower-level
// `CaptureCheckIn`. This `WithCronMonitor` IS the cross-stack parity for the
// missing helper. If a future `sentry-go` release adds `WithMonitor`, this
// impl can be slimmed to a composition; see `docs/decisions/0029-cron-monitor-sdk-composition.md`.
package {{PACKAGE_NAME}}

import (
	"context"
	"fmt"
	"os"
	"strings"

	sentry "github.com/getsentry/sentry-go"
)

// ─── Functional options ───────────────────────────────────────────────────────

// CronMonitorOption configures WithCronMonitor.
type CronMonitorOption func(*cronMonitorConfig)

// cronMonitorConfig is the resolved option bag.
type cronMonitorConfig struct {
	monitorSlug       string
	handlerName       string
	cronExpression    string
	schedule          sentry.MonitorSchedule
	maxRuntimeSeconds int
}

// WithMonitorSlug sets an explicit Sentry monitor slug. Takes precedence over
// the env-var and auto-derive sources (D6 row 1).
//
// REQUIRED for multi-cron workers per D11 — env-key form cannot disambiguate
// multiple handlers and the auto-derived shape will produce per-handler slugs
// the operator may not have provisioned.
func WithMonitorSlug(slug string) CronMonitorOption {
	return func(c *cronMonitorConfig) { c.monitorSlug = slug }
}

// WithHandlerName names the handler for env-var key derivation
// (`SENTRY_CRON_MONITOR_SLUG_<HANDLER>`). Defaults to "scheduled".
func WithHandlerName(name string) CronMonitorOption {
	return func(c *cronMonitorConfig) { c.handlerName = name }
}

// WithCronExpression provides the cron expression used for slug auto-derive
// (D6 row 3). The Go stack has no controller object to read this from at
// runtime (unlike the Cloudflare Worker `controller.cron`), so the caller
// supplies it explicitly. The expression is also a candidate for the
// MonitorConfig schedule when WithMonitorSchedule is not provided — but the
// caller is expected to set the schedule explicitly via WithMonitorSchedule.
func WithCronExpression(expr string) CronMonitorOption {
	return func(c *cronMonitorConfig) { c.cronExpression = expr }
}

// WithMonitorSchedule forwards a Sentry monitor schedule (crontab or interval)
// as MonitorConfig.Schedule on the in_progress checkin (D12). Use
// sentry.CrontabSchedule("*/15 * * * *") or sentry.IntervalSchedule(...).
//
// NOTE (deviation from PLAN sketch): sentry.MonitorSchedule is an interface in
// sentry-go v0.31.0, not a struct. The PLAN sketched `*sentry.MonitorSchedule`
// (pointer-to-interface) which is non-idiomatic Go. We take the interface
// value directly; nil is the unset sentinel.
func WithMonitorSchedule(s sentry.MonitorSchedule) CronMonitorOption {
	return func(c *cronMonitorConfig) { c.schedule = s }
}

// WithMaxRuntimeSeconds forwards a max-runtime metadata hint as
// MonitorConfig.MaxRuntime on the in_progress checkin (D12). Metadata-only;
// not enforced client-side (see CONTEXT N5).
//
// Wrapper-API unit is SECONDS (matches the cross-stack contract). The value is
// forwarded into sentry-go's MonitorConfig.MaxRuntime field as-is so the
// in-Sentry numeric value is identical across all 4 stacks; operators reading
// the Sentry monitor see the same number they passed to the wrapper.
func WithMaxRuntimeSeconds(s int) CronMonitorOption {
	return func(c *cronMonitorConfig) { c.maxRuntimeSeconds = s }
}

// ─── Package-level seams (test stubs swap these) ──────────────────────────────

// captureCheckinFn is the package-level seam for sentry.CaptureCheckIn.
//
// PER R05: returns *sentry.EventID (not sentry.EventID). Callers nil-check the
// returned pointer to detect a swallowed checkin (so the completion checkin is
// skipped rather than fired with a zero ID).
//
// MUST NOT use t.Parallel() in tests that swap this fn — it is package-level
// state shared across goroutines.
var captureCheckinFn = func(checkIn *sentry.CheckIn, monitorConfig *sentry.MonitorConfig) *sentry.EventID {
	return sentry.CaptureCheckIn(checkIn, monitorConfig)
}

// debugLogFn is the package-level seam for the SENTRY_DEBUG console surface
// (R04). Default prints to stderr via fmt.Fprintf so the cron's stdout JSON
// log stream stays clean. Tests swap this to assert on the surfaced messages.
//
// MUST NOT use t.Parallel() in tests that swap this fn — it is package-level
// state shared across goroutines.
var debugLogFn = func(msg string, err error) {
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: %v\n", msg, err)
	} else {
		fmt.Fprintln(os.Stderr, msg)
	}
}

// ─── Internal helpers ─────────────────────────────────────────────────────────

const cronSlugEnvPrefix = "SENTRY_CRON_MONITOR_SLUG_"

func cronIsConfigured() bool {
	return os.Getenv("SENTRY_DSN") != ""
}

func cronIsDebug() bool {
	return os.Getenv("SENTRY_DEBUG") == "1"
}

// resolveCronSlug implements D6 — 3-source slug resolution (precedence:
// explicit > env > auto-derive). Go's auto-derive uses the explicit
// cronExpression option because the Go runtime provides no controller from
// which to read the schedule (unlike the Cloudflare Worker stack).
func resolveCronSlug(cfg *cronMonitorConfig) string {
	// 1. Explicit.
	if cfg.monitorSlug != "" {
		return cfg.monitorSlug
	}
	// 2. Env: SENTRY_CRON_MONITOR_SLUG_<HANDLER> (uppercased, hyphens → underscores).
	handlerName := cfg.handlerName
	if handlerName == "" {
		handlerName = "scheduled"
	}
	envKey := cronSlugEnvPrefix + strings.ReplaceAll(strings.ToUpper(handlerName), "-", "_")
	if v := os.Getenv(envKey); v != "" {
		return v
	}
	// 3. Auto-derive: `${SERVICE_NAME ?? "service"}:${cronExpression ?? "scheduled"}`.
	svc := os.Getenv("SERVICE_NAME")
	if svc == "" {
		svc = "service"
	}
	expr := cfg.cronExpression
	if expr == "" {
		expr = "scheduled"
	}
	return svc + ":" + expr
}

// buildCronMonitorConfig assembles the Sentry MonitorConfig 2nd arg from the
// resolved options. Returns nil when neither schedule nor maxRuntime is set —
// causing the impl to omit the 2nd arg entirely on the in_progress call
// (and unconditionally on completion calls per D12).
func buildCronMonitorConfig(cfg *cronMonitorConfig) *sentry.MonitorConfig {
	if cfg.schedule == nil && cfg.maxRuntimeSeconds == 0 {
		return nil
	}
	mc := &sentry.MonitorConfig{}
	if cfg.schedule != nil {
		mc.Schedule = cfg.schedule
	}
	if cfg.maxRuntimeSeconds > 0 {
		mc.MaxRuntime = int64(cfg.maxRuntimeSeconds)
	}
	return mc
}

// safeCaptureCheckin wraps captureCheckinFn in a recover() so an SDK panic
// during a checkin never crashes the cron. Returns the EventID pointer (nil on
// swallow). When SENTRY_DEBUG=1 and a panic was swallowed, the recovered
// value is surfaced via debugLogFn (R04).
func safeCaptureCheckin(label string, c *sentry.CheckIn, mc *sentry.MonitorConfig) (out *sentry.EventID) {
	defer func() {
		if r := recover(); r != nil {
			out = nil
			if cronIsDebug() {
				err, ok := r.(error)
				if !ok {
					err = fmt.Errorf("%v", r)
				}
				debugLogFn("[WithCronMonitor] "+label+" checkin failed", err)
			}
		}
	}()
	return captureCheckinFn(c, mc)
}

// ─── Public wrapper ───────────────────────────────────────────────────────────

// WithCronMonitor wraps fn with Sentry Crons heartbeats (in_progress → ok |
// error). Composes INNERMOST per D5d so the rethrown error still propagates
// to the outer observability middleware's capture path.
//
// Behaviour:
//   - No-ops when SENTRY_DSN is unset (fail-safe per PLAN R02). fn still runs.
//   - Slug resolves per D6 (explicit > env > auto-derive).
//   - MonitorConfig (schedule + maxRuntime) is forwarded as Sentry's 2nd arg
//     on the in_progress checkin only; subsequent ok/error checkins pass nil
//     (Sentry treats the monitor as already-configured after the UPSERT).
//   - SDK panics during a checkin are recovered; opt-in SENTRY_DEBUG=1
//     surfaces them via debugLogFn.
//   - Handler errors are returned to the caller after the error checkin so
//     the outer middleware still records them.
//
// ctx is currently unused — accepted for future extension (e.g. tracing the
// heartbeat under the request span).
func WithCronMonitor(ctx context.Context, fn func() error, opts ...CronMonitorOption) error {
	_ = ctx

	cfg := &cronMonitorConfig{}
	for _, opt := range opts {
		opt(cfg)
	}

	if !cronIsConfigured() {
		return fn()
	}

	slug := resolveCronSlug(cfg)
	monitorConfig := buildCronMonitorConfig(cfg)

	// in_progress checkin — captures checkInID for the completion call.
	// The recover()'d safeCaptureCheckin returns nil if the SDK throws; we
	// then skip the completion checkin (better than firing with a zero ID).
	inProgress := &sentry.CheckIn{
		MonitorSlug: slug,
		Status:      sentry.CheckInStatusInProgress,
	}
	checkInID := safeCaptureCheckin("in_progress", inProgress, monitorConfig)

	err := fn()
	if err != nil {
		if checkInID != nil {
			// Completion checkin carries the ID + slug; monitorConfig is nil
			// per D12 (only in_progress UPSERTs the monitor config).
			safeCaptureCheckin("error", &sentry.CheckIn{
				ID:          *checkInID,
				MonitorSlug: slug,
				Status:      sentry.CheckInStatusError,
			}, nil)
		}
		return err
	}
	if checkInID != nil {
		safeCaptureCheckin("ok", &sentry.CheckIn{
			ID:          *checkInID,
			MonitorSlug: slug,
			Status:      sentry.CheckInStatusOK,
		}, nil)
	}
	return nil
}
