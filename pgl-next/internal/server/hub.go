// Package server is the PGL signaling + web server.
package server

import (
	"sync"

	"pgl-next/internal/proto"
)

// client is one connected endpoint: a device waiting for viewers, or a viewer.
type client struct {
	id   string // device id for devices; random for viewers
	send chan proto.Signal
}

// hub routes signaling messages between viewers and the device they target.
// A device registers under its id; viewers look it up to start a session.
type hub struct {
	mu      sync.RWMutex
	devices map[string]*client // device id -> device conn
	viewers map[string]*client // viewer sid -> viewer conn
}

func newHub() *hub {
	return &hub{devices: map[string]*client{}, viewers: map[string]*client{}}
}

func (h *hub) addDevice(id string, c *client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if old := h.devices[id]; old != nil {
		close(old.send)
	}
	h.devices[id] = c
}

func (h *hub) removeDevice(id string, c *client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.devices[id] == c {
		delete(h.devices, id)
	}
}

func (h *hub) deviceOnline(id string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	_, ok := h.devices[id]
	return ok
}

func (h *hub) addViewer(sid string, c *client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.viewers[sid] = c
}

func (h *hub) removeViewer(sid string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.viewers, sid)
}

// toDevice delivers a signal to a device; returns false if it is offline.
func (h *hub) toDevice(id string, m proto.Signal) bool {
	h.mu.RLock()
	c := h.devices[id]
	h.mu.RUnlock()
	return deliver(c, m)
}

// toViewer delivers a signal to a viewer by session id.
func (h *hub) toViewer(sid string, m proto.Signal) bool {
	h.mu.RLock()
	c := h.viewers[sid]
	h.mu.RUnlock()
	return deliver(c, m)
}

func deliver(c *client, m proto.Signal) bool {
	if c == nil {
		return false
	}
	defer func() { _ = recover() }() // send on closed channel during teardown
	select {
	case c.send <- m:
		return true
	default:
		return false
	}
}
