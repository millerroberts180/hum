import AppKit
@testable import HumUI
import SwiftUI
import Testing

/// Settings' and History's open and save panels come down as sheets on their
/// own window, key or not (DESIGN.md §4.5, §8).
@MainActor
@Suite("The window a view is in")
struct HostWindowTests {
    @Test func aViewFindsItsWindowAndLetsItGo() throws {
        let host = HostWindow()
        let view = NSHostingView(rootView: Color.clear.frame(width: 100, height: 100).readsHostWindow(into: host))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        #expect(host.window == nil)

        window.contentView = view
        view.layoutSubtreeIfNeeded()
        #expect(host.window === window)
        // Not the key window, which is what a click on an inactive app's window leaves.
        #expect(!window.isKeyWindow)

        window.contentView = nil
        #expect(host.window == nil)
    }
}
