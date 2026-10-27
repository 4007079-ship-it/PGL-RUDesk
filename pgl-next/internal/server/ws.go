package server

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gorilla/websocket"

	"pgl-next/internal/proto"
	"pgl-next/internal/store"
)

const (
	writeWait  = 10 * time.Second
	pongWait   = 60 * time.Second
	pingPeriod = 50 * time.Second
	iceTTL     = 12 * time.Hour
)

// wsDevice: a host registers with its id+secret and waits for viewers.
// Query: ?id=...&secret=...&name=...&os=...
func (s *Server) wsDevice(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	dev, ok := s.st.CheckDevice(q.Get("id"), q.Get("secret"))
	if !ok {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	conn, err := s.up.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	s.st.TouchDevice(dev.ID, q.Get("name"), q.Get("os"))

	c := &client{id: dev.ID, send: make(chan proto.Signal, 32)}
	s.hub.addDevice(dev.ID, c)
	defer s.hub.removeDevice(dev.ID, c)

	c.send <- proto.Signal{Type: proto.SigHello, ID: dev.ID, ICE: s.ice(iceTTL)}
	s.pump(conn, c, func(m proto.Signal) {
		// From device: answer / ice targeted at a viewer session.
		switch m.Type {
		case proto.SigAnswer, proto.SigICE, proto.SigBye:
			s.hub.toViewer(m.SID, m)
		}
	})
}

// wsViewer: a browser or desktop viewer connects to control a device.
// Query: ?id=<device>  (optional ?token= for owned devices)
func (s *Server) wsViewer(w http.ResponseWriter, r *http.Request) {
	target := r.URL.Query().Get("id")
	if target == "" {
		http.Error(w, "id required", http.StatusBadRequest)
		return
	}
	if _, ok := s.st.Device(target); !ok {
		http.Error(w, "no device", http.StatusNotFound)
		return
	}
	conn, err := s.up.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	sid := store.RandHex(12)
	c := &client{id: sid, send: make(chan proto.Signal, 32)}
	s.hub.addViewer(sid, c)
	defer s.hub.removeViewer(sid)

	online := s.hub.deviceOnline(target)
	c.send <- proto.Signal{Type: proto.SigHello, SID: sid, ICE: s.ice(iceTTL)}
	if !online {
		c.send <- proto.Signal{Type: proto.SigError, Message: "offline"}
	}

	s.pump(conn, c, func(m proto.Signal) {
		// From viewer: offer / ice forwarded to the device, tagged with sid.
		switch m.Type {
		case proto.SigOffer, proto.SigICE, proto.SigBye:
			m.SID = sid
			if !s.hub.toDevice(target, m) {
				c.send <- proto.Signal{Type: proto.SigError, Message: "offline"}
			}
		}
	})
	// Tell the device the viewer is gone.
	s.hub.toDevice(target, proto.Signal{Type: proto.SigBye, SID: sid})
}

// pump runs the read and write loops for a websocket connection.
func (s *Server) pump(conn *websocket.Conn, c *client, onMsg func(proto.Signal)) {
	done := make(chan struct{})
	go func() {
		ticker := time.NewTicker(pingPeriod)
		defer ticker.Stop()
		for {
			select {
			case m, ok := <-c.send:
				_ = conn.SetWriteDeadline(time.Now().Add(writeWait))
				if !ok {
					_ = conn.WriteMessage(websocket.CloseMessage, nil)
					return
				}
				b, _ := json.Marshal(m)
				if conn.WriteMessage(websocket.TextMessage, b) != nil {
					return
				}
			case <-ticker.C:
				_ = conn.SetWriteDeadline(time.Now().Add(writeWait))
				if conn.WriteMessage(websocket.PingMessage, nil) != nil {
					return
				}
			case <-done:
				return
			}
		}
	}()

	conn.SetReadLimit(1 << 16)
	_ = conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(pongWait))
	})
	for {
		_, data, err := conn.ReadMessage()
		if err != nil {
			break
		}
		var m proto.Signal
		if json.Unmarshal(data, &m) != nil {
			continue
		}
		onMsg(m)
	}
	close(done)
	_ = conn.Close()
}

// apiNewDevice provisions a fresh device id+secret for a first-time installation.
func (s *Server) apiNewDevice(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errJSON(w, 405, "method")
		return
	}
	var body struct{ Name, OS string }
	_ = readJSON(r, &body)
	dev, secret, err := s.st.NewDevice(body.Name, body.OS)
	if err != nil {
		errJSON(w, 500, "server")
		return
	}
	writeJSON(w, 200, map[string]string{"id": dev.ID, "secret": secret})
}
