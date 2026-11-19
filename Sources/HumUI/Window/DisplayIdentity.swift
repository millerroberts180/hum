import AppKit

/// A display's stable identity and usable area.
nonisolated struct DisplayInfo: Equatable, Sendable {
    var id: String
    /// The screen minus the menu bar and Dock, in global screen coordinates.
    var visibleFrame: CGRect
}

extension NSScreen {
    /// A key that survives reboots and rearranging displays: the display's UUID,
    /// or "main" if it has none.
    var displayKey: String {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String?
        else {
            return "main"
        }
        return string
    }

    var displayInfo: DisplayInfo {
        DisplayInfo(id: displayKey, visibleFrame: visibleFrame)
    }

    /// The screen under the pointer.
    static var withPointer: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? main
    }
}
