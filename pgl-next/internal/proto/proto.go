// Package proto describes the messages exchanged between the server, devices and viewers.
package proto

// Signal is a WebSocket signaling message (server <-> device, server <-> viewer).
type Signal struct {
	Type      string      `json:"type"`
	SID       string      `json:"sid,omitempty"`
	To        string      `json:"to,omitempty"`
	SDP       string      `json:"sdp,omitempty"`
	Candidate any         `json:"candidate,omitempty"`
	ICE       []ICEServer `json:"ice,omitempty"`
	Owner     bool        `json:"owner,omitempty"`
	Viewer    string      `json:"viewer,omitempty"`
	Message   string      `json:"message,omitempty"`
	ID        string      `json:"id,omitempty"`
}

// Signal types.
const (
	SigHello   = "hello"   // server -> client: ICE servers (+ device id)
	SigConnect = "connect" // viewer -> server: start a session with device To
	SigOffer   = "offer"   // viewer -> device (via server)
	SigAnswer  = "answer"  // device -> viewer (via server)
	SigICE     = "ice"     // both directions
	SigBye     = "bye"     // either side: session closed
	SigError   = "error"   // server -> client
	SigPing    = "ping"
)

// ICEServer mirrors RTCIceServer.
type ICEServer struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
}

// Control messages on the "ctl" data channel.
type Ctl struct {
	T      string `json:"t"`
	PW     string `json:"pw,omitempty"`
	OK     bool   `json:"ok,omitempty"`
	Err    string `json:"err,omitempty"`
	W      int    `json:"w,omitempty"`
	H      int    `json:"h,omitempty"`
	Name   string `json:"name,omitempty"`
	OS     string `json:"os,omitempty"`
	Screen int    `json:"screen,omitempty"`
	Count  int    `json:"count,omitempty"`
}

// Input messages on the "input" data channel.
type Input struct {
	T    string  `json:"t"` // mm, md, mu, wh, kd, ku, txt
	X    float64 `json:"x,omitempty"`
	Y    float64 `json:"y,omitempty"`
	B    int     `json:"b,omitempty"`
	DX   float64 `json:"dx,omitempty"`
	DY   float64 `json:"dy,omitempty"`
	Code string  `json:"code,omitempty"`
	S    string  `json:"s,omitempty"`
}

// Clip is a clipboard message on the "clip" data channel.
type Clip struct {
	T string `json:"t"`
	S string `json:"s"`
}

// File messages on the "file" data channel (text frames; binary frames carry chunk data).
type File struct {
	T       string      `json:"t"` // put, end, ls, get, meta, done, err
	Name    string      `json:"name,omitempty"`
	Path    string      `json:"path,omitempty"`
	Size    int64       `json:"size,omitempty"`
	Entries []FileEntry `json:"entries,omitempty"`
	Err     string      `json:"err,omitempty"`
}

// FileEntry is one item of a directory listing.
type FileEntry struct {
	Name  string `json:"name"`
	Dir   bool   `json:"dir"`
	Size  int64  `json:"size"`
	MTime int64  `json:"mtime"`
}
