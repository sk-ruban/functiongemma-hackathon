import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum KeyboardSimulator {
    static func pressShortcut(_ shortcut: String) -> Bool {
        let parts = shortcut
            .replacingOccurrences(of: " ", with: "")
            .split(separator: "+")
            .map { String($0).lowercased() }

        var flags: CGEventFlags = []
        var keyCode: CGKeyCode?

        for part in parts {
            switch part {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default:
                keyCode = Self.keyCodeFor(part)
            }
        }

        guard let code = keyCode else { return false }

        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
            return false
        }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    static func typeText(_ text: String) {
        for char in text {
            if char == "\n" || char == "\r" {
                _ = pressShortcut("Return")
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }

            let str = String(char)
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { continue }

            var utf16 = Array(str.utf16)
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private static func keyCodeFor(_ key: String) -> CGKeyCode? {
        let map: [String: CGKeyCode] = [
            "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02,
            "e": 0x0E, "f": 0x03, "g": 0x05, "h": 0x04,
            "i": 0x22, "j": 0x26, "k": 0x28, "l": 0x25,
            "m": 0x2E, "n": 0x2D, "o": 0x1F, "p": 0x23,
            "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
            "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07,
            "y": 0x10, "z": 0x06,
            "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14,
            "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A,
            "8": 0x1C, "9": 0x19,
            "return": 0x24, "enter": 0x24, "tab": 0x30,
            "space": 0x31, "escape": 0x35, "esc": 0x35,
            "delete": 0x33, "backspace": 0x33,
            "forwarddelete": 0x75,
            "up": 0x7E, "down": 0x7D, "left": 0x7B, "right": 0x7C,
            "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
            "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
            "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
            "-": 0x1B, "=": 0x18, "[": 0x21, "]": 0x1E,
            "\\": 0x2A, ";": 0x29, "'": 0x27, ",": 0x2B,
            ".": 0x2F, "/": 0x2C, "`": 0x32,
        ]
        return map[key]
    }
}
