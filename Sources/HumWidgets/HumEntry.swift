import AppKit
import HumCore
import ImageIO
import SwiftUI
import WidgetKit

/// One moment of a widget's timeline: the snapshot as it reads at `date`.
struct HumEntry: TimelineEntry, @unchecked Sendable {
    var date: Date
    var snapshot: WidgetSnapshot
    var playback: WidgetPlayback
    var cover: Cover
    /// The accent for active toggles over the cover or on dark material, and on
    /// light material (DESIGN.md §3.5.3: each context gets its own variant).
    var accentOnDark: Color
    var accentOnLight: Color

    enum Cover {
        case image(CGImage)
        /// The gallery's drawn cover.
        case demo
        case none
    }

    var song: WidgetSnapshot.Song? { snapshot.song }
    var palette: ArtworkPalette { snapshot.palette ?? .neutral }
}

extension HumEntry {
    /// `snapshot` at `date`, with its images read from `directory`.
    init(snapshot: WidgetSnapshot, at date: Date, directory: URL?) {
        self.date = date
        self.snapshot = snapshot
        self.playback = snapshot.playback(at: date)
        if let directory, let url = WidgetFiles.coverURL(for: snapshot, in: directory), let image = Self.decode(url) {
            cover = .image(image)
        } else {
            cover = .none
        }
        let accent = snapshot.accent ?? Self.systemAccent
        accentOnDark = Color(AccentResolver.adjust(accent, on: .dark, ratio: AccentResolver.glyphContrast) ?? .white)
        accentOnLight = Color(
            AccentResolver.adjust(accent, on: .light(background: .white), ratio: AccentResolver.glyphContrast) ?? .black
        )
    }

    /// The gallery's entry: the demo song with its drawn cover.
    static func demo(at date: Date) -> HumEntry {
        var entry = HumEntry(snapshot: .demo(at: date), at: date, directory: nil)
        entry.cover = .demo
        return entry
    }

    /// The accent chosen in System Settings, Hum's default accent mode.
    static var systemAccent: PaletteColor {
        guard let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) else {
            return PaletteColor(red: 0, green: 0.48, blue: 1)
        }
        return PaletteColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }

    /// A cover, read at no more than the size the largest widget draws it.
    private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(source)
    }

    private static func thumbnail(_ source: CGImageSource) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 600,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }
}

/// Reads Hum's snapshot for every widget.
struct HumProvider: TimelineProvider {
    /// Where the snapshot is: the fixed widget folder (see `WidgetFiles`).
    var directory = WidgetFiles.directory

    func placeholder(in context: Context) -> HumEntry {
        .demo(at: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (HumEntry) -> Void) {
        completion(context.isPreview ? .demo(at: .now) : entries(at: .now)[0])
    }

    /// Hum asks for a reload whenever what the widgets show changes, so the
    /// timeline never refreshes itself.
    func getTimeline(in context: Context, completion: @escaping (Timeline<HumEntry>) -> Void) {
        completion(Timeline(entries: entries(at: .now), policy: .never))
    }

    /// The song as it reads now and, while it plays, as it will read once it
    /// should have ended: paused, because a running Hum would have written a
    /// newer snapshot by then (DESIGN.md §7.3). No snapshot is Nothing Playing.
    func entries(at date: Date) -> [HumEntry] {
        let snapshot = WidgetFiles.readSnapshot(in: directory) ?? .nothingPlaying
        var entries = [HumEntry(snapshot: snapshot, at: date, directory: directory)]
        if let end = snapshot.songEnd, end > date {
            entries.append(HumEntry(snapshot: snapshot, at: end, directory: directory))
        }
        return entries
    }
}
