// Package input abstracts injecting mouse and keyboard events.
package input

// Injector performs mouse and keyboard actions on the local machine.
// Coordinates are in display pixels.
type Injector interface {
	MoveMouse(x, y int)
	MouseButton(button int, down bool)
	Scroll(dx, dy int)
	Key(code string, down bool) // code is a browser KeyboardEvent.code
	Text(s string)              // type a unicode string
	Close() error
}

// Factory builds the platform injector. Set by the platform file's init().
var Factory func() (Injector, error)

// New returns an injector for the current platform, or a no-op one.
func New() (Injector, error) {
	if Factory == nil {
		return noop{}, nil
	}
	return Factory()
}

type noop struct{}

func (noop) MoveMouse(int, int)     {}
func (noop) MouseButton(int, bool)  {}
func (noop) Scroll(int, int)        {}
func (noop) Key(string, bool)       {}
func (noop) Text(string)            {}
func (noop) Close() error           { return nil }
