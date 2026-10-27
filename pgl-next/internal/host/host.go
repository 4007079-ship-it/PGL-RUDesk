// Package host runs on the controlled machine: it connects to the PGL server,
// waits for viewers, and serves the screen plus input over WebRTC data channels.
package host

import (
	"encoding/json"
	"log"
	"net/url"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/pion/webrtc/v4"

	"pgl-next/internal/capture"
	"pgl-next/internal/input"
	"pgl-next/internal/proto"
)

// Config configures a host agent.
type Config struct {
	ServerWS string // ws(s)://host:port
	DeviceID string
	Secret   string
	Name     string
	OS       string
	Password string // required from viewers before control is granted
	FPS      int
	Quality  int
}

// Host maintains the control connection and spawns a session per viewer.
type Host struct {
	cfg      Config
	ice      []webrtc.ICEServer
	mu       sync.Mutex
	sessions map[string]*session // viewer sid -> session
	ws       *websocket.Conn
	writeMu  sync.Mutex
}

func New(cfg Config) *Host {
	if cfg.FPS <= 0 {
		cfg.FPS = 12
	}
	if cfg.Quality <= 0 {
		cfg.Quality = 60
	}
	return &Host{cfg: cfg, sessions: map[string]*session{}}
}

// Run connects to the server and serves viewers until the context connection drops.
// It reconnects with backoff. Blocks forever unless stop is closed.
func (h *Host) Run(stop <-chan struct{}) {
	backoff := time.Second
	for {
		select {
		case <-stop:
			return
		default:
		}
		if err := h.connect(stop); err != nil {
			log.Printf("host: connection lost: %v (retry in %s)", err, backoff)
		}
		select {
		case <-stop:
			return
		case <-time.After(backoff):
		}
		if backoff < 30*time.Second {
			backoff *= 2
		}
	}
}

func (h *Host) connect(stop <-chan struct{}) error {
	u, err := url.Parse(h.cfg.ServerWS)
	if err != nil {
		return err
	}
	u.Path = "/ws/device"
	q := u.Query()
	q.Set("id", h.cfg.DeviceID)
	q.Set("secret", h.cfg.Secret)
	q.Set("name", h.cfg.Name)
	q.Set("os", h.cfg.OS)
	u.RawQuery = q.Encode()

	conn, _, err := websocket.DefaultDialer.Dial(u.String(), nil)
	if err != nil {
		return err
	}
	h.ws = conn
	defer conn.Close()
	log.Printf("host: connected as device %s", h.cfg.DeviceID)

	done := make(chan struct{})
	go func() {
		select {
		case <-stop:
			conn.Close()
		case <-done:
		}
	}()
	defer close(done)

	for {
		_, data, err := conn.ReadMessage()
		if err != nil {
			h.closeAll()
			return err
		}
		var m proto.Signal
		if json.Unmarshal(data, &m) != nil {
			continue
		}
		h.onSignal(m)
	}
}

func (h *Host) onSignal(m proto.Signal) {
	switch m.Type {
	case proto.SigHello:
		h.ice = toICEServers(m.ICE)
	case proto.SigOffer:
		h.startSession(m.SID, m.SDP)
	case proto.SigICE:
		h.mu.Lock()
		s := h.sessions[m.SID]
		h.mu.Unlock()
		if s != nil {
			s.addRemoteICE(m.Candidate)
		}
	case proto.SigBye:
		h.endSession(m.SID)
	}
}

func (h *Host) send(m proto.Signal) {
	h.writeMu.Lock()
	defer h.writeMu.Unlock()
	if h.ws == nil {
		return
	}
	b, _ := json.Marshal(m)
	_ = h.ws.SetWriteDeadline(time.Now().Add(10 * time.Second))
	_ = h.ws.WriteMessage(websocket.TextMessage, b)
}

func (h *Host) startSession(sid, offer string) {
	h.endSession(sid) // replace any stale session with the same id
	cap, err := capture.New()
	if err != nil {
		log.Printf("host: capture unavailable: %v", err)
		return
	}
	inj, err := input.New()
	if err != nil {
		log.Printf("host: input unavailable: %v", err)
		inj, _ = input.New()
	}
	s, err := newSession(h, sid, cap, inj)
	if err != nil {
		log.Printf("host: session %s: %v", sid, err)
		_ = cap.Close()
		return
	}
	h.mu.Lock()
	h.sessions[sid] = s
	h.mu.Unlock()
	if err := s.accept(offer); err != nil {
		log.Printf("host: session %s offer: %v", sid, err)
		h.endSession(sid)
	}
}

func (h *Host) endSession(sid string) {
	h.mu.Lock()
	s := h.sessions[sid]
	delete(h.sessions, sid)
	h.mu.Unlock()
	if s != nil {
		s.close()
	}
}

func (h *Host) closeAll() {
	h.mu.Lock()
	for _, s := range h.sessions {
		s.close()
	}
	h.sessions = map[string]*session{}
	h.mu.Unlock()
}

func toICEServers(in []proto.ICEServer) []webrtc.ICEServer {
	out := make([]webrtc.ICEServer, 0, len(in))
	for _, s := range in {
		srv := webrtc.ICEServer{URLs: s.URLs}
		if s.Username != "" {
			srv.Username = s.Username
			srv.Credential = s.Credential
		}
		out = append(out, srv)
	}
	return out
}
