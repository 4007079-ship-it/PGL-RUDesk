package host_test

import (
	"encoding/json"
	"net/http"
	"sync"
	"testing"
	"time"

	"github.com/gorilla/websocket"

	"pgl-next/internal/proto"
)

// vcWriteMu serializes writes to the viewer websocket in tests; gorilla
// websocket panics on concurrent writes (offer goroutine + ICE callback).
var vcWriteMu sync.Mutex

func websocketDial(u string) (*websocket.Conn, *http.Response, error) {
	return websocket.DefaultDialer.Dial(u, nil)
}

func readSig(t *testing.T, c *websocket.Conn) proto.Signal {
	t.Helper()
	m := readSigNoFatal(c)
	if m == nil {
		t.Fatal("read signal failed")
	}
	return *m
}

func readSigNoFatal(c *websocket.Conn) *proto.Signal {
	c.SetReadDeadline(time.Now().Add(12 * time.Second))
	_, b, err := c.ReadMessage()
	if err != nil {
		return nil
	}
	var m proto.Signal
	if json.Unmarshal(b, &m) != nil {
		return nil
	}
	return &m
}

func writeSig(t *testing.T, c *websocket.Conn, m proto.Signal) {
	t.Helper()
	b, _ := json.Marshal(m)
	vcWriteMu.Lock()
	err := c.WriteMessage(websocket.TextMessage, b)
	vcWriteMu.Unlock()
	if err != nil {
		t.Fatalf("write signal: %v", err)
	}
}
