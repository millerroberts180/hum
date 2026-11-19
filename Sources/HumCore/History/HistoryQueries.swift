import Foundation

/// A filter for the History list.
public struct HistoryQuery: Equatable, Sendable {
    /// Matches title, artist, or album.
    public var search = ""
    public var artist: String?
    public var album: String?
    /// A playlist name, matched against listens whose context was that playlist.
    public var playlist: String?
    public var timeOfDay: TimeOfDay?
    public var limit = 400

    public init(search: String = "", artist: String? = nil, album: String? = nil, playlist: String? = nil, timeOfDay: TimeOfDay? = nil, limit: Int = 400) {
        self.search = search
        self.artist = artist
        self.album = album
        self.playlist = playlist
        self.timeOfDay = timeOfDay
        self.limit = limit
    }

    /// Whether a search or any filter narrows the listens.
    public var isFiltered: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || artist != nil || album != nil || playlist != nil || timeOfDay != nil
    }
}

/// A part of the day, for patterns, chapter names, and filters.
public enum TimeOfDay: String, CaseIterable, Codable, Sendable {
    case morning, afternoon, evening, night

    public init(hour: Int) {
        switch hour {
        case 5..<12: self = .morning
        case 12..<17: self = .afternoon
        case 17..<22: self = .evening
        default: self = .night
        }
    }

    public var title: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .night: "Late Night"
        }
    }

    /// The hours it covers, for explanations.
    public var span: String {
        switch self {
        case .morning: "5 AM and noon"
        case .afternoon: "noon and 5 PM"
        case .evening: "5 PM and 10 PM"
        case .night: "10 PM and 5 AM"
        }
    }

    /// As it reads inside a sentence: "late at night", "in the morning".
    public var phrase: String {
        switch self {
        case .morning: "in the morning"
        case .afternoon: "in the afternoon"
        case .evening: "in the evening"
        case .night: "late at night"
        }
    }

    /// As it reads before "listening": "afternoon", "late-night".
    public var adjective: String {
        switch self {
        case .morning: "morning"
        case .afternoon: "afternoon"
        case .evening: "evening"
        case .night: "late-night"
        }
    }
}

/// What the Top section ranks.
public enum TopDimension: String, CaseIterable, Sendable {
    case songs, artists, albums

    public var title: String {
        switch self {
        case .songs: "Songs"
        case .artists: "Artists"
        case .albums: "Albums"
        }
    }
}

/// One ranked row in Top or Rediscover.
public struct TopEntry: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var plays: Int
    public var listened: TimeInterval
    /// A listen to borrow artwork from.
    public var sampleTrackID: TrackID
    public var sampleSource: SourceID
    public var firstPlayed: Date?
    public var lastPlayed: Date?

    public init(
        id: String,
        title: String,
        subtitle: String,
        plays: Int,
        listened: TimeInterval,
        sampleTrackID: TrackID,
        sampleSource: SourceID,
        firstPlayed: Date? = nil,
        lastPlayed: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.plays = plays
        self.listened = listened
        self.sampleTrackID = sampleTrackID
        self.sampleSource = sampleSource
        self.firstPlayed = firstPlayed
        self.lastPlayed = lastPlayed
    }

    public var artworkKey: String { sampleSource.rawValue + ":" + sampleTrackID.rawValue }
}

/// Listening on one calendar day.
public struct DayTotal: Hashable, Sendable {
    /// The start of the day.
    public var day: Date
    public var listened: TimeInterval
    public var plays: Int

    public init(day: Date, listened: TimeInterval, plays: Int) {
        self.day = day
        self.listened = listened
        self.plays = plays
    }
}

/// Where a range of listens came from, by how Hum got them.
public struct HistoryProvenance: Hashable, Sendable {
    /// Sources Hum watched while it ran.
    public var tracked: Set<SourceID> = []
    /// Sources whose history was imported from a file.
    public var imported: Set<SourceID> = []
    /// Sources whose own history service reported the listens.
    public var service: Set<SourceID> = []

    public init(tracked: Set<SourceID> = [], imported: Set<SourceID> = [], service: Set<SourceID> = []) {
        self.tracked = tracked
        self.imported = imported
        self.service = service
    }

    /// Where `listens` came from: only their own sources, for a caption that
    /// covers just those listens.
    public init(_ listens: some Sequence<Listen>) {
        self.init()
        for listen in listens {
            insert(listen.source, origin: listen.origin)
        }
    }

    public var isEmpty: Bool { tracked.isEmpty && imported.isEmpty && service.isEmpty }

    mutating func insert(_ source: SourceID, origin: ListenOrigin) {
        switch origin {
        case .tracked: tracked.insert(source)
        case .imported: imported.insert(source)
        case .service: service.insert(source)
        }
    }
}

/// The imported part of history.
public struct ImportedHistory: Hashable, Sendable {
    public var count: Int
    /// When the earliest imported listen started.
    public var since: Date
    /// When the latest one ended.
    public var until: Date

    public init(count: Int, since: Date, until: Date) {
        self.count = count
        self.since = since
        self.until = until
    }
}
