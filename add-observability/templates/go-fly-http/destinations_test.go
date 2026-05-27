// Destination-registry role-dispatch + failure-path tests — spec §10.8.
//
// Phase 21 / P2e. These tests exercise the Go destinations layer: the
// role-based registry (resolveConfig fail-closed), the sentry + axiom
// adapters, and the never-throw egress path. They use an httptest.Server
// as the fake Axiom ingest endpoint, injected via AXIOM_INGEST_URL.
//
// These tests live alongside (do NOT replace) observability_test.go; the
// 16 contract tests there MUST stay green.
package {{PACKAGE_NAME}}

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

// withEnv sets env vars for the duration of a test and restores them after.
// It also resets the module-level registry/init state so each test builds a
// fresh registry from its own env.
func withEnv(t *testing.T, kv map[string]string) {
	t.Helper()
	for k, v := range kv {
		t.Setenv(k, v)
	}
	resetForTest()
}

// ─── Case 1: errors=sentry, logs=axiom ───────────────────────────────────────
//
// LogEvent → exactly one POST to the Axiom test server with bearer auth and a
// single-element [envelope] body (drained via Flush). CaptureError must NOT
// POST to Axiom (errors role is sentry, which is unconfigured here ⇒ no-op
// sentry, definitely no axiom error POST).
func TestRoleDispatchSentryErrorsAxiomLogs(t *testing.T) {
	var logPosts atomic.Int32
	var sawBearer atomic.Bool
	var sawBatch atomic.Bool

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		logPosts.Add(1)
		if r.Header.Get("Authorization") == "Bearer test-token" {
			sawBearer.Store(true)
		}
		body, _ := io.ReadAll(r.Body)
		s := string(body)
		// body must be a JSON array (single-element batch)
		if len(s) > 0 && s[0] == '[' {
			sawBatch.Store(true)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	withEnv(t, map[string]string{
		"OBS_DESTINATIONS": "errors=sentry,logs=axiom",
		"AXIOM_TOKEN":      "test-token",
		"AXIOM_DATASET":    "test-dataset",
		"AXIOM_INGEST_URL": srv.URL,
		// SENTRY_DSN intentionally unset — sentry adapter unconfigured.
	})
	Init()

	LogEvent(context.Background(), Envelope{Event: "log_event", Severity: SeverityInfo})
	CaptureError(context.Background(), errors.New("boom"), Envelope{Event: "err_event"})

	if !Flush(2 * time.Second) {
		t.Fatal("Flush returned false — axiom emit goroutine not drained")
	}

	if got := logPosts.Load(); got != 1 {
		t.Errorf("expected exactly 1 POST to axiom, got %d", got)
	}
	if !sawBearer.Load() {
		t.Error("axiom POST missing 'Authorization: Bearer test-token' header")
	}
	if !sawBatch.Load() {
		t.Error("axiom POST body was not a JSON array [envelope]")
	}
}

// ─── Case 2: errors=sentry, logs=none ────────────────────────────────────────
func TestRoleDispatchLogsNone(t *testing.T) {
	var posts atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		posts.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	withEnv(t, map[string]string{
		"OBS_DESTINATIONS": "errors=sentry,logs=none",
		"AXIOM_TOKEN":      "test-token",
		"AXIOM_DATASET":    "test-dataset",
		"AXIOM_INGEST_URL": srv.URL,
	})
	Init()

	LogEvent(context.Background(), Envelope{Event: "log_event", Severity: SeverityInfo})
	if !Flush(2 * time.Second) {
		t.Fatal("Flush returned false")
	}
	if got := posts.Load(); got != 0 {
		t.Errorf("logs=none must not POST to axiom, got %d POSTs", got)
	}
}

// ─── Case 3: errors=none, logs=axiom ─────────────────────────────────────────
//
// LogEvent → POST; CaptureError → no-op (errors=none), no panic.
func TestRoleDispatchErrorsNone(t *testing.T) {
	var posts atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		posts.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	withEnv(t, map[string]string{
		"OBS_DESTINATIONS": "errors=none,logs=axiom",
		"AXIOM_TOKEN":      "test-token",
		"AXIOM_DATASET":    "test-dataset",
		"AXIOM_INGEST_URL": srv.URL,
	})
	Init()

	defer func() {
		if r := recover(); r != nil {
			t.Errorf("CaptureError with errors=none panicked: %v", r)
		}
	}()
	LogEvent(context.Background(), Envelope{Event: "log_event", Severity: SeverityInfo})
	CaptureError(context.Background(), errors.New("boom"), Envelope{Event: "err_event"})

	if !Flush(2 * time.Second) {
		t.Fatal("Flush returned false")
	}
	if got := posts.Load(); got != 1 {
		t.Errorf("logs=axiom expected 1 POST, got %d", got)
	}
}

// ─── Case 4: errors=none, logs=none ──────────────────────────────────────────
func TestRoleDispatchBothNone(t *testing.T) {
	var posts atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		posts.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	withEnv(t, map[string]string{
		"OBS_DESTINATIONS": "errors=none,logs=none",
		"AXIOM_TOKEN":      "test-token",
		"AXIOM_DATASET":    "test-dataset",
		"AXIOM_INGEST_URL": srv.URL,
	})
	Init()

	defer func() {
		if r := recover(); r != nil {
			t.Errorf("both-none panicked: %v", r)
		}
	}()
	LogEvent(context.Background(), Envelope{Event: "log_event", Severity: SeverityInfo})
	CaptureError(context.Background(), errors.New("boom"), Envelope{Event: "err_event"})

	if !Flush(2 * time.Second) {
		t.Fatal("Flush returned false")
	}
	if got := posts.Load(); got != 0 {
		t.Errorf("both none must not POST, got %d", got)
	}
}

// ─── Case 5: fail-closed resolveConfig ───────────────────────────────────────
//
// OBS_DESTINATIONS=errors=axiom must be REJECTED — axiom does not declare the
// errors role — so resolved.errors stays "sentry" (the baked default).
func TestResolveConfigFailClosedErrorsAxiom(t *testing.T) {
	t.Setenv("OBS_DESTINATIONS", "errors=axiom")
	cfg := resolveConfig()
	if cfg.errors != "sentry" {
		t.Errorf("fail-closed: errors=axiom must be rejected, errors stayed %q (want sentry)", cfg.errors)
	}
	if cfg.logs != "axiom" {
		t.Errorf("baked logs default should remain axiom, got %q", cfg.logs)
	}
}

func TestResolveConfigDefaults(t *testing.T) {
	t.Setenv("OBS_DESTINATIONS", "")
	cfg := resolveConfig()
	if cfg.errors != "sentry" || cfg.logs != "axiom" || cfg.analytics != "none" {
		t.Errorf("baked defaults wrong: %+v", cfg)
	}
}

func TestResolveConfigUnknownTokensIgnored(t *testing.T) {
	t.Setenv("OBS_DESTINATIONS", "errors=bogus,frobnicate=sentry,logs=axiom,malformedpair")
	cfg := resolveConfig()
	if cfg.errors != "sentry" {
		t.Errorf("unknown dest must be ignored, errors=%q", cfg.errors)
	}
	if cfg.logs != "axiom" {
		t.Errorf("valid logs=axiom should apply, got %q", cfg.logs)
	}
}

// ─── Case 6: never-throw on 500 / closed connection ──────────────────────────
func TestAxiomNeverThrowsOn500(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()

	withEnv(t, map[string]string{
		"OBS_DESTINATIONS": "errors=sentry,logs=axiom",
		"AXIOM_TOKEN":      "test-token",
		"AXIOM_DATASET":    "test-dataset",
		"AXIOM_INGEST_URL": srv.URL,
	})
	Init()

	defer func() {
		if r := recover(); r != nil {
			t.Errorf("axiom 500 path panicked: %v", r)
		}
	}()
	LogEvent(context.Background(), Envelope{Event: "log_event", Severity: SeverityInfo})
	if !Flush(2 * time.Second) {
		t.Fatal("Flush returned false after a 500 — emit goroutine should still complete")
	}
}

func TestAxiomNeverThrowsOnClosedConnection(t *testing.T) {
	// Server that hijacks and immediately closes the connection — forces a
	// transport-level error in the egress goroutine.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hj, ok := w.(http.Hijacker)
		if !ok {
			return
		}
		conn, _, err := hj.Hijack()
		if err == nil {
			_ = conn.Close()
		}
	}))
	defer srv.Close()

	withEnv(t, map[string]string{
		"OBS_DESTINATIONS": "errors=sentry,logs=axiom",
		"AXIOM_TOKEN":      "test-token",
		"AXIOM_DATASET":    "test-dataset",
		"AXIOM_INGEST_URL": srv.URL,
	})
	Init()

	defer func() {
		if r := recover(); r != nil {
			t.Errorf("axiom closed-connection path panicked: %v", r)
		}
	}()
	LogEvent(context.Background(), Envelope{Event: "log_event", Severity: SeverityInfo})
	if !Flush(2 * time.Second) {
		t.Fatal("Flush returned false after a closed connection — emit goroutine should still complete")
	}
}
