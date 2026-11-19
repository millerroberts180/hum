import AppKit
import HumCore
@testable import HumUI
import SwiftUI
import Testing

/// Every Settings pane drawn off screen as the Settings window draws it, in
/// light and dark, and the full length of the panes that scroll, for a few
/// styles each. Nothing is put on screen.
///
/// Set `HUM_SETTINGS_RENDERS` to a folder to keep the pictures as PNGs.
@MainActor
@Suite("Settings renders", .serialized)
struct SettingsPaneRenderTests {
    nonisolated static let folder = ProcessInfo.processInfo.environment["HUM_SETTINGS_RENDERS"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }

    /// The width the detail column gives a pane.
    static let paneWidth = SettingsMetrics.windowSize.width - SettingsMetrics.sidebarWidth
    /// Room for the longest pane, so a full-length render shows every row.
    static let fullHeight: CGFloat = 1800

    struct Picture {
        let rep: NSBitmapImageRep

        /// The mean luminance, 0...1, of every fourth pixel.
        var meanLuminance: Double {
            var total = 0.0, count = 0
            for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
                for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                    guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    total += 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
                    count += 1
                }
            }
            return count == 0 ? 0 : total / Double(count)
        }

        /// How many different colors every fourth pixel takes, to 5 bits a
        /// channel. A blank or one-color picture has a handful.
        var distinctColors: Int {
            var colors = Set<Int>()
            for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
                for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                    guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    let r = Int(color.redComponent * 31), g = Int(color.greenComponent * 31), b = Int(color.blueComponent * 31)
                    colors.insert(r << 10 | g << 5 | b)
                }
            }
            return colors.count
        }

        func write(_ name: String) throws {
            guard let folder = SettingsPaneRenderTests.folder else { return }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }

    /// A demo player with its cover in, in `style`, and a player size and pin
    /// for Settings to show.
    func harness(style: PlayerStyleID) async throws -> (PreviewPlayer, PlayerSizing) {
        let player = PreviewPlayer()
        player.settings.appearance.style = style
        for _ in 0..<500 where player.store.artwork == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(player.store.artwork != nil)
        let sizing = PlayerSizing()
        sizing.size = StyleGeometry.defaultSize(for: style)
        sizing.pin = .topRight
        return (player, sizing)
    }

    func environment(_ view: some View, player: PreviewPlayer, sizing: PlayerSizing) -> AnyView {
        player.services.inject(
            view
                .environment(player.settings)
                .environment(player.store)
                .environment(sizing)
        )
    }

    /// `content` in a window far off screen, never ordered in, drawn once it
    /// has settled.
    func capture(_ content: NSViewController, size: CGSize, appearance: LookAppearance, toolbar: Bool) async throws -> Picture {
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        if toolbar {
            window.toolbarStyle = .unified
            window.toolbar = NSToolbar()
        }
        window.contentViewController = content
        window.setContentSize(size)
        window.setFrameOrigin(CGPoint(x: -20000, y: -20000))
        defer { window.close() }
        let view = try #require(window.contentView)
        // Let SwiftUI lay out, load the tile icons, and settle its animations.
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return Picture(rep: rep)
    }

    /// The Settings window on `pane`, as `SettingsWindowPresenter` makes it.
    func window(_ pane: SettingsPane, style: PlayerStyleID = .artOnly, appearance: LookAppearance) async throws -> Picture {
        let (player, sizing) = try await harness(style: style)
        let navigation = SettingsNavigation(pane: pane)
        let controller = NSHostingController(rootView: environment(SettingsView().environment(navigation), player: player, sizing: sizing))
        controller.sceneBridgingOptions = [.title, .toolbars]
        return try await capture(controller, size: SettingsMetrics.windowSize, appearance: appearance, toolbar: true)
    }

    /// One pane at its full length, without the window around it.
    func fullPane(_ pane: some View, style: PlayerStyleID, appearance: LookAppearance) async throws -> Picture {
        let (player, sizing) = try await harness(style: style)
        let size = CGSize(width: Self.paneWidth, height: Self.fullHeight)
        let controller = NSHostingController(rootView: environment(pane.frame(width: size.width, height: size.height), player: player, sizing: sizing))
        return try await capture(controller, size: size, appearance: appearance, toolbar: false)
    }

    @Test(arguments: SettingsPane.allCases)
    func everyPaneDrawsInLightAndDark(pane: SettingsPane) async throws {
        let light = try await window(pane, appearance: .light)
        let dark = try await window(pane, appearance: .dark)
        try light.write("window-\(pane.rawValue)-light")
        try dark.write("window-\(pane.rawValue)-dark")
        #expect(light.distinctColors > 40, "\(pane) light looks blank")
        #expect(dark.distinctColors > 40, "\(pane) dark looks blank")
        #expect(dark.meanLuminance < light.meanLuminance - 0.2, "\(pane) doesn't follow the appearance")
    }

    @Test(arguments: [PlayerStyleID.artOnly, .text, .bigArt, .menuBar])
    func appearanceDrawsEveryRowForTheStyle(style: PlayerStyleID) async throws {
        for appearance in LookAppearance.allCases {
            let picture = try await fullPane(AppearanceSettingsPane(), style: style, appearance: appearance)
            try picture.write("full-appearance-\(style.rawValue)-\(appearance.rawValue)")
            #expect(picture.distinctColors > 200, "\(style) \(appearance)")
        }
    }

    @Test(arguments: [PlayerStyleID.artOnly, .title, .menuBar])
    func playerDrawsEveryRowForTheStyle(style: PlayerStyleID) async throws {
        for appearance in LookAppearance.allCases {
            let picture = try await fullPane(PlayerSettingsPane(), style: style, appearance: appearance)
            try picture.write("full-player-\(style.rawValue)-\(appearance.rawValue)")
            if style.hasWindow {
                #expect(picture.distinctColors > 100, "\(style) \(appearance) is missing its tiles")
            } else {
                // Switches and text only: the size, position, and visibility
                // tiles hide, but the pane isn't blank.
                #expect((10...100).contains(picture.distinctColors), "\(style) \(appearance)")
            }
        }
    }

    @Test func sourcesDrawsItsTiles() async throws {
        for appearance in LookAppearance.allCases {
            let picture = try await fullPane(SourcesSettingsPane(), style: .artOnly, appearance: appearance)
            try picture.write("full-sources-\(appearance.rawValue)")
            #expect(picture.distinctColors > 40, "\(appearance)")
        }
    }
}
