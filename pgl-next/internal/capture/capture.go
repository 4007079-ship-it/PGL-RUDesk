// Package capture abstracts grabbing the screen into JPEG frames.
package capture

import "image"

// Frame is one captured screen image plus the display size it came from.
type Frame struct {
	JPEG   []byte
	Width  int
	Height int
	Seq    uint64
}

// Capturer grabs frames from a display. Implementations are platform specific.
type Capturer interface {
	// Size returns the current display dimensions in pixels.
	Size() (w, h int)
	// Grab returns the next frame encoded as JPEG at the given quality (1..100).
	Grab(quality int) (*Frame, error)
	// Close releases any resources.
	Close() error
}

// Factory creates the platform capturer. Set by the platform file's init().
var Factory func() (Capturer, error)

// New returns a capturer for the current platform.
func New() (Capturer, error) {
	if Factory == nil {
		return nil, errNoCapturer
	}
	return Factory()
}

type capErr string

func (e capErr) Error() string { return string(e) }

const errNoCapturer = capErr("no screen capturer for this platform")

// bounds is a small helper shared by platform encoders.
func bounds(img image.Image) (int, int) {
	b := img.Bounds()
	return b.Dx(), b.Dy()
}
