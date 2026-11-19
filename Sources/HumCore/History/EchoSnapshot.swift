import Foundation

/// What Echo shows for the current moment: insights about the song playing and
/// the session it belongs to.
public struct EchoSnapshot: Equatable, Sendable {
    /// The song the insights are about.
    public var songKey: String?
    public var songInsights: [Insight]
    public var session: ListeningSession?
    public var sessionInsights: [Insight]
    public var trackedSince: Date?
    /// Total listens stored, for empty states.
    public var listenCount: Int
    /// The imported part of history, if any was imported.
    public var imported: ImportedHistory?

    public init(
        songKey: String? = nil,
        songInsights: [Insight] = [],
        session: ListeningSession? = nil,
        sessionInsights: [Insight] = [],
        trackedSince: Date? = nil,
        listenCount: Int = 0,
        imported: ImportedHistory? = nil
    ) {
        self.songKey = songKey
        self.songInsights = songInsights
        self.session = session
        self.sessionInsights = sessionInsights
        self.trackedSince = trackedSince
        self.listenCount = listenCount
        self.imported = imported
    }

    public static let empty = EchoSnapshot()
}

extension HistoryStore {
    /// Compute Echo for `track` (the one playing, if any) at `now`.
    public func echo(track: Track?, inProgress: Listen?, now: Date, calendar: Calendar) throws -> EchoSnapshot {
        let trackedSince = try trackedSince()
        let imported = try importedHistory()
        var snapshot = EchoSnapshot(trackedSince: trackedSince, listenCount: try count(), imported: imported)

        if let track {
            let key = SongKey.make(artist: track.artist, title: track.title)
            let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let input = InsightEngine.SongInput(
                track: track,
                listens: try listens(songKey: key),
                monthPlayCounts: try playCounts(from: monthStart, to: now.addingTimeInterval(1)),
                trackedSince: trackedSince,
                importedRange: imported.map { $0.since ... max($0.since, $0.until) },
                now: now
            )
            snapshot.songKey = key
            snapshot.songInsights = InsightEngine.songInsights(input, calendar: calendar)
        }

        // A session can't reach back further than a day without a 30-minute gap
        // in practice; a day of listens is plenty to find where it began.
        // Sessions are listening Hum saw, so imported listens (which may have
        // been on another device) stay out of them.
        let recent = try listens(from: now.addingTimeInterval(-86_400), to: nil).filter { $0.origin == .tracked }
        var keys = Set(recent.map(\.songKey))
        if let inProgress { keys.insert(inProgress.songKey) }
        let firstHeard = try self.firstHeard(songKeys: keys, origin: .tracked)
        if let session = SessionBuilder.current(recent, inProgress: inProgress, firstHeard: firstHeard, now: now, calendar: calendar) {
            let prior = try spans(origin: .tracked).filter { $0.endedAt < session.start }
            snapshot.session = session
            snapshot.sessionInsights = InsightEngine.sessionInsights(
                session,
                priorLengths: SessionBuilder.sessionLengths(prior),
                trackedSince: trackedSince,
                now: now,
                calendar: calendar
            )
        }
        return snapshot
    }
}
