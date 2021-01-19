package hello

import (
	"encoding/json"
	"log"
	"net/http"
)

type HTTPMessage struct {
	Name string `json:"name"`
}

func HelloHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Not allowed", http.StatusMethodNotAllowed)
		return
	}

	var m HTTPMessage
	if err := json.NewDecoder(r.Body).Decode(&m); err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	log.Printf("Hello, %s!", m.Name)
	w.WriteHeader(http.StatusNoContent)
}
