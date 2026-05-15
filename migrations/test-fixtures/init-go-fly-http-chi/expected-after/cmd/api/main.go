package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	// agenticapps:observability:start
	"example.com/fixture-chi/internal/observability"
	// agenticapps:observability:end
)

func main() {
	// agenticapps:observability:start
	observability.Init()
	// agenticapps:observability:end

	r := chi.NewRouter()
	// agenticapps:observability:start
	r.Use(observability.Middleware)
	// agenticapps:observability:end
	r.Get("/", func(w http.ResponseWriter, req *http.Request) {
		w.Write([]byte("ok"))
	})
	http.ListenAndServe(":8080", r)
}
