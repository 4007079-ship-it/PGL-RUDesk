//go:build windows

// Windows screen capturer using GDI BitBlt + GetDIBits. Pure Go via syscall,
// no CGO. Captures the whole virtual desktop and encodes each grab as JPEG.
package capture

import (
	"bytes"
	"fmt"
	"image"
	"image/jpeg"
	"sync/atomic"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	user32   = windows.NewLazySystemDLL("user32.dll")
	gdi32    = windows.NewLazySystemDLL("gdi32.dll")
	kernel32 = windows.NewLazySystemDLL("kernel32.dll")

	procGetDC                  = user32.NewProc("GetDC")
	procReleaseDC              = user32.NewProc("ReleaseDC")
	procGetSystemMetrics       = user32.NewProc("GetSystemMetrics")
	procSetProcessDPIAware     = user32.NewProc("SetProcessDPIAware")
	procSetProcessDpiAwareness = user32.NewProc("SetProcessDpiAwarenessContext")
	procCreateCompatibleDC = gdi32.NewProc("CreateCompatibleDC")
	procCreateCompatBitmap = gdi32.NewProc("CreateCompatibleBitmap")
	procSelectObject       = gdi32.NewProc("SelectObject")
	procBitBlt             = gdi32.NewProc("BitBlt")
	procDeleteObject       = gdi32.NewProc("DeleteObject")
	procDeleteDC           = gdi32.NewProc("DeleteDC")
	procGetDIBits          = gdi32.NewProc("GetDIBits")
)

const (
	smXVirtualScreen  = 76
	smYVirtualScreen  = 77
	smCXVirtualScreen = 78
	smCYVirtualScreen = 79

	srcCopy    = 0x00CC0020
	captureBLT = 0x40000000
	diBRGB     = 0
	biRGB      = 0
)

type bitmapInfoHeader struct {
	BiSize          uint32
	BiWidth         int32
	BiHeight        int32
	BiPlanes        uint16
	BiBitCount      uint16
	BiCompression   uint32
	BiSizeImage     uint32
	BiXPelsPerMeter int32
	BiYPelsPerMeter int32
	BiClrUsed       uint32
	BiClrImportant  uint32
}

type winCapturer struct {
	seq uint64
	buf []byte // reused BGRA scratch buffer
}

func init() {
	makeDPIAware()
	Factory = func() (Capturer, error) { return &winCapturer{}, nil }
}

// makeDPIAware makes GetSystemMetrics and BitBlt report and capture true
// pixels on scaled displays. Tries per-monitor-v2, then the legacy call.
func makeDPIAware() {
	const perMonitorV2 = ^uintptr(3) // -4 as uintptr: DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
	if procSetProcessDpiAwareness.Find() == nil {
		if r, _, _ := procSetProcessDpiAwareness.Call(perMonitorV2); r != 0 {
			return
		}
	}
	procSetProcessDPIAware.Call()
}

func metric(i int) int {
	r, _, _ := procGetSystemMetrics.Call(uintptr(i))
	return int(int32(r))
}

func (c *winCapturer) Size() (int, int) {
	return metric(smCXVirtualScreen), metric(smCYVirtualScreen)
}

func (c *winCapturer) Grab(quality int) (*Frame, error) {
	x0 := metric(smXVirtualScreen)
	y0 := metric(smYVirtualScreen)
	w := metric(smCXVirtualScreen)
	h := metric(smCYVirtualScreen)
	if w <= 0 || h <= 0 {
		return nil, fmt.Errorf("bad screen size %dx%d", w, h)
	}

	screenDC, _, _ := procGetDC.Call(0)
	if screenDC == 0 {
		return nil, fmt.Errorf("GetDC failed")
	}
	defer procReleaseDC.Call(0, screenDC)

	memDC, _, _ := procCreateCompatibleDC.Call(screenDC)
	if memDC == 0 {
		return nil, fmt.Errorf("CreateCompatibleDC failed")
	}
	defer procDeleteDC.Call(memDC)

	bmp, _, _ := procCreateCompatBitmap.Call(screenDC, uintptr(w), uintptr(h))
	if bmp == 0 {
		return nil, fmt.Errorf("CreateCompatibleBitmap failed")
	}
	defer procDeleteObject.Call(bmp)

	old, _, _ := procSelectObject.Call(memDC, bmp)

	ok, _, _ := procBitBlt.Call(memDC, 0, 0, uintptr(w), uintptr(h),
		screenDC, uintptr(int32(x0)), uintptr(int32(y0)), srcCopy|captureBLT)
	if ok == 0 {
		// Some drivers reject CAPTUREBLT; retry with a plain copy.
		ok, _, _ = procBitBlt.Call(memDC, 0, 0, uintptr(w), uintptr(h),
			screenDC, uintptr(int32(x0)), uintptr(int32(y0)), srcCopy)
	}

	// GetDIBits requires the bitmap NOT be selected into any DC, so deselect it
	// (restore the DC's default object) before reading the pixels.
	procSelectObject.Call(memDC, old)

	if ok == 0 {
		return nil, fmt.Errorf("BitBlt failed")
	}

	stride := w * 4
	need := stride * h
	if cap(c.buf) < need {
		c.buf = make([]byte, need)
	}
	bits := c.buf[:need]

	bi := bitmapInfoHeader{
		BiSize:        40,
		BiWidth:       int32(w),
		BiHeight:      int32(-h), // negative = top-down
		BiPlanes:      1,
		BiBitCount:    32,
		BiCompression: biRGB,
	}
	r, _, _ := procGetDIBits.Call(memDC, bmp, 0, uintptr(h),
		uintptr(unsafe.Pointer(&bits[0])), uintptr(unsafe.Pointer(&bi)), diBRGB)
	if r == 0 {
		return nil, fmt.Errorf("GetDIBits failed")
	}

	img := image.NewRGBA(image.Rect(0, 0, w, h))
	// GDI gives BGRA; convert to RGBA.
	for i := 0; i < need; i += 4 {
		img.Pix[i+0] = bits[i+2] // R
		img.Pix[i+1] = bits[i+1] // G
		img.Pix[i+2] = bits[i+0] // B
		img.Pix[i+3] = 255
	}

	var out bytes.Buffer
	if err := jpeg.Encode(&out, img, &jpeg.Options{Quality: clampQ(quality)}); err != nil {
		return nil, err
	}
	return &Frame{JPEG: out.Bytes(), Width: w, Height: h, Seq: atomic.AddUint64(&c.seq, 1)}, nil
}

func (c *winCapturer) Close() error { return nil }

var _ = kernel32
