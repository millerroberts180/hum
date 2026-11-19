import CoreGraphics
import HumCore
@testable import HumUI
import SwiftUI
import Testing

/// Every style keeps all five transport controls at every size (DESIGN.md
/// §5.2, §3.8): where the row is wider than its room, the hit targets shrink,
/// and shuffle and repeat stay. Each control is found by drawing the player
/// with and without the source able to do it: a hidden control keeps its
/// space, so what changes is that control's glyph and nothing else.
@MainActor
@Suite("Transport at every size")
struct TransportPresenceTests {
    typealias Pixels = MissingArtworkTests.Pixels

    /// The five controls in order, and what the source needs for each.
    nonisolated static let controls: [(name: String, needs: SourceCapabilities)] = [
        ("Shuffle", [.shuffle]),
        ("Previous Track", [.skipPrevious, .scan]),
        ("Play", [.playPause]),
        ("Next Track", [.skipNext, .scan]),
        ("Repeat", [.repeatAll, .repeatOne]),
    ]

    /// Each player style at its smallest width and at its Small preset.
    nonisolated static let sizes: [(PlayerStyleID, CGFloat)] = [
        (.artOnly, 168), (.artOnly, 200),
        (.title, 240), (.title, 260),
        (.text, 180), (.text, 200),
        (.strip, 260), (.strip, 280),
        (.wide, 320),
        (.bigArt, 220), (.bigArt, 240),
    ]

    @Test func theSizesAreEachStylesMinimumAndSmallPreset() {
        for style in PlayerStyleID.allCases where style != .menuBar {
            let widths = Set(Self.sizes.filter { $0.0 == style }.map(\.1))
            let expected: Set<CGFloat> = [
                CGFloat(style.shape.widths.lowerBound),
                CGFloat(PlayerSizePreset.small.width(for: style)),
            ]
            #expect(widths == expected, "\(style)")
        }
    }

    /// The style's Now view as the player draws it with its controls showing,
    /// paused so that nothing moves between two drawings.
    static func render(
        _ style: PlayerStyleID,
        width: CGFloat,
        capabilities: SourceCapabilities = PreviewSource.capabilities,
        hoverControls: HoverControls = .all
    ) async throws -> Pixels {
        let player = PreviewPlayer(isPlaying: false, revealsControls: true, capabilities: capabilities)
        for _ in 0..<500 where player.store.artwork == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(player.store.artwork != nil)
        let history = PreviewHistory.shared
        for _ in 0..<500 where history.echo.songInsights.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        let size = style.shape.size(width: Double(width))
        let view = NowStyleSwitch()
            .frame(width: CGFloat(size.width), height: CGFloat(size.height))
            .environment(\.colorScheme, .dark)
            .environment(\.playerMetrics, PlayerMetrics(side: width))
            .environment(\.playerLook, PlayerLook(
                style: style,
                look: StyleLook(hoverControls: hoverControls),
                appearance: .dark,
                isBar: style.isBar || style.isLandscape
            ))
            .environment(player.store)
            .environment(player.settings)
            .environment(player.pager)
            .environment(player.interaction)
            .environment(history)
        let renderer = ImageRenderer(content: player.services.inject(view))
        renderer.scale = 1
        return try Pixels(try #require(renderer.cgImage))
    }

    /// The box around every pixel that differs between two drawings.
    static func difference(_ a: Pixels, _ b: Pixels) -> CGRect? {
        guard a.width == b.width, a.height == b.height else { return CGRect(x: 0, y: 0, width: a.width, height: a.height) }
        var minX = a.width, minY = a.height, maxX = -1, maxY = -1
        for y in 0..<a.height {
            for x in 0..<a.width {
                let start = (y * a.width + x) * 4
                let differs = (0..<4).contains { abs(Int(a.bytes[start + $0]) - Int(b.bytes[start + $0])) > 16 }
                if differs {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    @Test(arguments: sizes)
    func allFiveControlsDraw(style: PlayerStyleID, width: CGFloat) async throws {
        let all = try await Self.render(style, width: width)
        var boxes: [CGRect] = []
        for control in Self.controls {
            let without = try await Self.render(
                style, width: width, capabilities: PreviewSource.capabilities.subtracting(control.needs)
            )
            let box = try #require(Self.difference(all, without), "\(style) at \(width): no \(control.name)")
            // Only the glyph changed: the control keeps its space.
            #expect(box.width <= 32 && box.height <= 32, "\(style) at \(width): \(control.name) \(box)")
            // Inside the window, not clipped at its edge.
            #expect(box.minX >= 1 && box.maxX <= CGFloat(all.width) - 1, "\(style) at \(width): \(control.name) \(box)")
            boxes.append(box)
        }
        // One row, in order, play in the middle.
        #expect(boxes.map(\.midX) == boxes.map(\.midX).sorted(), "\(style) at \(width): \(boxes)")
        let row = boxes[2].midY
        for box in boxes {
            #expect(abs(box.midY - row) <= 4, "\(style) at \(width): \(boxes)")
        }
        // No two glyphs overlap.
        for (left, right) in zip(boxes, boxes.dropFirst()) {
            #expect(left.maxX <= right.minX, "\(style) at \(width): \(boxes)")
        }
    }

    /// With the look's switch off, shuffle and repeat aren't drawn at all.
    @Test(arguments: [(PlayerStyleID.artOnly, CGFloat(168)), (.bigArt, 220), (.wide, 320), (.title, 260)])
    func theLookCanLeaveOutShuffleAndRepeat(style: PlayerStyleID, width: CGFloat) async throws {
        let off = HoverControls.all.subtracting(.shuffleRepeat)
        let all = try await Self.render(style, width: width, hoverControls: off)
        for control in [Self.controls[0], Self.controls[4]] {
            let without = try await Self.render(
                style, width: width,
                capabilities: PreviewSource.capabilities.subtracting(control.needs),
                hoverControls: off
            )
            #expect(Self.difference(all, without) == nil, "\(style) at \(width): \(control.name) drawn")
        }
    }
}

/// The Menu Bar popover's transport follows the look's Shuffle and Repeat
/// switch, as every player style's does (DESIGN.md §7.1, §8).
@MainActor
@Suite("Menu Bar transport")
struct MenuBarTransportTests {
    typealias Pixels = MissingArtworkTests.Pixels

    static func render(capabilities: SourceCapabilities, hoverControls: HoverControls) async throws -> Pixels {
        let player = PreviewPlayer(isPlaying: false, revealsControls: true, capabilities: capabilities)
        for _ in 0..<500 where player.store.artwork == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(player.store.artwork != nil)
        let view = MenuBarNowView(popOut: {})
            .environment(\.colorScheme, .dark)
            .environment(\.playerLook, PlayerLook(
                style: .menuBar,
                look: StyleLook(hoverControls: hoverControls),
                appearance: .dark,
                isBar: false
            ))
            .environment(player.store)
            .environment(player.settings)
            .environment(player.pager)
            .environment(player.interaction)
        let renderer = ImageRenderer(content: player.services.inject(view))
        renderer.scale = 1
        return try Pixels(try #require(renderer.cgImage))
    }

    @Test func shuffleAndRepeatShowWithTheSwitchOn() async throws {
        let all = try await Self.render(capabilities: PreviewSource.capabilities, hoverControls: .all)
        for control in TransportPresenceTests.controls {
            let without = try await Self.render(
                capabilities: PreviewSource.capabilities.subtracting(control.needs), hoverControls: .all
            )
            let box = try #require(TransportPresenceTests.difference(all, without), "no \(control.name)")
            #expect(box.width <= 32 && box.height <= 32, "\(control.name) \(box)")
        }
    }

    @Test func theSwitchOffLeavesThreeControls() async throws {
        let off = HoverControls.all.subtracting(.shuffleRepeat)
        let all = try await Self.render(capabilities: PreviewSource.capabilities, hoverControls: off)
        for (index, control) in TransportPresenceTests.controls.enumerated() {
            let without = try await Self.render(
                capabilities: PreviewSource.capabilities.subtracting(control.needs), hoverControls: off
            )
            let box = TransportPresenceTests.difference(all, without)
            if index == 0 || index == 4 {
                #expect(box == nil, "\(control.name) drawn with the switch off")
            } else {
                #expect(box != nil, "no \(control.name)")
            }
        }
    }
}
