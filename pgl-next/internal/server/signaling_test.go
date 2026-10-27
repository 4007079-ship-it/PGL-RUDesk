package server

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"

	"pgl-next/internal/proto"
)

func newTestServer(t *testing.T) (*httptest.Server, *Server) {
	t.Helper()
	srv, err := New(Config{DataFile: filepath.Join(t.TempDir(), "d.json")})
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(func() { ts.Close(); srv.Close() })
	return ts, srv
}

func wsURL(ts *httptest.Server, path, query string) string {
	u, _ := url.Parse(ts.URL)
	u.Scheme = "ws"
	u.Path = path
	u.RawQuery = query
	return u.String()
}

func dial(t *testing.T, u string) *websocket.Conn {
	t.Helper()
	c, _, err := websocket.DefaultDialer.Dial(u, nil)
	if err != nil {
		t.Fatalf("dial %s: %v", u, err)
	}
	t.Cleanup(func() { c.Close() })
	return c
}

func readSig(t *testing.T, c *websocket.Conn) proto.Signal {
	t.Helper()
	c.SetReadDeadline(time.Now().Add(3 * time.Second))
	_, b, err := c.ReadMessage()
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	var m proto.Signal
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	return m
}

func send(t *testing.T, c *websocket.Conn, m proto.Signal) {
	t.Helper()
	b, _ := json.Marshal(m)
	if err := c.WriteMessage(websocket.TextMessage, b); err != nil {
		t.Fatalf("write: %v", err)
	}
}

// TestOfferAnswerRelay verifies that a viewer's offer reaches the device and
// the device's answer (tagged with the viewer sid) comes back to that viewer.
func TestOfferAnswerRelay(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, secret, err := srv.st.NewDevice("PC", "windows")
	if err != nil {
		t.Fatal(err)
	}

	devConn := dial(t, wsURL(ts, "/ws/device", "id="+dev.ID+"&secret="+secret))
	if hello := readSig(t, devConn); hello.Type != proto.SigHello || hello.ID != dev.ID {
		t.Fatalf("device hello = %+v", hello)
	}

	viewer := dial(t, wsURL(ts, "/ws/viewer", "id="+dev.ID))
	vh := readSig(t, viewer)
	if vh.Type != proto.SigHello || vh.SID == "" {
		t.Fatalf("viewer hello = %+v", vh)
	}

	send(t, viewer, proto.Signal{Type: proto.SigOffer, SDP: "OFFER"})
	got := readSig(t, devConn)
	if got.Type != proto.SigOffer || got.SDP != "OFFER" || got.SID == "" {
		t.Fatalf("device received = %+v", got)
	}

	send(t, devConn, proto.Signal{Type: proto.SigAnswer, SID: got.SID, SDP: "ANSWER"})
	ans := readSig(t, viewer)
	if ans.Type != proto.SigAnswer || ans.SDP != "ANSWER" {
		t.Fatalf("viewer received = %+v", ans)
	}
}

// TestViewerOfflineDevice: connecting to a registered-but-offline device yields an offline error.
func TestViewerOfflineDevice(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _, _ := srv.st.NewDevice("PC", "linux")

	viewer := dial(t, wsURL(ts, "/ws/viewer", "id="+dev.ID))
	if h := readSig(t, viewer); h.Type != proto.SigHello {
		t.Fatalf("hello = %+v", h)
	}
	if e := readSig(t, viewer); e.Type != proto.SigError || e.Message != "offline" {
		t.Fatalf("expected offline, got %+v", e)
	}
}

// TestUnknownDeviceRejected: viewer to a non-existent device id is 404.
func TestUnknownDeviceRejected(t *testing.T) {
	ts, _ := newTestServer(t)
	_, resp, err := websocket.DefaultDialer.Dial(wsURL(ts, "/ws/viewer", "id=000000000"), nil)
	if err == nil {
		t.Fatal("expected error")
	}
	if resp == nil || resp.StatusCode != http.StatusNotFound {
		t.Fatalf("status = %v", resp)
	}
}

// TestDeviceBadSecret: wrong secret is rejected at the device endpoint.
func TestDeviceBadSecret(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _, _ := srv.st.NewDevice("PC", "linux")
	_, resp, err := websocket.DefaultDialer.Dial(wsURL(ts, "/ws/device", "id="+dev.ID+"&secret=wrong"), nil)
	if err == nil {
		t.Fatal("expected error")
	}
	if resp == nil || resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status = %v", resp)
	}
}

func TestValidEmail(t *testing.T) {
	ok := []string{"a@b.com", "x.y@mail.co.uk", "USER@Example.Org"}
	bad := []string{"", "no-at", "a@b", "@b.com", "a@"}
	for _, e := range ok {
		if !validEmail(e) {
			t.Errorf("want valid: %q", e)
		}
	}
	for _, e := range bad {
		if validEmail(e) {
			t.Errorf("want invalid: %q", e)
		}
	}
	if !strings.Contains(strings.ToLower("USER@Example.Org"), "@") {
		t.Fatal("sanity")
	}
}
