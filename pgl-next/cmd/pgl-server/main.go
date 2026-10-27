// Command pgl-server is the PGL-RUDesk signaling and account server.
//
// Первый этап: HTTP-сервер с проверкой здоровья. Дальше добавляются аккаунты,
// список устройств, сигнализация WebRTC и встроенный ретранслятор (TURN).
package main

import (
	"log"
	"net/http"
	"os"
)

func main() {
	addr := os.Getenv("PGL_LISTEN")
	if addr == "" {
		addr = "127.0.0.1:21200"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"ok":true,"service":"pgl-server"}`))
	})

	log.Printf("pgl-server listening on %s", addr)
	srv := &http.Server{Addr: addr, Handler: mux}
	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("pgl-server stopped: %v", err)
	}
}
