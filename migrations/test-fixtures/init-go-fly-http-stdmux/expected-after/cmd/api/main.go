package main

import (
	"log"
	"net/http"

	// agenticapps:observability:start
	"example.com/fixture-stdmux/internal/observability"
	// agenticapps:observability:end
)

func main() {
	// agenticapps:observability:start
	observability.Init()
	// agenticapps:observability:end

	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})
	// agenticapps:observability:start
	if err := http.ListenAndServe(":8080", observability.Middleware(mux)); err != nil {
		log.Fatal(err)
	}
	// agenticapps:observability:end
}
