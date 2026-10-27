package host

import (
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/pion/webrtc/v4"

	"pgl-next/internal/capture"
	"pgl-next/internal/input"
	"pgl-next/internal/proto"
)

// session is one viewer's WebRTC connection to this host.
type session struct {
	h   *Host
	sid string
	pc  *webrtc.PeerConnection
	cap capture.Capturer
	inj input.Injector

	mu      sync.Mutex
	authed  bool
	closed  bool
	video   *webrtc.DataChannel
	stopVid chan struct{}
}

func newSession(h *Host, sid string, cap capture.Capturer, inj input.Injector) (*session, error) {
	pc, err := webrtc.NewPeerConnection(webrtc.Configuration{ICEServers: h.ice})
	if err != nil {
		return nil, err
	}
	s := &session{h: h, sid: sid, pc: pc, cap: cap, inj: inj, stopVid: make(chan struct{})}

	pc.OnICECandidate(func(c *webrtc.ICECandidate) {
		if c == nil {
			return
		}
		h.send(proto.Signal{Type: proto.SigICE, SID: sid, Candidate: c.ToJSON()})
	})
	pc.OnConnectionStateChange(func(st webrtc.PeerConnectionState) {
		if st == webrtc.PeerConnectionStateFailed || st == webrtc.PeerConnectionStateClosed {
			h.endSession(sid)
		}
	})
	pc.OnDataChannel(func(dc *webrtc.DataChannel) { s.onChannel(dc) })
	return s, nil
}

func (s *session) accept(offer string) error {
	if err := s.pc.SetRemoteDescription(webrtc.SessionDescription{
		Type: webrtc.SDPTypeOffer, SDP: offer,
	}); err != nil {
		return err
	}
	answer, err := s.pc.CreateAnswer(nil)
	if err != nil {
		return err
	}
	if err := s.pc.SetLocalDescription(answer); err != nil {
		return err
	}
	s.h.send(proto.Signal{Type: proto.SigAnswer, SID: s.sid, SDP: answer.SDP})
	return nil
}

func (s *session) addRemoteICE(raw any) {
	if raw == nil {
		return
	}
	b, err := json.Marshal(raw)
	if err != nil {
		return
	}
	var init webrtc.ICECandidateInit
	if json.Unmarshal(b, &init) != nil {
		return
	}
	_ = s.pc.AddICECandidate(init)
}

func (s *session) onChannel(dc *webrtc.DataChannel) {
	switch dc.Label() {
	case "video":
		s.mu.Lock()
		s.video = dc
		s.mu.Unlock()
		dc.OnOpen(func() { go s.videoLoop(dc) })
	case "ctl":
		dc.OnMessage(func(msg webrtc.DataChannelMessage) { s.onCtl(dc, msg.Data) })
	case "input":
		dc.OnMessage(func(msg webrtc.DataChannelMessage) { s.onInput(msg.Data) })
	case "clip":
		dc.OnMessage(func(msg webrtc.DataChannelMessage) { s.onClip(dc, msg.Data) })
	}
}

func (s *session) onCtl(dc *webrtc.DataChannel, data []byte) {
	var c proto.Ctl
	if json.Unmarshal(data, &c) != nil {
		return
	}
	switch c.T {
	case "auth":
		ok := s.h.cfg.Password == "" || c.PW == s.h.cfg.Password
		s.mu.Lock()
		s.authed = ok
		s.mu.Unlock()
		w, hgt := s.cap.Size()
		reply := proto.Ctl{T: "auth", OK: ok, W: w, H: hgt, Name: s.h.cfg.Name, OS: s.h.cfg.OS}
		if !ok {
			reply.Err = "bad password"
		}
		sendJSON(dc, reply)
	}
}

func (s *session) onInput(data []byte) {
	if !s.isAuthed() {
		return
	}
	var in proto.Input
	if json.Unmarshal(data, &in) != nil {
		return
	}
	switch in.T {
	case "mm":
		s.inj.MoveMouse(int(in.X), int(in.Y))
	case "md":
		s.inj.MouseButton(in.B, true)
	case "mu":
		s.inj.MouseButton(in.B, false)
	case "wh":
		s.inj.Scroll(int(in.DX), int(in.DY))
	case "kd":
		s.inj.Key(in.Code, true)
	case "ku":
		s.inj.Key(in.Code, false)
	case "txt":
		s.inj.Text(in.S)
	}
}

func (s *session) onClip(dc *webrtc.DataChannel, data []byte) {
	if !s.isAuthed() {
		return
	}
	// Clipboard sync is added with the platform clipboard; ignored until then.
	_ = dc
}

func (s *session) videoLoop(dc *webrtc.DataChannel) {
	interval := time.Second / time.Duration(maxInt(s.h.cfg.FPS, 1))
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-s.stopVid:
			return
		case <-t.C:
			if !s.isAuthed() {
				continue
			}
			if dc.BufferedAmount() > 2*1024*1024 {
				continue // viewer is behind; skip this frame
			}
			f, err := s.cap.Grab(s.h.cfg.Quality)
			if err != nil {
				log.Printf("host: capture: %v", err)
				continue
			}
			if err := dc.Send(f.JPEG); err != nil {
				return
			}
		}
	}
}

func (s *session) isAuthed() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.authed
}

func (s *session) close() {
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		return
	}
	s.closed = true
	close(s.stopVid)
	s.mu.Unlock()
	if s.pc != nil {
		_ = s.pc.Close()
	}
	_ = s.cap.Close()
	_ = s.inj.Close()
}

func sendJSON(dc *webrtc.DataChannel, v any) {
	b, _ := json.Marshal(v)
	_ = dc.SendText(string(b))
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}
