package host_test

import (
	"encoding/json"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/pion/webrtc/v4"

	"pgl-next/internal/host"
	"pgl-next/internal/proto"
	"pgl-next/internal/server"
)

// TestEndToEnd stands up the real server, a host with the synthetic capturer,
// and a pion viewer that offers the data channels, authenticates and receives
// a JPEG frame — exercising the whole pipeline in pure Go.
func TestEndToEnd(t *testing.T) {
	srv, err := server.New(server.Config{DataFile: t.TempDir() + "/d.json"})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { srv.Close() })
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)

	// Provision a device via the server store and start the host.
	st := srv.Store()
	dev, secret, err := st.NewDevice("TestPC", "linux")
	if err != nil {
		t.Fatal(err)
	}
	h := host.New(host.Config{
		ServerWS: toWS(ts.URL), DeviceID: dev.ID, Secret: secret,
		Name: "TestPC", OS: "linux", Password: "pw123", FPS: 20, Quality: 50,
	})
	stop := make(chan struct{})
	go h.Run(stop)
	t.Cleanup(func() { close(stop) })
	time.Sleep(300 * time.Millisecond) // let the host register

	// --- viewer side ---
	wsURL := wsURL(ts, "/ws/viewer", "id="+dev.ID)
	vc, _, err := websocketDial(wsURL)
	if err != nil {
		t.Fatalf("viewer dial: %v", err)
	}
	defer vc.Close()

	hello := readSig(t, vc)
	if hello.Type != proto.SigHello {
		t.Fatalf("expected hello, got %+v", hello)
	}
	ice := make([]webrtc.ICEServer, 0)
	for _, s := range hello.ICE {
		ice = append(ice, webrtc.ICEServer{URLs: s.URLs})
	}

	pc, err := webrtc.NewPeerConnection(webrtc.Configuration{ICEServers: ice})
	if err != nil {
		t.Fatal(err)
	}
	defer pc.Close()

	frameCh := make(chan []byte, 4)
	authCh := make(chan proto.Ctl, 1)

	ctl, _ := pc.CreateDataChannel("ctl", nil)
	video, _ := pc.CreateDataChannel("video", nil)
	pc.CreateDataChannel("input", nil)

	ctl.OnMessage(func(m webrtc.DataChannelMessage) {
		var c proto.Ctl
		if json.Unmarshal(m.Data, &c) == nil && c.T == "auth" {
			select {
			case authCh <- c:
			default:
			}
		}
	})
	ctl.OnOpen(func() { _ = ctl.SendText(`{"t":"auth","pw":"pw123"}`) })
	video.OnMessage(func(m webrtc.DataChannelMessage) {
		select {
		case frameCh <- m.Data:
		default:
		}
	})

	pc.OnICECandidate(func(c *webrtc.ICECandidate) {
		if c == nil {
			return
		}
		writeSig(t, vc, proto.Signal{Type: proto.SigICE, Candidate: c.ToJSON()})
	})

	offer, err := pc.CreateOffer(nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := pc.SetLocalDescription(offer); err != nil {
		t.Fatal(err)
	}
	writeSig(t, vc, proto.Signal{Type: proto.SigOffer, SDP: offer.SDP})

	// Read answer + ICE from the device (relayed by server) in a goroutine.
	go func() {
		for {
			m := readSigNoFatal(vc)
			if m == nil {
				return
			}
			switch m.Type {
			case proto.SigAnswer:
				_ = pc.SetRemoteDescription(webrtc.SessionDescription{Type: webrtc.SDPTypeAnswer, SDP: m.SDP})
			case proto.SigICE:
				addICE(pc, m.Candidate)
			}
		}
	}()

	select {
	case c := <-authCh:
		if !c.OK {
			t.Fatalf("auth failed: %+v", c)
		}
		if c.W == 0 || c.H == 0 {
			t.Fatalf("auth missing size: %+v", c)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("no auth reply (data channel never opened)")
	}

	select {
	case f := <-frameCh:
		if len(f) < 100 || !(f[0] == 0xFF && f[1] == 0xD8) { // JPEG SOI marker
			t.Fatalf("not a JPEG frame: %d bytes", len(f))
		}
		t.Logf("received JPEG frame: %d bytes", len(f))
	case <-time.After(10 * time.Second):
		t.Fatal("no video frame received")
	}
}

// --- test helpers (thin wrappers to keep the test readable) ---

func toWS(httpURL string) string {
	u, _ := url.Parse(httpURL)
	u.Scheme = "ws"
	return u.String()
}

func wsURL(ts *httptest.Server, path, query string) string {
	u, _ := url.Parse(ts.URL)
	u.Scheme = "ws"
	u.Path = path
	u.RawQuery = query
	return u.String()
}

func addICE(pc *webrtc.PeerConnection, raw any) {
	if raw == nil {
		return
	}
	b, _ := json.Marshal(raw)
	var init webrtc.ICECandidateInit
	if json.Unmarshal(b, &init) == nil {
		_ = pc.AddICECandidate(init)
	}
}

var _ = strings.TrimSpace
