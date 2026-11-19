import Foundation

/// What Hum's widgets show (DESIGN.md §7.3): the song and its play state. Hum
/// writes it next to the cover in `WidgetFiles.directory`; the widget extension
/// reads it.
///
/// It holds nothing else: no history, no account, no paths, and no source. The
/// widgets never name the music app (§10), so the snapshot doesn't know it.
///
/// Decoding is lenient, field by field, so a file from an older or newer Hum
/// loses only what it got wrong. A file from before 2026-11-08 may also hold
/// Echo's insight and session trail, for the retired Data and Session widgets
/// (§13.19); they're ignored, and a retired style reads as no style.
public struct WidgetSnapshot: Equatable, Sendable {
    /// Bumped when a field changes meaning. Readers still decode what they can.
    public static let currentVersion = 1

    public var version: Int
    /// The song, or `nil` for Nothing Playing.
    public var song: Song?
    public var isPlaying: Bool
    /// Seconds into the song at `positionDate`.
    public var position: TimeInterval
    /// When `position` was true. Progress runs forward from here while playing.
    public var positionDate: Date
    /// `nil` when the source doesn't report it.
    public var shuffle: Bool?
    public var repeatMode: RepeatMode?
    /// The transport the source supports right now. `show` is always allowed.
    public var actions: Set<HumURLAction>
    /// The player style when the snapshot was written, for nothing but a default.
    public var style: PlayerStyleID?
    /// The accent for active toggles, or `nil` for the system accent (DESIGN.md
    /// §3.5.3, the default mode).
    public var accent: PaletteColor?
    /// The cover's colors, for the backdrop and tinted text.
    public var palette: ArtworkPalette?
    /// The cover's file name in the snapshot's folder, if there is a cover.
    public var coverFile: String?

    public struct Song: Codable, Equatable, Sendable {
        public var title: String
        public var artist: String
        public var album: String
        /// Seconds, when the source knows it.
        public var duration: TimeInterval?

        public init(title: String, artist: String, album: String = "", duration: TimeInterval? = nil) {
            self.title = title
            self.artist = artist
            self.album = album
            self.duration = duration
        }
    }

    public init(
        song: Song?,
        isPlaying: Bool = false,
        position: TimeInterval = 0,
        positionDate: Date = .now,
        shuffle: Bool? = nil,
        repeatMode: RepeatMode? = nil,
        actions: Set<HumURLAction> = [.show],
        style: PlayerStyleID? = nil,
        accent: PaletteColor? = nil,
        palette: ArtworkPalette? = nil,
        coverFile: String? = nil
    ) {
        self.version = Self.currentVersion
        self.song = song
        self.isPlaying = isPlaying
        self.position = max(0, position)
        self.positionDate = positionDate
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.actions = actions.union([.show])
        self.style = style
        self.accent = accent
        self.palette = palette
        self.coverFile = coverFile
    }

    /// Nothing Playing.
    public static let nothingPlaying = WidgetSnapshot(song: nil, positionDate: .distantPast)
}

// MARK: - Playback at a moment

extension WidgetSnapshot {
    /// When the song ends, if it's playing and its length is known.
    public var songEnd: Date? {
        guard isPlaying, let duration = song?.duration, duration > 0 else { return nil }
        return positionDate.addingTimeInterval(max(0, duration - position))
    }

    /// Whether the snapshot is past its song's end at `date`: Hum would have
    /// written a newer one if it were still following playback, so the widget
    /// shows the song paused (DESIGN.md §7.3).
    public func isStale(at date: Date) -> Bool {
        guard let songEnd else { return false }
        return date >= songEnd
    }

    /// What a widget draws at `date`.
    public func playback(at date: Date) -> WidgetPlayback {
        guard song != nil else { return .nothingPlaying }
        let duration = song?.duration.flatMap { $0 > 0 ? $0 : nil }
        if isPlaying, !isStale(at: date) {
            let elapsed = position + max(0, date.timeIntervalSince(positionDate))
            let start = date.addingTimeInterval(-elapsed)
            return .playing(start: start, end: duration.map { start.addingTimeInterval($0) }, duration: duration)
        }
        var shown = position
        if isPlaying { shown += max(0, date.timeIntervalSince(positionDate)) }
        if let duration { shown = min(shown, duration) }
        return .paused(position: max(0, shown), duration: duration)
    }

    /// Whether the transport offers `action`.
    public func supports(_ action: HumURLAction) -> Bool {
        actions.contains(action)
    }
}

/// The play state a widget draws.
public enum WidgetPlayback: Equatable, Sendable {
    case nothingPlaying
    /// Progress runs on its own from `start` (the moment the song would have been
    /// at 0:00) to `end`, with `ProgressView(timerInterval:)`.
    case playing(start: Date, end: Date?, duration: TimeInterval?)
    /// Progress stands still at `position`.
    case paused(position: TimeInterval, duration: TimeInterval?)

    public var isPlaying: Bool {
        if case .playing = self { true } else { false }
    }
}

// MARK: - Codable

extension HumURLAction: Codable {}

extension WidgetSnapshot.Song {
    enum CodingKeys: String, CodingKey {
        case title, artist, album, duration
    }

    /// A title and an artist make a song; the album and length may be missing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decode(String.self, forKey: .artist)
        album = container.lenient(.album, default: "")
        duration = container.lenient(.duration, default: nil)
    }
}

extension WidgetSnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case version, song, isPlaying, position, positionDate, shuffle, repeatMode, actions
        case style, accent, palette, coverFile
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WidgetSnapshot.nothingPlaying
        version = container.lenient(.version, default: 0)
        song = container.lenient(.song, default: nil)
        isPlaying = container.lenient(.isPlaying, default: false)
        position = max(0, container.lenient(.position, default: 0))
        positionDate = container.lenient(.positionDate, default: defaults.positionDate)
        shuffle = container.lenient(.shuffle, default: nil)
        repeatMode = container.lenient(.repeatMode, default: nil)
        // Actions a newer Hum knows and this one doesn't are skipped, not fatal.
        let names: [String] = container.lenient(.actions, default: [])
        actions = Set(names.compactMap(HumURLAction.init(rawValue:))).union([.show])
        style = container.lenient(.style, default: nil)
        accent = container.lenient(.accent, default: nil)
        palette = container.lenient(.palette, default: nil)
        coverFile = container.lenient(.coverFile, default: nil)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(song, forKey: .song)
        try container.encode(isPlaying, forKey: .isPlaying)
        try container.encode(position, forKey: .position)
        try container.encode(positionDate, forKey: .positionDate)
        try container.encodeIfPresent(shuffle, forKey: .shuffle)
        try container.encodeIfPresent(repeatMode, forKey: .repeatMode)
        try container.encode(actions.map(\.rawValue).sorted(), forKey: .actions)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encodeIfPresent(accent, forKey: .accent)
        try container.encodeIfPresent(palette, forKey: .palette)
        try container.encodeIfPresent(coverFile, forKey: .coverFile)
    }
}
