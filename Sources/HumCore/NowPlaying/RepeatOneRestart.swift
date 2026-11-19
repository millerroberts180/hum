import Foundation

/// Hum's repeat one, for an app whose own repeat is only on or off, as
/// Spotify's is (DESIGN.md §5.2, §13.24).
///
/// The app's repeat stays on. About `lead` before the song ends, the store
/// re-reads the player and, if the same song is still playing, sets its
/// position back to 0, so it starts over without a gap. If the song ends anyway
/// (a missed timing, a new position the app took too late, the Mac asleep),
/// the store goes back to it with Previous Track, once. Pure state and
/// decisions; `NowPlayingStore` runs the timers and sends the commands.
public struct RepeatOneRestart: Equatable, Sendable {
    /// How long before the end the song starts over. Spotify takes a new
    /// position a moment after it answers, so the restart leaves it time to
    /// land before the song ends (§13.34).
    public static let lead: TimeInterval = 2
    /// A song that gave way to another this close to its end ran out rather
    /// than being skipped. A re-read this close to the end restarts it.
    public static let endWindow: TimeInterval = 3
    /// After a restart, how long past the song's old end a change away from it
    /// still means the new position never took.
    public static let landingSlack: TimeInterval = 1.5
    /// How long the re-read may take. With no answer by then, the restart
    /// goes ahead on the store's clock.
    public static let rereadTimeout: TimeInterval = 0.5
    /// A track change this soon after Hum sent Next or Previous was Hum's own.
    public static let skipWindow: TimeInterval = 3

    /// When the store re-reads the player for `track`.
    public struct Plan: Equatable, Sendable {
        public var track: TrackID
        public var at: Date

        /// Whether `other` is this plan, give or take the rounding of the
        /// clock's arithmetic.
        func isSame(as other: Plan?) -> Bool {
            guard let other else { return false }
            return track == other.track && abs(at.timeIntervalSince(other.at)) < 0.01
        }
    }

    /// The re-read on its way: the song it's for, and when it was asked for.
    struct Reread: Equatable, Sendable {
        var track: TrackID
        var requestedAt: Date
    }

    /// A restart sent: the song, and until when the app may still play on
    /// past it to the next song.
    struct Restarted: Equatable, Sendable {
        var track: TrackID
        var until: Date
    }

    /// The source whose song repeats, while One is on.
    public private(set) var sourceID: SourceID?
    /// When Hum last sent Next or Previous.
    var lastSkipAt: Date?
    var reread: Reread?
    var restarted: Restarted?

    public init() {}

    /// Whether One is on for `source`.
    public func isOn(for source: SourceID?) -> Bool {
        source != nil && sourceID == source
    }

    /// The user chose `mode` for `source`. Returns the mode to send the app:
    /// One keeps (or sets) the app's repeat on.
    public mutating func choose(_ mode: RepeatMode, for source: SourceID) -> RepeatMode {
        reread = nil
        restarted = nil
        sourceID = mode == .one ? source : nil
        return mode == .one ? .all : mode
    }

    /// One ends: the app's repeat went off, the app quit, or another source took over.
    public mutating func turnOff() {
        sourceID = nil
        reread = nil
        restarted = nil
    }

    /// The store is sending `track` back to 0 with `remaining` left. Until a
    /// moment past its old end, the song giving way to another means the new
    /// position came too late.
    mutating func willRestart(_ track: TrackID, remaining: TimeInterval?, at date: Date) {
        restarted = Restarted(track: track, until: date.addingTimeInterval((remaining ?? Self.lead) + Self.landingSlack))
    }

    /// The song changed: whatever was on its way for the old one is moot.
    mutating func songChanged() {
        reread = nil
        restarted = nil
    }

    /// When to re-read the player: `lead` before the end, while the song plays.
    /// `nil` once that moment has passed (a seek past it), and for a song of
    /// unknown length.
    public func plan(track: TrackID?, isPlaying: Bool, clock: PositionClock, at date: Date) -> Plan? {
        guard sourceID != nil, isPlaying, let track, let remaining = clock.remaining(at: date),
              remaining > Self.lead else { return nil }
        return Plan(track: track, at: date.addingTimeInterval(remaining - Self.lead))
    }

    /// Whether a fresh `report` says `track` is still playing and near its
    /// end, so it should start over now.
    public static func shouldRestart(_ track: TrackID, after report: PlaybackSnapshot, at date: Date) -> Bool {
        guard report.track?.id == track, report.status.isPlaying,
              let duration = report.track?.duration, duration > 0,
              let position = report.position else { return false }
        let now = position + max(0, date.timeIntervalSince(report.timestamp))
        return duration - now <= endWindow
    }

    /// Whether `previous` ran out on its own and gave way to `next`, so the
    /// store should go back to it: it had at most `endWindow` left, or Hum had
    /// just sent it back to 0 and the app played on regardless, and Hum sent
    /// no skip just before. `remaining` is the store's clock, which a restart
    /// has already set back to the start.
    public func ranOut(previous: TrackID?, remaining: TimeInterval?, next: TrackID?, source: SourceID, at date: Date) -> Bool {
        guard isOn(for: source), let previous, let next, previous != next else { return false }
        if let lastSkipAt, date.timeIntervalSince(lastSkipAt) <= Self.skipWindow { return false }
        if let restarted, restarted.track == previous, date <= restarted.until { return true }
        guard let remaining else { return false }
        return remaining <= Self.endWindow
    }
}
