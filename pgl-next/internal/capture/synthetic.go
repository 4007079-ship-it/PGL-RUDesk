//go:build !windows

// Synthetic capturer: a moving box on a gradient. Used on platforms without a
// native capturer yet, and as the capturer in end-to-end tests. Pure Go.
package capture

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"math"
	"sync/atomic"
	"time"
)

type synthetic struct {
	w, h  int
	seq   uint64
	start time.Time
}

func init() {
	if Factory == nil {
		Factory = func() (Capturer, error) {
			return &synthetic{w: 1280, h: 720, start: time.Now()}, nil
		}
	}
}

func (s *synthetic) Size() (int, int) { return s.w, s.h }

func (s *synthetic) Grab(quality int) (*Frame, error) {
	img := image.NewRGBA(image.Rect(0, 0, s.w, s.h))
	t := time.Since(s.start).Seconds()
	// gradient background
	for y := 0; y < s.h; y++ {
		for x := 0; x < s.w; x += 4 {
			c := color.RGBA{uint8(x * 255 / s.w), uint8(y * 255 / s.h), 64, 255}
			img.SetRGBA(x, y, c)
			img.SetRGBA(x+1, y, c)
			img.SetRGBA(x+2, y, c)
			img.SetRGBA(x+3, y, c)
		}
	}
	// moving box
	bx := int((0.5 + 0.4*math.Sin(t)) * float64(s.w-120))
	by := int((0.5 + 0.4*math.Cos(t*0.7)) * float64(s.h-120))
	for y := by; y < by+120 && y < s.h; y++ {
		for x := bx; x < bx+120 && x < s.w; x++ {
			img.SetRGBA(x, y, color.RGBA{246, 74, 246, 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: clampQ(quality)}); err != nil {
		return nil, err
	}
	w, h := bounds(img)
	return &Frame{JPEG: buf.Bytes(), Width: w, Height: h, Seq: atomic.AddUint64(&s.seq, 1)}, nil
}

func (s *synthetic) Close() error { return nil }

func clampQ(q int) int {
	if q < 1 {
		return 1
	}
	if q > 100 {
		return 100
	}
	return q
}
