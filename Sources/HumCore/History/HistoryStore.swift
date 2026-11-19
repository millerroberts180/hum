import Foundation

/// Listening history on disk: one SQLite file, written and read only from this
/// actor so no disk work runs on the main thread.
public actor HistoryStore {
    private let database: SQLiteDatabase
    /// Where the file lives, or `nil` for an in-memory store.
    public nonisolated let fileURL: URL?
    /// Bumped by every change to the stored listens, so work that leaves the
    /// actor partway (an import's comparison) can tell whether they changed.
    private(set) var playsRevision = 0

    /// Open (and migrate) the file at `url`; `nil` keeps everything in memory.
    public init(url: URL?) throws {
        try self.init(url: url, migrations: HistorySchema.migrations)
    }

    init(url: URL?, migrations: [HistoryMigration]) throws {
        database = try SQLiteDatabase(url: url)
        fileURL = url
        if url != nil {
            try database.execute("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")
        }
        // Removed listens are overwritten, not just unlinked, so the file
        // never holds what someone took out of their history.
        try database.execute("PRAGMA secure_delete = ON")
        try HistorySchema.migrate(database, migrations: migrations)
        if try HistorySchema.version(of: database) >= 1 {
            try HistorySchema.addIndexes(database)
        }
    }

    /// Open the file at `url`, or fall back to memory if it can't be used (for
    /// example, a newer Hum wrote it). The file itself is never altered then.
    public static func openOrFallback(url: URL?) -> (store: HistoryStore, problem: String?) {
        do {
            return (try HistoryStore(url: url), nil)
        } catch {
            // An in-memory database always opens.
            return (try! HistoryStore(url: nil), String(describing: error))
        }
    }

    // MARK: Writing

    /// Store a listen and return it with its id.
    @discardableResult
    public func insert(_ listen: Listen) throws -> Listen {
        try noteTrackingStarted(at: listen.startedAt)
        try database.run(Self.insertSQL, Self.values(for: listen, includingID: false))
        playsRevision += 1
        var stored = listen
        stored.id = database.lastInsertedRowID
        return stored
    }

    /// Store a listen unless the same one (track, source, and start) is already
    /// stored. Recording uses this, so a listen written while quitting and again
    /// from its checkpoint on the next launch is kept once.
    @discardableResult
    public func insertIfNew(_ listen: Listen) throws -> Listen? {
        let existing = try database.query(
            "SELECT COUNT(*) FROM plays WHERE started_at = ? AND track_id = ? AND source = ?",
            [.real(listen.startedAt.timeIntervalSince1970), .text(listen.trackID.rawValue), .text(listen.source.rawValue)]
        ) { $0.integer(0) }
        guard existing.first == 0 else { return nil }
        return try insert(listen)
    }

    /// Finish and store the listen a previous run checkpointed, if there is one.
    @discardableResult
    public func recoverPending() throws -> Listen? {
        guard let pending = try takePending(),
              let listen = pending.finished(exit: .stopped, wasPlaying: false)
        else { return nil }
        return try insertIfNew(listen)
    }

    /// Store many listens in one transaction (demo seeding).
    public func insert(contentsOf listens: [Listen]) throws {
        guard let earliest = listens.map(\.startedAt).min() else { return }
        try database.transaction {
            try noteTrackingStarted(at: earliest)
            for listen in listens {
                try database.run(Self.insertSQL, Self.values(for: listen, includingID: false))
            }
        }
        playsRevision += 1
    }

    /// Store imported listens in one transaction. Unlike the other inserts, this
    /// leaves when Hum started tracking alone.
    func insertImported(_ listens: [Listen]) throws {
        guard !listens.isEmpty else { return }
        try database.transaction {
            for var listen in listens {
                listen.origin = .imported
                try database.run(Self.insertSQL, Self.values(for: listen, includingID: false))
            }
        }
        playsRevision += 1
    }

    /// Remove every imported listen; tracked ones stay. Returns how many went.
    @discardableResult
    public func removeImported() throws -> Int {
        let count = try database.transaction {
            let count = try database.query("SELECT COUNT(*) FROM plays WHERE origin = 'imported'") { Int($0.integer(0)) }.first ?? 0
            try database.run("DELETE FROM plays WHERE origin = 'imported'")
            return count
        }
        playsRevision += 1
        compact()
        return count
    }

    /// Remove listens and return what was removed, for undo.
    public func delete(ids: [Int64]) throws -> [Listen] {
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let values = ids.map(SQLiteDatabase.Value.integer)
        return try database.transaction {
            let removed = try database.query(
                "SELECT \(Self.columns) FROM plays WHERE id IN (\(placeholders)) ORDER BY started_at",
                values,
                map: Self.listen(from:)
            )
            try database.run("DELETE FROM plays WHERE id IN (\(placeholders))", values)
            playsRevision += 1
            return removed
        }
    }

    /// Put removed listens back under their old ids.
    public func restore(_ listens: [Listen]) throws {
        guard !listens.isEmpty else { return }
        try database.transaction {
            for listen in listens {
                try database.run(Self.restoreSQL, Self.values(for: listen, includingID: true))
            }
        }
        playsRevision += 1
    }

    /// Remove every listen and start tracking over.
    public func eraseAll() throws {
        try database.transaction {
            try database.run("DELETE FROM plays")
            try database.run("DELETE FROM pending_listen")
            try database.run("DELETE FROM meta WHERE key = 'tracked_since'")
        }
        playsRevision += 1
        compact()
    }

    /// Fold the write-ahead log into the file and empty it, so a big write
    /// doesn't leave the log at its size.
    func checkpoint() {
        guard fileURL != nil else { return }
        // Best effort: a reader holding the log open only delays this.
        try? database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    /// After a bulk removal, give the space back and empty the log, so the
    /// file shrinks and holds no copy of what went. Best effort too: the
    /// removal is done, and secure delete has already overwritten it.
    private func compact() {
        guard fileURL != nil else { return }
        try? database.execute("VACUUM")
        checkpoint()
    }

    public func savePending(_ pending: PendingListen?) throws {
        guard let pending else {
            try database.run("DELETE FROM pending_listen")
            return
        }
        let body = String(decoding: try JSONEncoder().encode(pending), as: UTF8.self)
        try database.run("INSERT OR REPLACE INTO pending_listen (id, body) VALUES (1, ?)", [.text(body)])
    }

    /// The checkpointed listen from a previous run, removed as it's read.
    public func takePending() throws -> PendingListen? {
        let bodies = try database.query("SELECT body FROM pending_listen WHERE id = 1") { $0.text(0) }
        try database.run("DELETE FROM pending_listen")
        guard let body = bodies.first else { return nil }
        return try? JSONDecoder().decode(PendingListen.self, from: Data(body.utf8))
    }

    /// When Hum started tracking, kept even if the earliest listens are removed.
    public func trackedSince() throws -> Date? {
        try database.query("SELECT value FROM meta WHERE key = 'tracked_since'") { $0.text(0) }
            .first
            .flatMap(Double.init)
            .map(Date.init(timeIntervalSince1970:))
    }

    private func noteTrackingStarted(at date: Date) throws {
        let current = try trackedSince()
        guard current == nil || date < current! else { return }
        try database.run(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('tracked_since', ?)",
            [.text(String(date.timeIntervalSince1970))]
        )
    }

    // MARK: Reading

    public func count() throws -> Int {
        try database.query("SELECT COUNT(*) FROM plays") { Int($0.integer(0)) }.first ?? 0
    }

    /// Every listen of one song, oldest first.
    public func listens(songKey: String) throws -> [Listen] {
        try database.query(
            "SELECT \(Self.columns) FROM plays WHERE song_key = ? ORDER BY started_at",
            [.text(songKey)],
            map: Self.listen(from:)
        )
    }

    /// Listens that started in `[start, end)`, oldest first.
    public func listens(from start: Date? = nil, to end: Date? = nil) throws -> [Listen] {
        try database.query(
            "SELECT \(Self.columns) FROM plays WHERE started_at >= ? AND started_at < ? ORDER BY started_at",
            [.real(start?.timeIntervalSince1970 ?? -.greatestFiniteMagnitude), .real(end?.timeIntervalSince1970 ?? .greatestFiniteMagnitude)],
            map: Self.listen(from:)
        )
    }

    /// Listens matching `query`, newest first.
    public func listens(matching query: HistoryQuery, calendar: Calendar) throws -> [Listen] {
        let (filter, values) = Self.filter(for: query)
        // Time of day depends on the user's calendar, so it's filtered here.
        let limit = query.timeOfDay == nil ? "LIMIT \(max(1, query.limit))" : ""
        var rows = try database.query(
            "SELECT \(Self.columns) FROM plays \(filter) ORDER BY started_at DESC \(limit)",
            values,
            map: Self.listen(from:)
        )
        if let timeOfDay = query.timeOfDay {
            rows = Array(rows.lazy.filter { TimeOfDay(hour: calendar.component(.hour, from: $0.startedAt)) == timeOfDay }.prefix(query.limit))
        }
        return rows
    }

    /// How many listens a query matches, ignoring its limit.
    public func count(matching query: HistoryQuery, calendar: Calendar) throws -> Int {
        let (filter, values) = Self.filter(for: query)
        guard let timeOfDay = query.timeOfDay else {
            return try database.query("SELECT COUNT(*) FROM plays \(filter)", values) { Int($0.integer(0)) }.first ?? 0
        }
        return try database.query("SELECT started_at FROM plays \(filter)", values) {
            Date(timeIntervalSince1970: $0.real(0))
        }
        .count { TimeOfDay(hour: calendar.component(.hour, from: $0)) == timeOfDay }
    }

    /// The `WHERE` clause for a query's search and filters, apart from time of day.
    private static func filter(for query: HistoryQuery) -> (String, [SQLiteDatabase.Value]) {
        var clauses: [String] = []
        var values: [SQLiteDatabase.Value] = []
        let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            clauses.append("(title LIKE ? ESCAPE '\\' OR artist LIKE ? ESCAPE '\\' OR album LIKE ? ESCAPE '\\')")
            let pattern = "%" + Self.escapeLike(search) + "%"
            values += [.text(pattern), .text(pattern), .text(pattern)]
        }
        if let artist = query.artist {
            clauses.append("artist = ?")
            values.append(.text(artist))
        }
        if let album = query.album {
            clauses.append("album = ?")
            values.append(.text(album))
        }
        if let playlist = query.playlist {
            clauses.append("context_kind = 'playlist' AND context_name = ?")
            values.append(.text(playlist))
        }
        return (clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND "), values)
    }

    /// The names the History filters offer.
    public func filterOptions() throws -> (artists: [String], albums: [String], playlists: [String]) {
        let artists = try database.query("SELECT DISTINCT artist FROM plays WHERE artist != '' ORDER BY artist COLLATE NOCASE") { $0.text(0) }
        let albums = try database.query("SELECT DISTINCT album FROM plays WHERE album != '' ORDER BY album COLLATE NOCASE") { $0.text(0) }
        let playlists = try database.query(
            "SELECT DISTINCT context_name FROM plays WHERE context_kind = 'playlist' AND TRIM(context_name) != '' ORDER BY context_name COLLATE NOCASE"
        ) { $0.text(0) }
        return (artists, albums, playlists)
    }

    /// The most-played songs, artists, or albums in `[start, end)`.
    /// Only plays that count are ranked.
    public func top(_ dimension: TopDimension, from start: Date?, to end: Date?, limit: Int = 25) throws -> [TopEntry] {
        let group: String
        let extra: String
        switch dimension {
        case .songs:
            group = "song_key"
            extra = ""
        case .artists:
            group = "artist"
            extra = ""
        case .albums:
            group = "artist, album"
            extra = "AND album != ''"
        }
        let sql = """
            SELECT song_key, title, artist, album, track_id, source,
                   COUNT(*), SUM(listened), MIN(started_at), MAX(started_at)
            FROM plays
            WHERE counts = 1 AND started_at >= ? AND started_at < ? \(extra)
            GROUP BY \(group)
            ORDER BY COUNT(*) DESC, SUM(listened) DESC, MAX(started_at) DESC
            LIMIT ?
            """
        let values: [SQLiteDatabase.Value] = [
            .real(start?.timeIntervalSince1970 ?? -.greatestFiniteMagnitude),
            .real(end?.timeIntervalSince1970 ?? .greatestFiniteMagnitude),
            .integer(Int64(limit)),
        ]
        return try database.query(sql, values) { row in
            let songKey = row.text(0), title = row.text(1), artist = row.text(2), album = row.text(3)
            let (id, name, subtitle): (String, String, String) = switch dimension {
            case .songs: (songKey, title, artist)
            case .artists: (artist, artist, "")
            case .albums: (artist + "\u{1F}" + album, album, artist)
            }
            return TopEntry(
                id: id,
                title: name,
                subtitle: subtitle,
                plays: Int(row.integer(6)),
                listened: row.real(7),
                sampleTrackID: TrackID(row.text(4)),
                sampleSource: SourceID(row.text(5)),
                firstPlayed: Date(timeIntervalSince1970: row.real(8)),
                lastPlayed: Date(timeIntervalSince1970: row.real(9))
            )
        }
    }

    /// Songs played at least `minimumPlays` times whose last play was before
    /// `quietSince`, most-played first.
    public func rediscover(quietSince: Date, minimumPlays: Int = 3, limit: Int = 30) throws -> [TopEntry] {
        let sql = """
            SELECT song_key, title, artist, track_id, source,
                   COUNT(*), SUM(listened), MIN(started_at), MAX(started_at)
            FROM plays
            WHERE counts = 1
            GROUP BY song_key
            HAVING MAX(started_at) < ? AND COUNT(*) >= ?
            ORDER BY COUNT(*) DESC, MAX(started_at) DESC
            LIMIT ?
            """
        return try database.query(sql, [.real(quietSince.timeIntervalSince1970), .integer(Int64(minimumPlays)), .integer(Int64(limit))]) { row in
            TopEntry(
                id: row.text(0),
                title: row.text(1),
                subtitle: row.text(2),
                plays: Int(row.integer(5)),
                listened: row.real(6),
                sampleTrackID: TrackID(row.text(3)),
                sampleSource: SourceID(row.text(4)),
                firstPlayed: Date(timeIntervalSince1970: row.real(7)),
                lastPlayed: Date(timeIntervalSince1970: row.real(8))
            )
        }
    }

    /// Time listened per calendar day in `[start, end)`. Days with nothing are left out.
    public func dailyTotals(from start: Date, to end: Date, calendar: Calendar) throws -> [DayTotal] {
        let rows = try database.query(
            "SELECT started_at, listened, counts FROM plays WHERE started_at >= ? AND started_at < ?",
            [.real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)]
        ) { (Date(timeIntervalSince1970: $0.real(0)), $0.real(1), $0.integer(2) == 1) }
        var totals: [Date: DayTotal] = [:]
        for (started, listened, counts) in rows {
            let day = calendar.startOfDay(for: started)
            var total = totals[day] ?? DayTotal(day: day, listened: 0, plays: 0)
            total.listened += listened
            if counts { total.plays += 1 }
            totals[day] = total
        }
        return totals.values.sorted { $0.day < $1.day }
    }

    /// When each of `songKeys` was first heard, counting only listens of
    /// `origin` when one is given.
    public func firstHeard(songKeys: Set<String>, origin: ListenOrigin? = nil) throws -> [String: Date] {
        // One look per song down its own run of `plays_by_song`, which stops at
        // the first listen of `origin` instead of reading every one.
        let sql = origin == nil ? Self.firstHeardSQL : Self.firstHeardOfOriginSQL
        var first: [String: Date] = [:]
        for key in songKeys {
            let values: [SQLiteDatabase.Value] = [.text(key)] + (origin.map { [.text($0.rawValue)] } ?? [])
            if let started = try database.query(sql, values, map: { $0.real(0) }).first {
                first[key] = Date(timeIntervalSince1970: started)
            }
        }
        return first
    }

    static let firstHeardSQL = "SELECT started_at FROM plays WHERE song_key = ? ORDER BY started_at LIMIT 1"
    static let firstHeardOfOriginSQL = "SELECT started_at FROM plays WHERE song_key = ? AND origin = ? ORDER BY started_at LIMIT 1"

    /// Counted plays per song in `[start, end)`.
    public func playCounts(from start: Date, to end: Date) throws -> [String: Int] {
        let rows = try database.query(
            "SELECT song_key, COUNT(*) FROM plays WHERE counts = 1 AND started_at >= ? AND started_at < ? GROUP BY song_key",
            [.real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)]
        ) { ($0.text(0), Int($0.integer(1))) }
        return Dictionary(rows, uniquingKeysWith: +)
    }

    /// The sources listens in `[start, end)` came from, so every number can say
    /// where it was counted.
    public func sources(from start: Date? = nil, to end: Date? = nil) throws -> Set<SourceID> {
        let rows = try database.query(
            "SELECT DISTINCT source FROM plays WHERE started_at >= ? AND started_at < ?",
            [.real(start?.timeIntervalSince1970 ?? -.greatestFiniteMagnitude), .real(end?.timeIntervalSince1970 ?? .greatestFiniteMagnitude)]
        ) { SourceID($0.text(0)) }
        return Set(rows)
    }

    /// Where listens in `[start, end)` came from: the sources Hum tracked and the
    /// ones imported, so every number can say how it was counted.
    public func provenance(from start: Date? = nil, to end: Date? = nil) throws -> HistoryProvenance {
        let rows = try database.query(
            "SELECT DISTINCT source, origin FROM plays WHERE started_at >= ? AND started_at < ?",
            [.real(start?.timeIntervalSince1970 ?? -.greatestFiniteMagnitude), .real(end?.timeIntervalSince1970 ?? .greatestFiniteMagnitude)]
        ) { (SourceID($0.text(0)), ListenOrigin(rawValue: $0.text(1)) ?? .tracked) }
        var provenance = HistoryProvenance()
        for (source, origin) in rows {
            provenance.insert(source, origin: origin)
        }
        return provenance
    }

    /// How many listens were imported and the span they cover, or `nil` when
    /// none were.
    public func importedHistory() throws -> ImportedHistory? {
        try database.query(Self.importedHistorySQL) { row in
            row.integer(0) == 0 ? nil : ImportedHistory(
                count: Int(row.integer(0)),
                since: Date(timeIntervalSince1970: row.real(1)),
                until: Date(timeIntervalSince1970: row.real(2))
            )
        }
        .first ?? nil
    }

    // `plays_imported` covers it, so it never reads the tracked listens.
    static let importedHistorySQL = "SELECT COUNT(*), MIN(started_at), MAX(ended_at) FROM plays WHERE origin = 'imported'"

    /// How SQLite would run `sql`, one line per step, for checking which index
    /// a lookup uses.
    func queryPlan(_ sql: String, _ values: [SQLiteDatabase.Value] = []) throws -> [String] {
        try database.query("EXPLAIN QUERY PLAN " + sql, values) { $0.text(3) }
    }

    /// Every listen's span, oldest first, for session statistics. Only listens
    /// of `origin` when one is given.
    public func spans(origin: ListenOrigin? = nil) throws -> [ListenSpan] {
        let filter = origin == nil ? "" : "WHERE origin = ?"
        return try database.query(
            "SELECT started_at, ended_at, listened FROM plays \(filter) ORDER BY started_at",
            origin.map { [.text($0.rawValue)] } ?? []
        ) {
            ListenSpan(
                startedAt: Date(timeIntervalSince1970: $0.real(0)),
                endedAt: Date(timeIntervalSince1970: $0.real(1)),
                listened: $0.real(2)
            )
        }
    }

    // MARK: Export

    /// Write every listen as JSON or CSV. Returns how many were written.
    @discardableResult
    public func export(_ format: HistoryExportFormat, to url: URL) throws -> Int {
        let all = try listens()
        let data = switch format {
        case .json: try HistoryExport.json(all)
        case .csv: Data(HistoryExport.csv(all).utf8)
        }
        try data.write(to: url, options: .atomic)
        return all.count
    }

    // MARK: Rows

    private static let columns = """
        id, track_id, song_key, title, artist, album, source, context_kind, context_name, context_id,
        started_at, ended_at, listened, duration, ending, counts, origin
        """

    private static let insertSQL = """
        INSERT INTO plays (track_id, song_key, title, artist, album, source, context_kind, context_name, context_id,
                           started_at, ended_at, listened, duration, ending, counts, origin)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

    private static let restoreSQL = """
        INSERT OR REPLACE INTO plays (id, track_id, song_key, title, artist, album, source, context_kind, context_name, context_id,
                                      started_at, ended_at, listened, duration, ending, counts, origin)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

    private static func values(for listen: Listen, includingID: Bool) -> [SQLiteDatabase.Value] {
        var values: [SQLiteDatabase.Value] = includingID ? [.integer(listen.id)] : []
        values += [
            .text(listen.trackID.rawValue),
            .text(listen.songKey),
            .text(listen.title),
            .text(listen.artist),
            .text(listen.album),
            .text(listen.source.rawValue),
            .optional(listen.context?.kind.rawValue),
            .optional(listen.context?.name),
            .optional(listen.context?.identifier),
            .real(listen.startedAt.timeIntervalSince1970),
            .real(listen.endedAt.timeIntervalSince1970),
            .real(listen.listened),
            .optional(listen.duration),
            .text(listen.ending.rawValue),
            .integer(listen.counts ? 1 : 0),
            .text(listen.origin.rawValue),
        ]
        return values
    }

    private static func listen(from row: SQLiteDatabase.Cursor) -> Listen {
        let context = row.optionalText(7)
            .flatMap(PlaybackContext.Kind.init(rawValue:))
            .map { PlaybackContext(kind: $0, name: row.optionalText(8), identifier: row.optionalText(9)) }
        return Listen(
            id: row.integer(0),
            trackID: TrackID(row.text(1)),
            songKey: row.text(2),
            title: row.text(3),
            artist: row.text(4),
            album: row.text(5),
            source: SourceID(row.text(6)),
            context: context,
            startedAt: Date(timeIntervalSince1970: row.real(10)),
            endedAt: Date(timeIntervalSince1970: row.real(11)),
            listened: row.real(12),
            duration: row.optionalReal(13),
            ending: ListenEnding(rawValue: row.text(14)) ?? .partial,
            counts: row.integer(15) == 1,
            origin: ListenOrigin(rawValue: row.text(16)) ?? .tracked
        )
    }

    private static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}

/// When a listen started and ended, and how much was heard.
public struct ListenSpan: Hashable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    public var listened: TimeInterval

    public init(startedAt: Date, endedAt: Date, listened: TimeInterval) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.listened = listened
    }
}
