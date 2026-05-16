// agenticapps:observability:start
//
// Observability wrapper — materialised by `/add-observability init`.
// Source template: add-observability/templates/go-fly-http/observability.go
// Parameters substituted:
//   PACKAGE_NAME=observability
//   MODULE_PATH=example.com/fixture-gorilla/internal/observability
//   SERVICE_NAME=fixture-gorilla
//   ENV_VAR_DSN=SENTRY_DSN
//   ENV_VAR_ENV=DEPLOY_ENV
//   ENV_VAR_SERVICE=SERVICE_NAME
//   DESTINATION=sentry
//   DEBUG_SAMPLE_RATE=0.1
//   TRACE_SAMPLE_RATE=0.1
//   REDACTED_KEYS=["password","token","api_key","card_number","cvv","ssn","secret","client_secret","refresh_token","access_token"]
//
// Fixture stub — the real init produces ~15k of token-substituted template
// content (see add-observability/templates/go-fly-http/observability.go).
// This file is the structural placeholder used by run-tests.sh comparisons.

package observability

import (
	"context"
	"net/http"
)

func Init() {}

type TraceContext struct {
	TraceID string
	SpanID  string
}

type Envelope struct {
	Event    string
	Severity string
	Attrs    map[string]any
}

type Span struct{}

func (s *Span) End()                                {}
func (s *Span) EndWithStatus(_ Status)              {}
func (s *Span) SetAttribute(_ string, _ any)        {}

type Status int

const (
	StatusOK Status = iota
	StatusError
	SeverityFatal = "fatal"
)

func ParseTraceparent(_ string) (TraceContext, bool) { return TraceContext{}, false }
func NewRootContext() TraceContext                   { return TraceContext{} }
func FormatTraceparent(_ TraceContext) string        { return "" }
func WithContext(ctx context.Context, _ TraceContext) context.Context {
	return ctx
}
func FromContext(_ context.Context) *TraceContext { return nil }
func StartSpan(ctx context.Context, _ string, _ map[string]any) (context.Context, *Span) {
	return ctx, &Span{}
}
func CaptureError(_ context.Context, _ error, _ Envelope) {}

func NewTracingTransport(base http.RoundTripper) http.RoundTripper {
	if base == nil {
		base = http.DefaultTransport
	}
	return base
}
// agenticapps:observability:end
