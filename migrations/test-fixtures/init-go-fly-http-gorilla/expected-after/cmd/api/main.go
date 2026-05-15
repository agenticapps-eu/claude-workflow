package main

import (
	"net/http"

	"github.com/gorilla/mux"

	// agenticapps:observability:start
	"example.com/fixture-gorilla/internal/observability"
	// agenticapps:observability:end
)

func main() {
	// agenticapps:observability:start
	observability.Init()
	// agenticapps:observability:end

	r := mux.NewRouter()
	// agenticapps:observability:start
	r.Use(observability.Middleware)
	// agenticapps:observability:end
	r.HandleFunc("/", func(w http.ResponseWriter, req *http.Request) {
		w.Write([]byte("ok"))
	})
	http.ListenAndServe(":8080", r)
}
