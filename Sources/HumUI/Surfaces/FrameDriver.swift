import AppKit
import QuartzCore

/// Something that calls back once per display frame while running.
@MainActor
protocol FrameDriving: AnyObject {
    /// Receives the time the frame will be shown, in seconds on the uptime clock.
    var onFrame: ((TimeInterval) -> Void)? { get set }
    func start()
    func stop()
}

/// Frame callbacks from the display a view is on, so animation runs at that
/// display's refresh rate (including ProMotion). The link exists only while
/// something is moving; at rest there is nothing scheduled at all.
final class DisplayLinkFrameDriver: NSObject, FrameDriving {
    var onFrame: ((TimeInterval) -> Void)?
    private weak var view: NSView?
    private var link: CADisplayLink?

    init(view: NSView) {
        self.view = view
    }

    func start() {
        guard link == nil, let view else { return }
        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        onFrame?(link.targetTimestamp)
    }
}
