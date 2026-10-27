// Command pgl-host runs on the controlled machine and serves its screen to viewers.
package main

import (
	"encoding/json"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"strings"
	"syscall"

	"pgl-next/internal/host"
)

func main() {
	var (
		server   = flag.String("server", envOr("PGL_SERVER", "http://127.0.0.1:21220"), "server base URL")
		id       = flag.String("id", os.Getenv("PGL_DEVICE_ID"), "device id (empty = provision a new one)")
		secret   = flag.String("secret", os.Getenv("PGL_DEVICE_SECRET"), "device secret")
		password = flag.String("password", os.Getenv("PGL_PASSWORD"), "password viewers must enter")
		name     = flag.String("name", hostname(), "device name shown to viewers")
		fps      = flag.Int("fps", 12, "frames per second")
		quality  = flag.Int("quality", 60, "JPEG quality 1..100")
	)
	flag.Parse()

	base := strings.TrimRight(*server, "/")
	if *id == "" || *secret == "" {
		nid, nsecret, err := provision(base, *name)
		if err != nil {
			log.Fatalf("provision: %v", err)
		}
		*id, *secret = nid, nsecret
		log.Printf("provisioned device id=%s (save it): PGL_DEVICE_ID=%s PGL_DEVICE_SECRET=%s", nid, nid, nsecret)
	}

	h := host.New(host.Config{
		ServerWS: toWS(base),
		DeviceID: *id,
		Secret:   *secret,
		Name:     *name,
		OS:       runtime.GOOS,
		Password: *password,
		FPS:      *fps,
		Quality:  *quality,
	})

	stop := make(chan struct{})
	go func() {
		c := make(chan os.Signal, 1)
		signal.Notify(c, os.Interrupt, syscall.SIGTERM)
		<-c
		close(stop)
	}()
	log.Printf("pgl-host: device %s -> %s", *id, base)
	h.Run(stop)
}

func provision(base, name string) (string, string, error) {
	body, _ := json.Marshal(map[string]string{"name": name, "os": runtime.GOOS})
	resp, err := http.Post(base+"/api/device/new", "application/json", strings.NewReader(string(body)))
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()
	var r struct{ ID, Secret string }
	if err := json.NewDecoder(resp.Body).Decode(&r); err != nil {
		return "", "", err
	}
	return r.ID, r.Secret, nil
}

func toWS(base string) string {
	if strings.HasPrefix(base, "https://") {
		return "wss://" + strings.TrimPrefix(base, "https://")
	}
	return "ws://" + strings.TrimPrefix(base, "http://")
}

func hostname() string {
	n, _ := os.Hostname()
	if n == "" {
		return "PGL host"
	}
	return n
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
