import Foundation

/// Listening history brought in from Spotify's account data download. Files
/// only: nothing here talks to Spotify.
///
/// Two shapes are read, recognized by their contents rather than their names:
///
/// - **Account data** (`StreamingHistory_music_0.json`, or `StreamingHistory0.json`
///   in older downloads): an array of `endTime` (UTC, to the minute),
///   `artistName`, `trackName`, and `msPlayed`.
/// - **Extended streaming history** (`Streaming_History_Audio_….json`, or
///   `endsong_0.json` in older downloads): an array with `ts` (UTC, when the
///   stream ended), `ms_played`, the track, artist, and album names, the track's
///   URI, and why it ended.
///
/// Only music is kept: podcast episodes, audiobooks, and video are left out, and
/// so is anything played in a private session. Account, device, and network
/// fields are never read.
public enum HistoryImport {
    /// Listens read from files, not yet compared with what's stored.
    public struct Batch: Equatable, Sendable {
        /// Each history file's listens, oldest first. Listens in one file are
        /// never duplicates of each other; two files can overlap.
        public var files: [[Listen]]
        /// Entries left out: not music, a private session, or too short to keep.
        public var skipped: Int

        public init(files: [[Listen]] = [], skipped: Int = 0) {
            self.files = files
            self.skipped = skipped
        }

        public var listens: [Listen] { files.flatMap(\.self) }
    }

    /// What an import did.
    public struct Summary: Equatable, Sendable {
        /// Listens added to history.
        public var added: Int
        /// Listens already in history, tracked by Hum or imported before.
        public var duplicates: Int
        /// Entries left out: not music, a private session, or too short to keep.
        public var skipped: Int
        public var files: Int

        public init(added: Int, duplicates: Int, skipped: Int, files: Int) {
            self.added = added
            self.duplicates = duplicates
            self.skipped = skipped
            self.files = files
        }

        /// "Imported 1,204 listens. 38 were already in your history."
        public var message: String {
            var parts = [added == 0 ? "Nothing new to import." : "Imported " + HistoryFormat.count(added, "listen") + "."]
            if duplicates > 0 {
                parts.append(duplicates == 1 ? "1 was already in your history." : "\(duplicates.formatted()) were already in your history.")
            }
            return parts.joined(separator: " ")
        }
    }

    public enum Failure: Error, Equatable, Sendable, CustomStringConvertible {
        /// Nothing chosen holds Spotify listening history.
        case noHistory
        /// A chosen file couldn't be read or isn't JSON.
        case unreadable(fileName: String)

        public var description: String {
            switch self {
            case .noHistory:
                "These files don’t contain Spotify listening history. Choose the JSON files or the folder from Spotify’s data download."
            case .unreadable(let name):
                "\(name) couldn’t be read."
            }
        }
    }

    // MARK: Reading

    /// Read every history file in `urls`, off the main actor. A folder is
    /// searched for the download's history files; a file is read whatever its
    /// name.
    @concurrent
    public static func read(_ urls: [URL]) async throws -> Batch {
        var contents: [Data] = []
        for file in try historyFiles(in: urls) {
            try Task.checkCancellation()
            guard let data = try? Data(contentsOf: file.url) else {
                throw Failure.unreadable(fileName: file.url.lastPathComponent)
            }
            if file.isExplicit, case .notHistory = parse(data) {
                throw Failure.unreadable(fileName: file.url.lastPathComponent)
            }
            contents.append(data)
        }
        guard let batch = batch(contents) else { throw Failure.noHistory }
        return batch
    }

    /// Read files' contents, or `nil` when none of them is history. Files that
    /// aren't history are passed over.
    static func batch(_ contents: [Data]) -> Batch? {
        var entries: [[Entry]] = []
        var skipped = 0
        for data in contents {
            guard case .history(let read, let left) = parse(data) else { continue }
            entries.append(read)
            skipped += left
        }
        guard !entries.isEmpty else { return nil }
        return Batch(files: listens(from: entries), skipped: skipped)
    }

    private struct HistoryFile {
        var url: URL
        /// Chosen directly rather than found in a folder.
        var isExplicit: Bool
    }

    private static func historyFiles(in urls: [URL]) throws -> [HistoryFile] {
        var files: [HistoryFile] = []
        for url in urls {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isFolder else {
                files.append(HistoryFile(url: url, isExplicit: true))
                continue
            }
            let found = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let item = found?.nextObject() as? URL {
                if isHistoryFileName(item.lastPathComponent) {
                    files.append(HistoryFile(url: item, isExplicit: false))
                }
            }
        }
        // Extended history first: it has the richer entries, so it's the one
        // kept when both describe the same listen.
        return files.sorted { lhs, rhs in
            let left = isExtendedFileName(lhs.url.lastPathComponent), right = isExtendedFileName(rhs.url.lastPathComponent)
            return left != right ? left : lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
        }
    }

    /// The download's music history files, by name. Podcast and video files
    /// are left alone.
    static func isHistoryFileName(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard lower.hasSuffix(".json") else { return false }
        if lower.contains("podcast") || lower.contains("video") { return false }
        return lower.hasPrefix("streaminghistory") || isExtendedFileName(name)
    }

    static func isExtendedFileName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("streaming_history_audio") || lower.hasPrefix("endsong")
    }

    // MARK: Parsing

    /// One entry from either shape, with only the fields Hum reads.
    private struct Record: Decodable {
        // Account data.
        var endTime: String?
        var artistName: String?
        var trackName: String?
        var msPlayed: Double?
        var episodeName: String?
        var podcastName: String?
        // Extended streaming history.
        var timestamp: String?
        var milliseconds: Double?
        var track: String?
        var albumArtist: String?
        var album: String?
        var trackURI: String?
        var episodeURI: String?
        var reasonEnd: String?
        var skipped: Bool?
        var isPrivate: Bool?

        enum CodingKeys: String, CodingKey {
            case endTime, artistName, trackName, msPlayed, episodeName, podcastName
            case timestamp = "ts"
            case milliseconds = "ms_played"
            case track = "master_metadata_track_name"
            case albumArtist = "master_metadata_album_artist_name"
            case album = "master_metadata_album_album_name"
            case trackURI = "spotify_track_uri"
            case episodeURI = "spotify_episode_uri"
            case reasonEnd = "reason_end"
            case skipped
            case isPrivate = "incognito_mode"
        }
    }

    /// A music entry, before its play is judged.
    struct Entry: Equatable, Sendable {
        var title: String
        var artist: String
        var album: String
        var trackID: String
        var endedAt: Date
        var listened: TimeInterval
        var reasonEnd: String?
        var skipped: Bool?
    }

    private enum Parsed {
        case history([Entry], skipped: Int)
        case notHistory
    }

    private static func parse(_ data: Data) -> Parsed {
        guard let records = try? JSONDecoder().decode([Record].self, from: data) else { return .notHistory }
        // An empty file from the download is still history, just none of it.
        guard records.isEmpty || records.contains(where: { $0.timestamp != nil || $0.endTime != nil }) else { return .notHistory }
        var entries: [Entry] = []
        var skipped = 0
        for record in records {
            if let entry = entry(record) {
                entries.append(entry)
            } else {
                skipped += 1
            }
        }
        return .history(entries, skipped: skipped)
    }

    private static func entry(_ record: Record) -> Entry? {
        if let timestamp = record.timestamp {
            guard record.isPrivate != true,
                  record.episodeURI == nil,
                  let title = clean(record.track),
                  let artist = clean(record.albumArtist),
                  let ended = extendedDate(timestamp),
                  let milliseconds = record.milliseconds
            else { return nil }
            return accepted(Entry(
                title: title,
                artist: artist,
                album: clean(record.album) ?? "",
                trackID: clean(record.trackURI) ?? "",
                endedAt: ended,
                listened: milliseconds / 1000,
                reasonEnd: record.reasonEnd,
                skipped: record.skipped
            ))
        }
        guard let endTime = record.endTime,
              record.episodeName == nil, record.podcastName == nil,
              let title = clean(record.trackName),
              let artist = clean(record.artistName),
              let ended = accountDate(endTime),
              let milliseconds = record.msPlayed
        else { return nil }
        return accepted(Entry(title: title, artist: artist, album: "", trackID: "", endedAt: ended, listened: milliseconds / 1000))
    }

    private static func accepted(_ entry: Entry) -> Entry? {
        PlayRules.shouldRecord(listened: entry.listened) ? entry : nil
    }

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// "2024-03-15T21:04:33Z".
    static func extendedDate(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }

    /// "2024-03-15 21:04", always UTC.
    static func accountDate(_ text: String) -> Date? {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == ":" || $0 == "T" }).compactMap { Int($0) }
        guard parts.count >= 5, (1 ... 12).contains(parts[1]), (1 ... 31).contains(parts[2]) else { return nil }
        let components = DateComponents(
            year: parts[0], month: parts[1], day: parts[2],
            hour: parts[3], minute: parts[4], second: parts.count > 5 ? parts[5] : 0
        )
        return utc.date(from: components)
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // MARK: Judging plays

    /// Turn each file's entries into listens. The download doesn't say how long
    /// each song is, so its length is taken from a listen that played it to the
    /// end, or else the longest listen of it in any file, and plays are counted
    /// by the same rules as tracked ones (`PlayRules`).
    static func listens(from files: [[Entry]]) -> [[Listen]] {
        var finished: [String: TimeInterval] = [:]
        var longest: [String: TimeInterval] = [:]
        for entry in files.joined() {
            let key = SongKey.make(artist: entry.artist, title: entry.title)
            longest[key] = max(longest[key] ?? 0, entry.listened)
            if entry.reasonEnd == "trackdone" {
                finished[key] = max(finished[key] ?? 0, entry.listened)
            }
        }
        func listen(_ entry: Entry) -> Listen {
            let key = SongKey.make(artist: entry.artist, title: entry.title)
            let length = finished[key] ?? longest[key]
            return Listen(
                trackID: TrackID(entry.trackID),
                songKey: key,
                title: entry.title,
                artist: entry.artist,
                album: entry.album,
                source: .spotifyApp,
                startedAt: entry.endedAt.addingTimeInterval(-entry.listened),
                endedAt: entry.endedAt,
                listened: entry.listened,
                duration: nil,
                ending: ending(entry, length: length),
                counts: entry.skipped != true && PlayRules.counts(listened: entry.listened, duration: length),
                origin: .imported
            )
        }
        return files.map { $0.map(listen).sorted { $0.startedAt < $1.startedAt } }
    }

    private static func ending(_ entry: Entry, length: TimeInterval?) -> ListenEnding {
        if entry.reasonEnd == "trackdone" { return .completed }
        if entry.skipped == true { return .skipped }
        if entry.reasonEnd == "fwdbtn", entry.listened < PlayRules.skipWindow { return .skipped }
        if entry.reasonEnd == nil, let length, length > 0, entry.listened >= length * PlayRules.completedShare {
            return .completed
        }
        return .partial
    }

    // MARK: Duplicates

    /// How far apart two listens can be and still be the same one: the account
    /// data's times are only to the minute, and a tracked listen's span includes
    /// pauses.
    static let matchTolerance: TimeInterval = 120

    /// The imported listens not already in `existing` or an earlier file, plus
    /// how many were. Each listen accounts for at most one other, so a song
    /// played twice in a row is kept twice.
    static func newListens(_ files: [[Listen]], existing: [Listen]) -> (new: [Listen], duplicates: Int) {
        var pool = DuplicatePool()
        for listen in existing {
            let probe = pool.probe(listen)
            pool.add(probe, file: -1)
        }
        var new: [Listen] = []
        var duplicates = 0
        for (file, listens) in files.enumerated() {
            for listen in listens {
                let probe = pool.probe(listen)
                if pool.claim(probe, file: file) {
                    duplicates += 1
                } else {
                    new.append(listen)
                    pool.add(probe, file: file)
                }
            }
        }
        return (new.sorted { $0.startedAt < $1.startedAt }, duplicates)
    }

    /// `newListens`, off the caller's actor, so a long import never holds up
    /// the history store while it compares.
    @concurrent
    static func matching(_ files: [[Listen]], existing: [Listen]) async -> (new: [Listen], duplicates: Int) {
        newListens(files, existing: existing)
    }

    /// Listens already kept, indexed by the ways a listen can be recognized.
    ///
    /// Each index keeps its listens in order of when they started, so a claim
    /// looks only at the listens near it in time, not at every listen of the
    /// song: a favorite played thousands of times costs no more than any other.
    private struct DuplicatePool {
        /// A listen with its title and artist normalized, once.
        struct Probe {
            var listen: Listen
            var title: String
            var artist: String
        }

        private struct Kept {
            var probe: Probe
            /// The file it came from; -1 for stored listens.
            var file: Int
            var isClaimed = false
        }

        private var kept: [Kept] = []
        private var bySong: [String: TimeIndex] = [:]
        private var byTrack: [String: TimeIndex] = [:]
        private var byTitle: [String: TimeIndex] = [:]
        /// Names already normalized: a history repeats the same few thousand.
        private var normalized: [String: String] = [:]

        mutating func probe(_ listen: Listen) -> Probe {
            Probe(listen: listen, title: normalize(listen.title), artist: normalize(listen.artist))
        }

        private mutating func normalize(_ text: String) -> String {
            if let known = normalized[text] { return known }
            let result = SongKey.normalize(text)
            normalized[text] = result
            return result
        }

        mutating func add(_ probe: Probe, file: Int) {
            let index = kept.count
            let listen = probe.listen
            kept.append(Kept(probe: probe, file: file))
            bySong[listen.songKey, default: TimeIndex()].insert(index, listen)
            if !listen.trackID.rawValue.isEmpty { byTrack[listen.trackID.rawValue, default: TimeIndex()].insert(index, listen) }
            byTitle[probe.title, default: TimeIndex()].insert(index, listen)
        }

        /// Mark the closest unclaimed match for the listen from another file as
        /// used. Returns whether there was one.
        ///
        /// A match is a listen of the same song, of the same track, or of the
        /// same title with a related artist (one side may name only the album's
        /// artist, the other every artist on the track), that overlaps it. The
        /// closest ends nearest it; between equally close ones, the same song
        /// wins over the same track, the same track over the same title, and
        /// then the one kept first.
        mutating func claim(_ probe: Probe, file: Int) -> Bool {
            let listen = probe.listen
            var best: (distance: TimeInterval, rank: Int, index: Int)?
            let indexes: [(TimeIndex?, rank: Int)] = [
                (bySong[listen.songKey], 0),
                (listen.trackID.rawValue.isEmpty ? nil : byTrack[listen.trackID.rawValue], 1),
                (byTitle[probe.title], 2),
            ]
            for case let (timeIndex?, rank) in indexes {
                for index in timeIndex.members(near: listen) {
                    let candidate = kept[index]
                    guard !candidate.isClaimed, candidate.file != file, overlaps(candidate.probe.listen, listen) else { continue }
                    if rank == 2 {
                        let other = candidate.probe.artist
                        guard other.contains(probe.artist) || probe.artist.contains(other) else { continue }
                    }
                    let distance = abs(candidate.probe.listen.endedAt.timeIntervalSince(listen.endedAt))
                    if let current = best, (current.distance, current.rank, current.index) <= (distance, rank, index) { continue }
                    best = (distance, rank, index)
                }
            }
            guard let best else { return false }
            kept[best.index].isClaimed = true
            return true
        }

        private func overlaps(_ stored: Listen, _ listen: Listen) -> Bool {
            stored.startedAt.addingTimeInterval(-matchTolerance) <= listen.endedAt
                && listen.startedAt <= stored.endedAt.addingTimeInterval(matchTolerance)
        }
    }

    /// Kept listens in order of when they started, with the longest span
    /// among them, so the ones that could overlap a listen are found by a
    /// binary search rather than a scan.
    private struct TimeIndex {
        private var starts: [Date] = []
        private var members: [Int] = []
        private var longest: TimeInterval = 0

        mutating func insert(_ member: Int, _ listen: Listen) {
            // After any that started at the same moment, so equal starts stay
            // in the order they were kept.
            let position = firstIndex(after: listen.startedAt)
            starts.insert(listen.startedAt, at: position)
            members.insert(member, at: position)
            longest = max(longest, listen.endedAt.timeIntervalSince(listen.startedAt))
        }

        /// Every member that could overlap `listen` within the match tolerance,
        /// and perhaps a few that don't: one that overlaps started no later
        /// than the listen's end plus the tolerance, and no earlier than its
        /// start less the tolerance and the longest span kept. A second of
        /// slack on each side keeps rounding from losing one.
        func members(near listen: Listen) -> ArraySlice<Int> {
            let low = firstIndex(atOrAfter: listen.startedAt.addingTimeInterval(-(matchTolerance + longest + 1)))
            let high = firstIndex(after: listen.endedAt.addingTimeInterval(matchTolerance + 1))
            return low < high ? members[low ..< high] : []
        }

        private func firstIndex(atOrAfter date: Date) -> Int {
            partition { $0 >= date }
        }

        private func firstIndex(after date: Date) -> Int {
            partition { $0 > date }
        }

        /// The first position whose start passes `test`; starts are sorted, so
        /// every later one passes too.
        private func partition(_ test: (Date) -> Bool) -> Int {
            var low = 0, high = starts.count
            while low < high {
                let middle = (low + high) / 2
                if test(starts[middle]) { high = middle } else { low = middle + 1 }
            }
            return low
        }
    }
}

// MARK: - Store

extension HistoryStore {
    /// Add imported listens that aren't already stored, in one transaction.
    /// Importing never moves when Hum started tracking.
    ///
    /// The comparison with what's stored runs off the store, so recording and
    /// the History pages carry on meanwhile. If listens change while it runs,
    /// it compares again; the last try runs on the store, where nothing can
    /// change underneath it.
    public func importListens(_ batch: HistoryImport.Batch) async throws -> HistoryImport.Summary {
        let incoming = batch.listens
        guard let first = incoming.map(\.startedAt).min(), let last = incoming.map(\.endedAt).max() else {
            return HistoryImport.Summary(added: 0, duplicates: 0, skipped: batch.skipped, files: batch.files.count)
        }
        // A stored listen's span can start well before an imported one's: it
        // includes pauses.
        let margin = HistoryImport.matchTolerance + 86_400
        var tries = 0
        while true {
            tries += 1
            let revision = playsRevision
            let existing = try listens(from: first.addingTimeInterval(-margin), to: last.addingTimeInterval(margin))
            let (new, duplicates) = tries < 3
                ? await HistoryImport.matching(batch.files, existing: existing)
                : HistoryImport.newListens(batch.files, existing: existing)
            guard playsRevision == revision else { continue }
            try insertImported(new)
            // The import reached the write-ahead log in one go; fold it into
            // the file now rather than leave the log that size until the next
            // write.
            checkpoint()
            return HistoryImport.Summary(added: new.count, duplicates: duplicates, skipped: batch.skipped, files: batch.files.count)
        }
    }
}
