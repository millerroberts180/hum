import AppKit
import HumCore
@testable import HumUI
import SwiftUI
import Testing

/// Art Only drawn off screen as the player draws it, at its smallest and at
/// the Medium and Large presets, at rest and with its controls, light and
/// dark: each draws its cover, and the controls change what's drawn.
///
/// Set `HUM_STYLE_RENDERS` to a folder to keep the pictures as PNGs.
@MainActor
@Suite("Style renders")
struct StyleRenderTests {
    typealias Pixels = MissingArtworkTests.Pixels

    nonisolated static let folder = ProcessInfo.processInfo.environment["HUM_STYLE_RENDERS"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }

    nonisolated static let sizes: [(PlayerStyleID, CGFloat)] = [
        (.artOnly, 168), (.artOnly, 280), (.artOnly, 380),
    ]

    /// `content` in a borderless window off screen, drawn by AppKit so the
    /// materials draw as they do in the player (an `ImageRenderer` can't draw
    /// them).
    func render(
        _ content: some View,
        player: PreviewPlayer,
        size: CGSize,
        scheme: ColorScheme
    ) async throws -> NSBitmapImageRep {
        player.interaction.isWindowVisible = true
        let view = NSHostingView(rootView: player.services.inject(
            content
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, scheme)
                .environment(\.humMaterialsStayInWindow, true)
                .environment(player.store)
                .environment(player.settings)
                .environment(player.pager)
                .environment(player.interaction)
                .environment(PreviewHistory.shared)
        ))
        view.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = view
        defer { window.close() }
        for _ in 0..<10 {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    func ready(_ player: PreviewPlayer) async throws {
        for _ in 0..<500 where player.store.artwork == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(player.store.artwork != nil)
        let history = PreviewHistory.shared
        for _ in 0..<500 where history.echo.session == nil || history.echo.songInsights.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func write(_ rep: NSBitmapImageRep, _ name: String) throws {
        guard let folder = Self.folder else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: folder.appendingPathComponent("\(name).png"))
    }

    /// How many of the picture's pixels differ between two drawings.
    func changedShare(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) throws -> Double {
        let first = try Pixels(try #require(a.cgImage)), second = try Pixels(try #require(b.cgImage))
        guard first.bytes.count == second.bytes.count else { return 1 }
        var changed = 0
        for index in stride(from: 0, to: first.bytes.count, by: 4)
        where (0..<4).contains(where: { abs(Int(first.bytes[index + $0]) - Int(second.bytes[index + $0])) > 24 }) {
            changed += 1
        }
        return Double(changed) / Double(first.bytes.count / 4)
    }

    @Test(arguments: sizes, [ColorScheme.light, .dark])
    func theStyleDraws(size: (PlayerStyleID, CGFloat), scheme: ColorScheme) async throws {
        let (style, side) = size
        let appearance = LookAppearance(scheme)
        var drawn: [NSBitmapImageRep] = []
        for controls in [false, true] {
            let player = PreviewPlayer(revealsControls: controls)
            try await ready(player)
            let look = player.settings.appearance.look(for: style, in: appearance)
            let metrics = PlayerMetrics(side: side, cornerRadiusScale: CGFloat(look.cornerRadiusScale))
            let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
            let content = NowStyleSwitch()
                .environment(\.playerMetrics, metrics)
                .frame(width: side, height: side)
                .containerShape(shape)
                .clipShape(shape)
                .environment(\.playerLook, PlayerLook(style: style, look: look, appearance: appearance, isBar: false))
            let rep = try await render(content, player: player, size: CGSize(width: side, height: side), scheme: scheme)
            #expect(rep.pixelsWide >= Int(side) && rep.pixelsHigh == rep.pixelsWide)
            try write(rep, "\(style.rawValue)-\(Int(side))-\(scheme == .dark ? "dark" : "light")-\(controls ? "controls" : "rest")")
            drawn.append(rep)
        }
        let share = try changedShare(drawn[0], drawn[1])
        #expect(share > 0.01, "\(style) at \(side) \(scheme): the controls changed \(share) of it")
    }

    /// Echo at the Small and Medium presets, where its cards show their range
    /// and source (§6.5).
    @Test(arguments: [240.0, 280], [ColorScheme.light, .dark])
    func echoDraws(side: CGFloat, scheme: ColorScheme) async throws {
        let player = PreviewPlayer()
        try await ready(player)
        let metrics = PlayerMetrics(side: side)
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
        let content = EchoSurface()
            .background { ArtBackdrop(artwork: player.store.artwork) }
            .environment(\.playerMetrics, metrics)
            .frame(width: side, height: side)
            .clipShape(shape)
        let rep = try await render(content, player: player, size: CGSize(width: side, height: side), scheme: scheme)
        #expect(rep.pixelsWide >= Int(side))
        try write(rep, "echo-\(Int(side))-\(scheme == .dark ? "dark" : "light")")
    }

    /// The Menu Bar popover, with the look's Shuffle and Repeat switch on and off.
    @Test(arguments: [true, false], [ColorScheme.light, .dark])
    func menuBarDraws(showsShuffleRepeat: Bool, scheme: ColorScheme) async throws {
        let player = PreviewPlayer()
        try await ready(player)
        let controls = showsShuffleRepeat ? HoverControls.all : HoverControls.all.subtracting(.shuffleRepeat)
        let content = MenuBarNowView(popOut: {})
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.playerLook, PlayerLook(
                style: .menuBar, look: StyleLook(hoverControls: controls), appearance: LookAppearance(scheme), isBar: false
            ))
            .fixedSize()
        let rep = try await render(content, player: player, size: CGSize(width: MenuBarNowView.width, height: 420), scheme: scheme)
        #expect(rep.pixelsWide >= Int(MenuBarNowView.width))
        try write(rep, "menubar-\(showsShuffleRepeat ? "shuffle-on" : "shuffle-off")-\(scheme == .dark ? "dark" : "light")")
    }
}
