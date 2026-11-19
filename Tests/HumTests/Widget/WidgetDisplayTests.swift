import CoreGraphics
import Foundation
import HumCore
@testable import HumUI
@testable import HumWidgets
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
import WidgetKit

@MainActor
@Suite("Widgets for every display")
struct WidgetDisplayTests {
    /// The displays with a widget: Art Only, Title and Text (DESIGN.md §7.3,
    /// §13.33).
    nonisolated static let widgetDisplays = WidgetDisplay.allCases

    // MARK: The gallery

    @Test func theWidgetsAreTheOnesTheDesignKeepsInTheirSizes() {
        // DESIGN.md §7.3: Art Only small and large, Title medium, Text small.
        // Strip, Wide, Big Art and Menu Bar have none (§13.33).
        let expected: [WidgetDisplay: [WidgetFamily]] = [
            .artOnly: [.systemSmall, .systemLarge],
            .title: [.systemMedium],
            .text: [.systemSmall],
        ]
        #expect(Self.widgetDisplays.map(\.style) == [.artOnly, .title, .text])
        for display in Self.widgetDisplays {
            #expect(DisplayWidget.families(display) == expected[display], "\(display.style.title)")
        }
        #expect(Set(Self.widgetDisplays.map(DisplayWidget.kind)).count == Self.widgetDisplays.count)
    }

    /// The kinds are the ones placed widgets already have, so they keep their
    /// places across builds.
    @Test func theKindsKeepTheirNames() {
        #expect(DisplayWidget.kind(.artOnly) == "com.millerroberts.hum.widget.artOnly")
        #expect(DisplayWidget.kind(.title) == "com.millerroberts.hum.widget.title")
        #expect(DisplayWidget.kind(.text) == "com.millerroberts.hum.widget.minimal")
    }

    @Test func eachDescriptionIsOneSentenceInHumsVoice() {
        for display in Self.widgetDisplays {
            let style = display.style
            let description = DisplayWidget.description(display)
            #expect(!description.contains("\n"), "\(style.title)")
            #expect(description.hasSuffix("."), "\(style.title)")
            #expect(description.filter { $0 == "." }.count == 1, "\(style.title)")
            #expect(description.count <= 60, "\(style.title): \(description.count) characters")
            // Curly apostrophes and quotes only (DESIGN.md §10).
            #expect(!description.contains("'") && !description.contains("\""), "\(style.title)")
            // The widgets never name the music app.
            #expect(!description.contains("Spotify") && !description.contains("Music"), "\(style.title)")
            #expect(description.first?.isUppercase == true, "\(style.title)")
        }
    }

    // MARK: Tokens restated from the app

    @Test func theTokensMatchTheApps() {
        #expect(WidgetSpacing.xxs == Spacing.xxs)
        #expect(WidgetSpacing.xs == Spacing.xs)
        #expect(WidgetSpacing.s == Spacing.s)
        #expect(WidgetSpacing.m == Spacing.m)
        #expect(WidgetSpacing.l == Spacing.l)
        #expect(WidgetRadius.artMedium == Radius.artMedium)
        // The title: the player's M size in small and medium widgets, its L
        // size in large ones (§7.3).
        #expect(WidgetType.trackTitle(.systemSmall) == HumType.trackTitle.style(for: .medium))
        #expect(WidgetType.trackTitle(.systemMedium) == HumType.trackTitle.style(for: .medium))
        #expect(WidgetType.trackTitle(.systemLarge) == HumType.trackTitle.style(for: .large))
        for (metrics, sizeClass) in [(TransportMetrics.medium, PlayerSizeClass.medium), (.large, .large)] {
            #expect(metrics.play == ControlSizing.play(sizeClass).glyph)
            #expect(metrics.playHit == ControlSizing.play(sizeClass).hit)
            #expect(metrics.skip == ControlSizing.skip(sizeClass).glyph)
            #expect(metrics.skipHit == ControlSizing.skip(sizeClass).hit)
            #expect(metrics.tertiary == ControlSizing.tertiary(sizeClass).glyph)
            #expect(metrics.tertiaryHit == ControlSizing.tertiary(sizeClass).hit)
        }
        // The scrubber over the cover, at rest and under Increase Contrast (§5.2).
        func scrubber(_ role: HumColor.Role, increasedContrast: Bool = false) -> String {
            HumColor.scrubberColor(role, context: .artwork, isDark: true, increasedContrast: increasedContrast)?.description ?? "none"
        }
        #expect(SeekColors.overArt.fill.description == scrubber(.scrubberFill))
    }

    @Test(arguments: [(170.0, 40.0), (364.0, 120.0), (364.0, 200.0), (382.0, 300.0), (200.0, 400.0)])
    func theScrimIsThePlayers(side: Double, content: Double) {
        #expect(WidgetScrim.bandHeight(side: side, contentHeight: content) == Scrim.bandHeight(side: side, contentHeight: content))
        #expect(WidgetScrim.featheredHeight(side: side, contentHeight: content) == Scrim.featheredHeight(side: side, contentHeight: content))
        #expect(WidgetScrim.minimumRamp == Spacing.xxl)
        let height = WidgetScrim.featheredHeight(side: side, contentHeight: content)
        let ramp = Scrim.ramp(height: height, contentHeight: content)
        for peak in [WidgetScrim.peak, WidgetScrim.increasedContrastPeak] {
            let ours = WidgetScrim.stops(peak: peak, ramp: ramp)
            let theirs = Scrim.stops(peak: peak, ramp: ramp)
            #expect(ours.map(\.location) == theirs.map(\.location))
            #expect(ours.map { $0.color.description } == theirs.map { $0.color.description })
        }
        #expect(WidgetScrim.peak == Scrim.peak)
        #expect(WidgetScrim.increasedContrastPeak == Scrim.increasedContrastPeak)
        #expect(WidgetScrim.reducedTransparencyOpacity == Scrim.reducedTransparencyOpacity)
    }

    // MARK: Hum's mark

    @Test func theMarkIsTheIconScriptsSmallCut() throws {
        // The numbers in vibratoPath(small: true), in order.
        let script = try String(contentsOf: AppBundleResourceTests.repository.appendingPathComponent("scripts/make-icon.swift"), encoding: .utf8)
        let start = try #require(script.range(of: "if small {"))
        let end = try #require(script.range(of: "} else {", range: start.upperBound..<script.endIndex))
        let block = script[start.upperBound..<end.lowerBound]
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        // Whole numbers only: not the digits in `control1:`.
        let number = try Regex(#"-?\b\d+(?:\.\d+)?"#)
        let scriptNumbers = block.matches(of: number).map { Double(block[$0.range])! }

        var markNumbers: [Double] = []
        HumMark.gridPath.forEach { element in
            switch element {
            case .move(let point), .line(let point):
                markNumbers += [point.x, point.y]
            case .curve(let to, let control1, let control2):
                markNumbers += [to.x, to.y, control1.x, control1.y, control2.x, control2.y]
            case .quadCurve(let to, let control):
                markNumbers += [to.x, to.y, control.x, control.y]
            case .closeSubpath:
                break
            }
        }
        #expect(!markNumbers.isEmpty)
        #expect(markNumbers == scriptNumbers)
    }

    @Test func theMarkFitsItsStatedBounds() {
        let stroked = HumMark.gridPath.strokedPath(StrokeStyle(lineWidth: HumMark.stroke, lineCap: .round, lineJoin: .round))
        let bounds = stroked.boundingRect
        #expect(abs(bounds.minX - HumMark.bounds.minX) < 0.5)
        #expect(abs(bounds.maxX - HumMark.bounds.maxX) < 0.5)
        #expect(abs(bounds.minY - HumMark.bounds.minY) < 0.5)
        #expect(abs(bounds.maxY - HumMark.bounds.maxY) < 0.5)
    }

    // MARK: The timeline

    func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hum-widget-provider-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func aPlayingSongGetsAnEntryNowAndAPausedOneAtItsEnd() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try WidgetFiles.write(.demo(at: now), cover: nil, to: directory)
        let entries = HumProvider(directory: directory).entries(at: now.addingTimeInterval(10))
        #expect(entries.count == 2)
        #expect(entries[0].date == now.addingTimeInterval(10))
        #expect(entries[0].playback.isPlaying)
        #expect(entries[1].date == now.addingTimeInterval(214 - 62))
        #expect(entries[1].playback == .paused(position: 214, duration: 214))
    }

    @Test func aStaleOrPausedSongGetsOneEntryShowingItPaused() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try WidgetFiles.write(.demo(at: now), cover: nil, to: directory)
        // Hum stopped writing an hour ago, mid-song.
        let stale = HumProvider(directory: directory).entries(at: now.addingTimeInterval(3600))
        #expect(stale.count == 1)
        #expect(stale[0].playback == .paused(position: 214, duration: 214))
        #expect(stale[0].song?.title == "Low Tide Radio")

        var paused = WidgetSnapshot.demo(at: now)
        paused.isPlaying = false
        try WidgetFiles.write(paused, cover: nil, to: directory)
        let entries = HumProvider(directory: directory).entries(at: now.addingTimeInterval(3600))
        #expect(entries.count == 1)
        #expect(entries[0].playback == .paused(position: 62, duration: 214))
    }

    @Test func noSnapshotIsNothingPlaying() {
        let entries = HumProvider(directory: folder()).entries(at: .now)
        #expect(entries.count == 1)
        #expect(entries[0].song == nil)
        #expect(entries[0].playback == .nothingPlaying)
    }

    @Test func theCoverIsReadFromBesideTheSnapshot() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        try WidgetFiles.write(.demo(at: now), cover: WidgetSnapshotWriterTests.png(side: 600), to: directory)
        let entry = try #require(HumProvider(directory: directory).entries(at: now).first)
        guard case .image(let image) = entry.cover else {
            Issue.record("no cover")
            return
        }
        #expect(image.width == 600)
    }

    @Test func theGalleryShowsTheDemoSongPlaying() {
        let entry = HumEntry.demo(at: .now)
        #expect(entry.song?.title == "Low Tide Radio")
        #expect(entry.playback.isPlaying)
        guard case .demo = entry.cover else {
            Issue.record("the gallery has no drawn cover")
            return
        }
    }

    // MARK: Renders

    /// The sizes macOS gives each family, in points, and its default margins.
    static let sizes: [WidgetFamily: CGSize] = [
        .systemSmall: CGSize(width: 170, height: 170),
        .systemMedium: CGSize(width: 364, height: 170),
        .systemLarge: CGSize(width: 364, height: 382),
    ]
    static let margins = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)

    /// Where renders go: `HUM_WIDGET_RENDERS` when set, a temporary folder otherwise.
    static let renders: URL = {
        if let path = ProcessInfo.processInfo.environment["HUM_WIDGET_RENDERS"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("hum-widget-renders", isDirectory: true)
    }()

    /// A widget as the desktop draws it: its background, its content, its corners.
    struct Tile: View {
        var display: WidgetDisplay
        var family: WidgetFamily
        var entry: HumEntry

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            let size = WidgetDisplayTests.sizes[family]!
            ZStack {
                // The system background is translucent; this stands in for the desktop under it.
                WidgetDisplayTests.desktop(colorScheme)
                WidgetBackgroundView(kind: entry.song == nil ? .system : DisplayView.background(display), entry: entry)
                DisplayView(display: display, entry: entry, layout: WidgetLayout(family: family, margins: WidgetDisplayTests.margins))
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    static func desktop(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.12) : Color(white: 0.9)
    }

    enum State: String, CaseIterable {
        case playing, paused, stale, nothingPlaying = "nothing-playing"
        /// A title and artist too long for any widget, to see them truncate.
        case longTitle = "long-title"
    }

    func entry(_ state: State, at now: Date) -> HumEntry {
        switch state {
        case .playing:
            return .demo(at: now)
        case .paused:
            var snapshot = WidgetSnapshot.demo(at: now)
            snapshot.isPlaying = false
            snapshot.shuffle = true
            var entry = HumEntry(snapshot: snapshot, at: now, directory: nil)
            entry.cover = .demo
            return entry
        case .stale:
            var entry = HumEntry(snapshot: .demo(at: now.addingTimeInterval(-3600)), at: now, directory: nil)
            entry.cover = .demo
            return entry
        case .nothingPlaying:
            return HumEntry(snapshot: .nothingPlaying, at: now, directory: nil)
        case .longTitle:
            var snapshot = WidgetSnapshot.demo(at: now)
            snapshot.song?.title = "The Longest Song Title Anyone Has Ever Given a Track, Extended Version"
            snapshot.song?.artist = "An Orchestra With a Name Much Too Long to Fit"
            var entry = HumEntry(snapshot: snapshot, at: now, directory: nil)
            entry.cover = .demo
            return entry
        }
    }

    func render(_ view: some View, scheme: ColorScheme) throws -> CGImage {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = 2
        return try #require(renderer.cgImage)
    }

    func save(_ image: CGImage, as name: String) throws {
        try FileManager.default.createDirectory(at: Self.renders, withIntermediateDirectories: true)
        let url = Self.renders.appendingPathComponent(name + ".png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// How many distinct colors the image holds, sampled on a grid: a blank
    /// render has one or two.
    func colorCount(_ image: CGImage) throws -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var colors = Set<UInt32>()
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let i = (y * width + x) * 4
                colors.insert(UInt32(data[i] >> 4) << 8 | UInt32(data[i + 1] >> 4) << 4 | UInt32(data[i + 2] >> 4))
            }
        }
        return colors.count
    }

    @Test(arguments: Self.widgetDisplays)
    func everyWidgetDrawsInEveryStateAndAppearance(_ display: WidgetDisplay) throws {
        let now = Date()
        let style = display.style
        for family in DisplayWidget.families(display) {
            let size = try #require(Self.sizes[family])
            for scheme in [ColorScheme.light, .dark] {
                for state in State.allCases {
                    let image = try render(Tile(display: display, family: family, entry: entry(state, at: now)), scheme: scheme)
                    #expect(image.width == Int(size.width * 2) && image.height == Int(size.height * 2))
                    #expect(try colorCount(image) > 8, "\(style.title) \(family) \(state) looks blank")
                    try save(image, as: "\(style.rawValue)-\(family.name)-\(state.rawValue)-\(scheme == .dark ? "dark" : "light")")
                }
            }
        }
    }

    /// Every widget on one sheet per appearance, to look at side by side.
    @Test func theGallerySheets() throws {
        let now = Date()
        for scheme in [ColorScheme.light, .dark] {
            for states in [[State.playing], [.paused, .nothingPlaying], [.longTitle]] {
                let sheet = VStack(alignment: .leading, spacing: 24) {
                    ForEach(Self.widgetDisplays, id: \.self) { display in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(display.style.title).font(.headline)
                            HStack(alignment: .top, spacing: 24) {
                                ForEach(states, id: \.self) { state in
                                    ForEach(DisplayWidget.families(display), id: \.self) { family in
                                        Tile(display: display, family: family, entry: entry(state, at: now))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(32)
                .background(Self.desktop(scheme))
                let image = try render(sheet, scheme: scheme)
                try save(image, as: "sheet-\(states.map(\.rawValue).joined(separator: "+"))-\(scheme == .dark ? "dark" : "light")")
            }
        }
    }
}

extension WidgetFamily {
    var name: String {
        switch self {
        case .systemSmall: "small"
        case .systemMedium: "medium"
        case .systemLarge: "large"
        default: "other"
        }
    }
}
