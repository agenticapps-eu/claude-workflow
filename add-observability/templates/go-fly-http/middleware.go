// Package {{PACKAGE_NAME}} — HTTP middleware satisfying spec §10.4 #1.
//
// Wraps an http.Handler so every request:
//
//  1. Parses inbound `traceparent` (or generates a fresh trace context).
//  2. Binds the trace context to the request context for handler use.
//  3. Captures unhandled panics via CaptureError before re-raising.
//  4. Echoes traceparent on the response so downstream callers can chain.
//
// Compatible with net/http, chi, echo, gorilla/mux, and any router that
// accepts http.Handler middleware.
//
// Use as:
//
//	mux := http.NewServeMux()
//	mux.HandleFunc("/api/users", createUser)
//	srv := &http.Server{
//	    Addr:    ":8080",
//	    Handler: observability.Middleware(mux),
//	}
//
// For chi:
//
//	r.Use(observability.Middleware)
//
// Install once in main():
//
//	observability.Init()
//	// ... wire handlers ...
package {{PACKAGE_NAME}}

import (
	"fmt"
	"net/http"
)

// Middleware wraps next so every request runs with trace context bound.
func Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		Init() // idempotent; safe to call per-request

		tc, ok := ParseTraceparent(r.Header.Get("traceparent"))
		if !ok {
			tc = NewRootContext()
		}
		ctx := WithContext(r.Context(), tc)

		spanName := fmt.Sprintf("%s %s", r.Method, r.URL.Path)
		ctx, span := StartSpan(ctx, spanName, map[string]any{
			"http.method": r.Method,
			"http.path":   r.URL.Path,
			"http.host":   r.Host,
		})
		defer func() {
			if rec := recover(); rec != nil {
				err, ok := rec.(error)
				if !ok {
					err = fmt.Errorf("panic: %v", rec)
				}
				CaptureError(ctx, err, Envelope{
					Event:    "unhandled_request_panic",
					Severity: SeverityFatal,
					Attrs:    map[string]any{"http.method": r.Method, "http.path": r.URL.Path},
				})
				span.EndWithStatus(StatusError)
				panic(rec) // re-raise so the server can log/return 500
			}
		}()

		// Wrap ResponseWriter to capture status code.
		rw := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

		// Echo traceparent on the response.
		rw.Header().Set("traceparent", FormatTraceparent(tc))

		next.ServeHTTP(rw, r.WithContext(ctx))

		span.SetAttribute("http.status", rw.status)
		if rw.status >= 500 {
			span.EndWithStatus(StatusError)
		} else {
			span.End()
		}
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status      int
	wroteHeader bool
}

func (s *statusRecorder) WriteHeader(code int) {
	if !s.wroteHeader {
		s.status = code
		s.wroteHeader = true
	}
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusRecorder) Write(b []byte) (int, error) {
	if !s.wroteHeader {
		s.WriteHeader(http.StatusOK)
	}
	return s.ResponseWriter.Write(b)
}

// ─── Outbound HTTP client ─────────────────────────────────────────────────

// TracingTransport is an http.RoundTripper that injects the active
// `traceparent` header on outbound requests.
//
// Use as:
//
//	client := &http.Client{Transport: observability.TracingTransport(http.DefaultTransport)}
//
// Or wrap the default client at boot:
//
//	http.DefaultClient.Transport = observability.TracingTransport(http.DefaultTransport)
type TracingTransport struct {
	Base http.RoundTripper
}

// NewTracingTransport returns a transport wrapping base. If base is nil,
// http.DefaultTransport is used.
func NewTracingTransport(base http.RoundTripper) *TracingTransport {
	if base == nil {
		base = http.DefaultTransport
	}
	return &TracingTransport{Base: base}
}

func (t *TracingTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	tc := FromContext(req.Context())
	if tc != nil {
		// Clone so we don't mutate the caller's request.
		req = req.Clone(req.Context())
		req.Header.Set("traceparent", FormatTraceparent(tc))
	}
	return t.Base.RoundTrip(req)
}
