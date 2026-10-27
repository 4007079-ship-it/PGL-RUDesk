// Command pgl-server is the PGL-RUDesk signaling, account and relay server.
package main

import (
	"context"
	"errors"
	"flag"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"pgl-next/internal/server"
	"pgl-next/web"
)

func main() {
	var cfg server.Config
	flag.StringVar(&cfg.Addr, "addr", envOr("PGL_ADDR", ":21220"), "HTTP listen address")
	flag.StringVar(&cfg.PublicIP, "public-ip", os.Getenv("PGL_PUBLIC_IP"), "public IPv4 for TURN relay (empty disables TURN)")
	flag.StringVar(&cfg.Host, "host", envOr("PGL_HOST", "127.0.0.1"), "hostname clients use for STUN/TURN")
	flag.StringVar(&cfg.Realm, "realm", envOr("PGL_REALM", "pgl-rudesk"), "TURN realm")
	flag.IntVar(&cfg.TurnPort, "turn-port", envInt("PGL_TURN_PORT", 21221), "UDP port for STUN/TURN")
	flag.IntVar(&cfg.RelayMin, "relay-min", envInt("PGL_RELAY_MIN", 21300), "lowest UDP relay port")
	flag.IntVar(&cfg.RelayMax, "relay-max", envInt("PGL_RELAY_MAX", 21400), "highest UDP relay port")
	flag.StringVar(&cfg.DataFile, "data", envOr("PGL_DATA", "pgl-data.json"), "data file path")
	flag.Parse()

	if sub, err := fs.Sub(web.Assets, "dist"); err == nil {
		cfg.Web = sub
	}

	srv, err := server.New(cfg)
	if err != nil {
		log.Fatalf("start: %v", err)
	}
	defer srv.Close()

	hs := &http.Server{
		Addr:              cfg.Addr,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("PGL-RUDesk server on %s (host=%s turn=%d public-ip=%q)", cfg.Addr, cfg.Host, cfg.TurnPort, cfg.PublicIP)
		if err := hs.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("serve: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = hs.Shutdown(ctx)
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func envInt(k string, def int) int {
	if v := os.Getenv(k); v != "" {
		n := 0
		for _, c := range v {
			if c < '0' || c > '9' {
				return def
			}
			n = n*10 + int(c-'0')
		}
		return n
	}
	return def
}
