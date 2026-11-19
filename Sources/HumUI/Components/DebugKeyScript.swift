#if DEBUG
import AppKit

/// Drives the keyboard paths for checks and screenshots:
/// `HUM_DEBUG_KEYS="cmd-3 down return"` sends those keys to Hum's own
/// window, one every 150 ms, once per launch. The events are made and delivered
/// inside Hum, through the same `sendEvent` path as typing; nothing reaches
/// other apps.
@MainActor
enum DebugKeyScript {
    private static var hasRun = false

    static func runIfRequested() {
        guard !hasRun, let script = ProcessInfo.processInfo.environment["HUM_DEBUG_KEYS"], !script.isEmpty else { return }
        hasRun = true
        let tokens = script.split(separator: " ").map(String.init)
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            for token in tokens {
                send(token)
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private static func send(_ token: String) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) else { return }
        let parts = token.split(separator: "-").map(String.init)
        var flags: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            switch part {
            case "cmd": flags.insert(.command)
            case "opt": flags.insert(.option)
            case "shift": flags.insert(.shift)
            case "ctrl": flags.insert(.control)
            default: break
            }
        }
        guard let name = parts.last, let key = key(named: name) else { return }
        if key.isFunction { flags.formUnion([.function, .numericPad]) }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: key.characters,
                charactersIgnoringModifiers: key.characters,
                isARepeat: false,
                keyCode: key.code
            ) else { continue }
            NSApp.sendEvent(event)
        }
        let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "none"
        FileHandle.standardError.write(Data("Hum debug key \(token) → \(responder) key=\(window.isKeyWindow)\n".utf8))
    }

    private struct Key {
        var code: UInt16
        var characters: String
        var isFunction = false
    }

    private static func key(named name: String) -> Key? {
        switch name {
        case "up": return Key(code: 126, characters: String(UnicodeScalar(0xF700)!), isFunction: true)
        case "down": return Key(code: 125, characters: String(UnicodeScalar(0xF701)!), isFunction: true)
        case "left": return Key(code: 123, characters: String(UnicodeScalar(0xF702)!), isFunction: true)
        case "right": return Key(code: 124, characters: String(UnicodeScalar(0xF703)!), isFunction: true)
        case "return": return Key(code: 36, characters: "\r")
        case "escape": return Key(code: 53, characters: "\u{1B}")
        case "delete": return Key(code: 51, characters: "\u{7F}")
        case "space": return Key(code: 49, characters: " ")
        case "tab": return Key(code: 48, characters: "\t")
        default:
            guard name.count == 1, let code = letterCodes[name] else { return nil }
            return Key(code: code, characters: name)
        }
    }

    /// ANSI key codes for the letters and digits.
    private static let letterCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31,
        "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]
}
#endif
