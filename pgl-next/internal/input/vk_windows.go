//go:build windows

package input

// codeToVK maps a browser KeyboardEvent.code to a Windows virtual-key code.
var codeToVK = buildVKMap()

func buildVKMap() map[string]uint16 {
	m := map[string]uint16{
		"ArrowLeft": 0x25, "ArrowUp": 0x26, "ArrowRight": 0x27, "ArrowDown": 0x28,
		"Enter": 0x0D, "NumpadEnter": 0x0D, "Escape": 0x1B, "Backspace": 0x08,
		"Tab": 0x09, "Space": 0x20, "CapsLock": 0x14,
		"ShiftLeft": 0xA0, "ShiftRight": 0xA1,
		"ControlLeft": 0xA2, "ControlRight": 0xA3,
		"AltLeft": 0xA4, "AltRight": 0xA5,
		"MetaLeft": 0x5B, "MetaRight": 0x5C, "ContextMenu": 0x5D,
		"Delete": 0x2E, "Insert": 0x2D, "Home": 0x24, "End": 0x23,
		"PageUp": 0x21, "PageDown": 0x22, "PrintScreen": 0x2C, "Pause": 0x13,
		"Semicolon": 0xBA, "Equal": 0xBB, "Comma": 0xBC, "Minus": 0xBD,
		"Period": 0xBE, "Slash": 0xBF, "Backquote": 0xC0, "BracketLeft": 0xDB,
		"Backslash": 0xDC, "BracketRight": 0xDD, "Quote": 0xDE,
		"NumpadMultiply": 0x6A, "NumpadAdd": 0x6B, "NumpadSubtract": 0x6D,
		"NumpadDecimal": 0x6E, "NumpadDivide": 0x6F, "NumLock": 0x90,
	}
	// Letters KeyA..KeyZ -> VK 0x41..0x5A
	for i := 0; i < 26; i++ {
		m["Key"+string(rune('A'+i))] = uint16(0x41 + i)
	}
	// Digits Digit0..Digit9 -> VK 0x30..0x39
	for i := 0; i < 10; i++ {
		m["Digit"+string(rune('0'+i))] = uint16(0x30 + i)
	}
	// Numpad0..Numpad9 -> VK 0x60..0x69
	for i := 0; i < 10; i++ {
		m["Numpad"+string(rune('0'+i))] = uint16(0x60 + i)
	}
	// F1..F12 -> VK 0x70..0x7B
	for i := 0; i < 12; i++ {
		m["F"+itoa(i+1)] = uint16(0x70 + i)
	}
	return m
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [4]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}
