// agenticapps:observability:start
//
// Observability middleware — materialised by `/add-observability init`.
// Source template: add-observability/templates/go-fly-http/middleware.go
//
// Exports `Middleware(next http.Handler) http.Handler` — compatible with
// net/http, chi, echo, gorilla/mux, and any router accepting http.Handler
// middleware.
//
// Fixture stub — the real init produces ~5k of token-substituted template
// content (see add-observability/templates/go-fly-http/middleware.go).

package observability

import "net/http"

func Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		Init()
		next.ServeHTTP(w, r)
	})
}
// agenticapps:observability:end
