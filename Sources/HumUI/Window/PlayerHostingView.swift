import AppKit
import SwiftUI

/// Hosts the SwiftUI player and reports the pointer entering and leaving.
///
/// The pointer is tracked even while Hum isn't the active app (which is nearly
/// always), so hover reveals the controls without a click first. The first click
/// on an inactive player acts immediately instead of only focusing it.
final class PlayerHostingView<Content: View>: NSHostingView<Content> {
    var onPointerInsideChange: ((Bool) -> Void)?
    private var pointerArea: NSTrackingArea?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        // The window decides its size; the SwiftUI content fills whatever it's given.
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea {
            removeTrackingArea(pointerArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pointerArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea === pointerArea {
            onPointerInsideChange?(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === pointerArea {
            onPointerInsideChange?(false)
        }
    }

    /// Whether the pointer is over the view right now, for when the window
    /// appears under a pointer that never "entered" it.
    var containsPointer: Bool {
        guard let window else { return false }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(point)
    }
}
