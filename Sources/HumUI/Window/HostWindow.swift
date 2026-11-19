import AppKit
import SwiftUI

/// The window a view is in, held weakly, so an open or save panel comes down
/// as a sheet on it. `NSApp.keyWindow` can't be relied on for that: a click
/// that brings a window of the inactive app forward runs the button's action
/// before the window is key, and the panel would float free, under the player.
@MainActor
final class HostWindow {
    weak var window: NSWindow?
}

extension View {
    /// Keeps `host` pointed at the window this view is in.
    func readsHostWindow(into host: HostWindow) -> some View {
        background(HostWindowReader(host: host))
    }
}

private struct HostWindowReader: NSViewRepresentable {
    var host: HostWindow

    func makeNSView(context: Context) -> ReportingView {
        let view = ReportingView()
        view.host = host
        return view
    }

    func updateNSView(_ view: ReportingView, context: Context) {
        view.host = host
        host.window = view.window
    }

    final class ReportingView: NSView {
        var host: HostWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            host?.window = window
        }
    }
}
