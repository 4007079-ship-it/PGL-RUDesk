//go:build windows

// Windows input injection via SendInput. Pure Go via syscall, no CGO.
package input

import (
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	user32               = windows.NewLazySystemDLL("user32.dll")
	procSendInput        = user32.NewProc("SendInput")
	procGetSystemMetrics = user32.NewProc("GetSystemMetrics")
)

const (
	smXVirtualScreen  = 76
	smYVirtualScreen  = 77
	smCXVirtualScreen = 78
	smCYVirtualScreen = 79

	inputMouse    = 0
	inputKeyboard = 1

	mouseeventfMove        = 0x0001
	mouseeventfLeftDown    = 0x0002
	mouseeventfLeftUp      = 0x0004
	mouseeventfRightDown   = 0x0008
	mouseeventfRightUp     = 0x0010
	mouseeventfMiddleDown  = 0x0020
	mouseeventfMiddleUp    = 0x0040
	mouseeventfWheel       = 0x0800
	mouseeventfHWheel      = 0x01000
	mouseeventfAbsolute    = 0x8000
	mouseeventfVirtualDesk = 0x4000

	keyeventfKeyUp   = 0x0002
	keyeventfUnicode = 0x0004
	keyeventfScancode = 0x0008

	wheelDelta = 120
)

// Both structs are exactly 40 bytes (the size of INPUT on amd64), so SendInput
// reads the correct number of bytes regardless of which one is passed.
type mouseInput struct {
	typ         uint32
	_           uint32
	dx          int32
	dy          int32
	mouseData   uint32
	dwFlags     uint32
	time        uint32
	_           uint32
	dwExtraInfo uintptr
}

type keybdInput struct {
	typ         uint32
	_           uint32
	wVk         uint16
	wScan       uint16
	dwFlags     uint32
	time        uint32
	_           uint32
	dwExtraInfo uintptr
	_           [8]byte
}

// Compile-time guarantee that both INPUT variants are exactly 40 bytes, the
// size of INPUT on amd64. A wrong field layout fails the build here instead of
// corrupting SendInput calls on a real machine.
const (
	_ = 40 - uint(unsafe.Sizeof(mouseInput{}))
	_ = uint(unsafe.Sizeof(mouseInput{})) - 40
	_ = 40 - uint(unsafe.Sizeof(keybdInput{}))
	_ = uint(unsafe.Sizeof(keybdInput{})) - 40
)

type winInjector struct{}

func init() {
	Factory = func() (Injector, error) { return &winInjector{}, nil }
}

func metric(i int) int {
	r, _, _ := procGetSystemMetrics.Call(uintptr(i))
	return int(int32(r))
}

func sendMouse(in *mouseInput) {
	in.typ = inputMouse
	procSendInput.Call(1, uintptr(unsafe.Pointer(in)), 40)
}

func sendKey(in *keybdInput) {
	in.typ = inputKeyboard
	procSendInput.Call(1, uintptr(unsafe.Pointer(in)), 40)
}

func (w *winInjector) MoveMouse(x, y int) {
	cx := metric(smCXVirtualScreen)
	cy := metric(smCYVirtualScreen)
	if cx <= 1 || cy <= 1 {
		return
	}
	// Normalize into 0..65535 across the whole virtual desktop.
	nx := int32(int64(x) * 65535 / int64(cx-1))
	ny := int32(int64(y) * 65535 / int64(cy-1))
	sendMouse(&mouseInput{
		dx: nx, dy: ny,
		dwFlags: mouseeventfMove | mouseeventfAbsolute | mouseeventfVirtualDesk,
	})
}

func (w *winInjector) MouseButton(button int, down bool) {
	var flag uint32
	switch button {
	case 0: // left
		flag = pick(down, mouseeventfLeftDown, mouseeventfLeftUp)
	case 1: // middle
		flag = pick(down, mouseeventfMiddleDown, mouseeventfMiddleUp)
	case 2: // right
		flag = pick(down, mouseeventfRightDown, mouseeventfRightUp)
	default:
		return
	}
	sendMouse(&mouseInput{dwFlags: flag})
}

func (w *winInjector) Scroll(dx, dy int) {
	if dy != 0 {
		sendMouse(&mouseInput{mouseData: uint32(int32(-dy * wheelDelta)), dwFlags: mouseeventfWheel})
	}
	if dx != 0 {
		sendMouse(&mouseInput{mouseData: uint32(int32(dx * wheelDelta)), dwFlags: mouseeventfHWheel})
	}
}

func (w *winInjector) Key(code string, down bool) {
	vk, ok := codeToVK[code]
	if !ok {
		return
	}
	in := &keybdInput{wVk: vk}
	if !down {
		in.dwFlags = keyeventfKeyUp
	}
	sendKey(in)
}

func (w *winInjector) Text(s string) {
	for _, r := range s {
		for _, u := range utf16Units(r) {
			sendKey(&keybdInput{wScan: u, dwFlags: keyeventfUnicode})
			sendKey(&keybdInput{wScan: u, dwFlags: keyeventfUnicode | keyeventfKeyUp})
		}
	}
}

func (w *winInjector) Close() error { return nil }

func pick(cond bool, a, b uint32) uint32 {
	if cond {
		return a
	}
	return b
}

func utf16Units(r rune) []uint16 {
	if r <= 0xFFFF {
		return []uint16{uint16(r)}
	}
	r -= 0x10000
	return []uint16{uint16(0xD800 + (r >> 10)), uint16(0xDC00 + (r & 0x3FF))}
}
