import Foundation

/// About six months of made-up listening for demos and screenshots.
///
/// Deterministic: the same catalog, end date, calendar, and seed always produce
/// the same listens. Patterns are deliberate so every insight has something to
/// say: weekday evening and weekend afternoon habits, a long-term favorite, a
/// song on repeat this week, one rediscovered after months away, one that's
/// often skipped lately, one that went quiet, and a single that's new this week.
/// Only ever written to the demo database.
public enum DemoHistory {
    public static let defaultSeed: UInt64 = 0x6875_6D5F_6465_6D6F
    public static let days = 182

    /// More songs on the demo albums, plus two singles, so the history has some
    /// variety. `catalog` is the demo playlist.
    public static func extraTracks(for catalog: [Track]) -> [Track] {
        let byAlbum = Dictionary(catalog.map { ($0.album, $0) }, uniquingKeysWith: { first, _ in first })
        func on(_ album: String, _ title: String, _ duration: TimeInterval) -> Track? {
            guard let anchor = byAlbum[album] else { return nil }
            return Track(id: TrackID("demo:" + slug(title)), title: title, artist: anchor.artist, album: album, duration: duration)
        }
        let companions: [Track?] = [
            on("Coastline Hours", "Salt on the Antenna", 201),
            on("Coastline Hours", "Harbor Static", 236),
            on("Coastline Hours", "Undertow Letters", 188),
            on("Small Fires", "Kindling Count", 174),
            on("Small Fires", "Ember Theory", 209),
            on("Altitude Notes", "Thin Air Waltz", 228),
            on("Altitude Notes", "Cairn Song", 195),
            on("Altitude Notes", "Treeline", 251),
            on("Conservatory", "Fern Radio", 183),
            on("Conservatory", "Condensation", 217),
            on("After Close", "Last Call Modulation", 262),
            on("After Close", "Receipt Paper Blues", 204),
            on("Ash & Paper", "Carbon Copy", 166),
            on("Ash & Paper", "Embossed", 190),
        ]
        let singles = [
            Track(id: TrackID("demo:northbound"), title: "Northbound", artist: "The Lindqvist Set", album: "Northbound", duration: 222),
            Track(id: TrackID("demo:paper-boats"), title: "Paper Boats", artist: "Wren Okoye", album: "Paper Boats", duration: 179),
        ]
        return companions.compactMap { $0 } + singles
    }

    /// Generate the listens, oldest first, ending a few minutes before `end` with
    /// a session still warm. Without `namesContexts` no listen says what it
    /// played from, as with Spotify's app; the listens are otherwise the same.
    public static func generate(
        catalog: [Track],
        source: SourceID = .demo,
        endingAt end: Date,
        calendar: Calendar,
        seed: UInt64 = defaultSeed,
        namesContexts: Bool = true
    ) -> [Listen] {
        let tracks = catalog + extraTracks(for: catalog)
        guard !tracks.isEmpty else { return [] }
        var random = SplitMix64(seed: seed)
        var listens: [Listen] = []
        let today = calendar.startOfDay(for: end)
        var roles = Roles(catalog: catalog, tracks: tracks)
        // The new single arrives this week, so the week's receipt has a discovery.
        if let weekStart = calendar.dateInterval(of: .weekOfYear, for: end)?.start {
            roles.newSingleDays = min(4, calendar.dateComponents([.day], from: weekStart, to: today).day ?? 4)
        }

        for dayIndex in 0..<days {
            let daysAgo = days - 1 - dayIndex
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            for plan in sessionPlans(isWeekend: isWeekend, weekday: weekday, random: &random) {
                guard var start = calendar.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: day) else { continue }
                if plan.hour < 5 { start = start.addingTimeInterval(86_400) }
                // Leave the last hour for the warm session below.
                guard start < end.addingTimeInterval(-2 * 3_600) else { continue }
                listens += session(
                    start: start,
                    count: plan.count,
                    context: plan.context,
                    daysAgo: daysAgo,
                    timeOfDay: TimeOfDay(hour: plan.hour),
                    roles: roles,
                    tracks: tracks,
                    source: source,
                    until: end.addingTimeInterval(-2 * 3_600),
                    random: &random
                )
            }
        }

        // A session that ended a few minutes ago, so Echo has a trail to show.
        // The singles stay out of it, so the trail, the first thing the demo
        // shows, is the playlist's songs.
        let warmCount = 6
        var warm = session(
            start: end.addingTimeInterval(-28 * 60),
            count: warmCount,
            context: PlaybackContext(kind: .playlist, name: "Late Shift"),
            daysAgo: 0,
            timeOfDay: TimeOfDay(hour: calendar.component(.hour, from: end)),
            roles: roles,
            tracks: tracks,
            leavingOut: [roles.newSingle, roles.lateSingle],
            source: source,
            until: end.addingTimeInterval(-90),
            random: &random
        )
        // Keep the newest listen off the track the demo starts on, so the live
        // listen reads as a new one.
        if let first = catalog.first, warm.last?.trackID == first.id { warm.removeLast() }
        listens += warm
        if !namesContexts {
            for index in listens.indices { listens[index].context = nil }
        }
        return listens.sorted { $0.startedAt < $1.startedAt }
    }

    // MARK: Shape

    private struct Plan {
        var hour: Int
        var minute: Int
        var count: Int
        var context: PlaybackContext?
    }

    private static func sessionPlans(isWeekend: Bool, weekday: Int, random: inout SplitMix64) -> [Plan] {
        var plans: [Plan] = []
        if isWeekend {
            if random.chance(0.65) {
                plans.append(Plan(hour: 13 + random.int(0..<3), minute: random.int(0..<60), count: 6 + random.int(0..<8), context: PlaybackContext(kind: .playlist, name: "Weekend Slow")))
            }
            if weekday == 7, random.chance(0.5) {
                plans.append(Plan(hour: 23, minute: random.int(0..<40), count: 5 + random.int(0..<6), context: PlaybackContext(kind: .playlist, name: "Late Shift")))
            }
        } else {
            if random.chance(0.45) {
                plans.append(Plan(hour: 8, minute: random.int(0..<40), count: 3 + random.int(0..<4), context: PlaybackContext(kind: .playlist, name: "Morning Commute")))
            }
            if random.chance(0.75) {
                let context: PlaybackContext? = random.chance(0.75) ? PlaybackContext(kind: .playlist, name: "Late Shift") : nil
                plans.append(Plan(hour: 19 + random.int(0..<3), minute: random.int(0..<60), count: 4 + random.int(0..<9), context: context))
            }
            if weekday == 6, random.chance(0.6) {
                plans.append(Plan(hour: 23, minute: 15 + random.int(0..<30), count: 4 + random.int(0..<5), context: PlaybackContext(kind: .playlist, name: "Late Shift")))
            }
        }
        return plans
    }

    /// Which catalog songs play which part.
    private struct Roles {
        var favorite: TrackID?
        var onRepeat: TrackID?
        var lateNight: TrackID?
        var rediscovered: TrackID?
        var wentQuiet: TrackID?
        var skippedLately: TrackID?
        var newSingle = TrackID("demo:northbound")
        var newSingleDays = 4
        var lateSingle = TrackID("demo:paper-boats")

        init(catalog: [Track], tracks: [Track]) {
            func id(_ index: Int) -> TrackID? { catalog.indices.contains(index) ? catalog[index].id : nil }
            favorite = id(0)
            onRepeat = id(1)
            skippedLately = id(2)
            rediscovered = id(3)
            wentQuiet = id(4)
            lateNight = id(5)
        }
    }

    private static func weight(of track: Track, daysAgo: Int, timeOfDay: TimeOfDay, roles: Roles) -> Double {
        let id = track.id
        switch id {
        case roles.favorite: return 3
        case roles.onRepeat: return daysAgo <= 2 ? 14 : 1.2
        case roles.skippedLately: return 2
        case roles.rediscovered:
            if daysAgo >= 140 { return 4 }
            return daysAgo <= 5 ? 3 : 0
        case roles.wentQuiet: return (90...150).contains(daysAgo) ? 5 : 0
        case roles.lateNight: return timeOfDay == .night ? 6 : 0.4
        case roles.newSingle: return daysAgo <= roles.newSingleDays ? 4 : 0
        case roles.lateSingle: return daysAgo <= 80 ? 1 : 0
        default: return 1
        }
    }

    private static func session(
        start: Date,
        count: Int,
        context: PlaybackContext?,
        daysAgo: Int,
        timeOfDay: TimeOfDay,
        roles: Roles,
        tracks: [Track],
        leavingOut: Set<TrackID> = [],
        source: SourceID,
        until limit: Date,
        random: inout SplitMix64
    ) -> [Listen] {
        let weights = tracks.map { leavingOut.contains($0.id) ? 0 : weight(of: $0, daysAgo: daysAgo, timeOfDay: timeOfDay, roles: roles) }
        var listens: [Listen] = []
        var cursor = start
        var previous: TrackID?
        for _ in 0..<count {
            guard var index = random.pick(weights: weights) else { break }
            if tracks[index].id == previous, let again = random.pick(weights: weights) { index = again }
            let track = tracks[index]
            previous = track.id
            let duration = track.duration ?? 200
            let skipChance = track.id == roles.skippedLately && daysAgo <= 30 ? 0.6 : 0.07
            let listened: TimeInterval
            if random.chance(skipChance) {
                listened = 4 + Double(random.int(0..<22))
            } else if random.chance(0.06) {
                listened = duration * (0.4 + random.unit() * 0.3)
            } else {
                listened = duration
            }
            // Now and then a pause that doesn't count.
            let paused: TimeInterval = random.chance(0.05) ? Double(60 + random.int(0..<240)) : 0
            let ended = cursor.addingTimeInterval(listened + paused)
            guard ended < limit else { break }
            let exit: PlayRules.Exit = .changedTrack
            let ending = PlayRules.ending(listened: listened, duration: duration, exit: exit, wasPlaying: true)
            listens.append(Listen(
                trackID: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                source: source,
                context: random.chance(0.85) ? context : nil,
                startedAt: cursor,
                endedAt: ended,
                listened: listened,
                duration: duration,
                ending: ending,
                counts: PlayRules.counts(listened: listened, duration: duration)
            ))
            cursor = ended.addingTimeInterval(Double(random.int(0..<4)))
        }
        return listens
    }

    private static func slug(_ title: String) -> String {
        SongKey.normalize(title).replacingOccurrences(of: " ", with: "-")
    }
}

/// A small, fast, seedable generator. Deterministic across runs and platforms.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `0..<1`.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }

    mutating func int(_ range: Range<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    /// An index chosen in proportion to `weights`.
    mutating func pick(weights: [Double]) -> Int? {
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }
        var target = unit() * total
        for (index, weight) in weights.enumerated() where weight > 0 {
            target -= weight
            if target < 0 { return index }
        }
        return weights.lastIndex { $0 > 0 }
    }
}
