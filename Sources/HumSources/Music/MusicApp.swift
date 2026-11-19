import Foundation
import HumCore

/// Music.app, described for `ScriptedAppSource`.
public enum MusicApp: ScriptableMusicApp {
    public static let sourceID = SourceID.musicApp
    public static let displayName = "Music"
    public static let bundleIdentifier = "com.apple.Music"
    public static let playbackNotification = Notification.Name("com.apple.Music.playerInfo")

    public static let capabilities: SourceCapabilities = [
        .playPause, .skipNext, .skipPrevious, .seek, .volume, .shuffle, .repeatAll, .repeatOne,
        .favorite, .artwork, .launch, .scan, .reveal,
    ]

    /// `{state, volume, shuffle, repeat}` or, with a track,
    /// `{state, volume, shuffle, repeat, persistent id, name, artist, album, duration s, position s, favorited,
    /// playlist name, playlist persistent id, playlist class}`.
    public static let stateScript = ScriptTemplate.guarded(bundleIdentifier, """
        set ps to (player state as string)
        set vol to sound volume
        set shf to shuffle enabled
        set rpt to (song repeat as string)
        try
        \tset t to current track
        \tset tid to persistent ID of t
        \tset nm to name of t
        \tset ar to artist of t
        \tset al to album of t
        \tset dur to missing value
        \ttry
        \t\tset dur to duration of t
        \tend try
        \tset pos to player position
        \tset fav to missing value
        \ttry
        \t\tset fav to favorited of t
        \tend try
        \tset cpn to ""
        \tset cpi to ""
        \tset cpc to ""
        \ttry
        \t\tset cp to current playlist
        \t\tset cpn to name of cp
        \t\tset cpi to persistent ID of cp
        \t\tset cpc to ((class of cp) as string)
        \tend try
        \treturn {ps, vol, shf, rpt, tid, nm, ar, al, dur, pos, fav, cpn, cpi, cpc}
        on error
        \treturn {ps, vol, shf, rpt}
        end try
        """)

    public static let artwork = ArtworkStrategy.rawData(
        script: ScriptTemplate.guarded(bundleIdentifier, """
            if (count of artworks of current track) is 0 then return missing value
            return raw data of artwork 1 of current track
            """)
    )

    public static func commandScript(for command: PlaybackCommand) -> String? {
        let body: String
        switch command {
        case .play: body = "play"
        case .pause: body = "pause"
        case .togglePlayPause: body = "playpause"
        case .next: body = "next track"
        // Restarts the track if it's a few seconds in, like the Previous button.
        case .previous: body = "back track"
        case .seek(let position): body = "set player position to \(ScriptFormat.seconds(position))"
        case .setVolume(let volume): body = "set sound volume to \(ScriptFormat.percent(volume))"
        case .setShuffle(let enabled): body = "set shuffle enabled to \(enabled)"
        case .setRepeat(let mode): body = "set song repeat to \(mode.rawValue)"
        case .setFavorite(let favorite): body = "set favorited of current track to \(favorite)"
        case .beginScan(let forward): body = forward ? "fast forward" : "rewind"
        case .endScan: body = "resume"
        }
        return ScriptTemplate.guarded(bundleIdentifier, body)
    }

    // MARK: Parsing

    public static func parseNotification(_ userInfo: [AnyHashable: Any], at date: Date) -> PlaybackSnapshot {
        let status = PlaybackStatus(playerState: NotificationFields.string(userInfo["Player State"])) ?? .stopped
        let persistentID = NotificationFields.int64(userInfo["PersistentID"] ?? userInfo["Persistent ID"])
        let title = NotificationFields.string(userInfo["Name"])
        var track: Track?
        if status != .stopped, persistentID != nil || title != nil {
            let id = persistentID.map(hexIdentifier(_:)) ?? "name:" + (title ?? "")
            track = Track(
                id: TrackID(id),
                title: title ?? "",
                artist: NotificationFields.string(userInfo["Artist"]) ?? "",
                album: NotificationFields.string(userInfo["Album"]) ?? "",
                duration: NotificationFields.double(userInfo["Total Time"]).flatMap { $0 > 0 ? $0 / 1000 : nil }
            )
        }
        return PlaybackSnapshot(track: track, status: track == nil ? .stopped : status, timestamp: date)
    }

    public static func parseState(_ value: ScriptValue, at date: Date) -> PlaybackSnapshot? {
        guard let fields = value.list, fields.count >= 4 else { return nil }
        var snapshot = PlaybackSnapshot(
            status: PlaybackStatus(playerState: fields[0].string) ?? .stopped,
            timestamp: date,
            volume: fields[1].double.map { min(1, max(0, $0 / 100)) },
            shuffle: fields[2].bool,
            repeatMode: fields[3].string.flatMap { RepeatMode(rawValue: $0.lowercased()) }
        )
        if fields.count >= 11, let persistentID = fields[4].string, !persistentID.isEmpty {
            snapshot.track = Track(
                id: TrackID(persistentID.uppercased()),
                title: fields[5].string ?? "",
                artist: fields[6].string ?? "",
                album: fields[7].string ?? "",
                duration: fields[8].nonNull?.double.flatMap { $0 > 0 ? $0 : nil }
            )
            snapshot.position = fields[9].double.map { max(0, $0) }
            snapshot.isFavorite = fields[10].nonNull?.bool
            if fields.count >= 14 {
                snapshot.context = MusicLibraryParsing.context(
                    name: fields[11].string,
                    identifier: fields[12].string,
                    className: fields[13].string
                )
            }
        } else {
            snapshot.status = .stopped
        }
        return snapshot
    }

    /// The notification carries the persistent ID as a signed 64-bit number; scripts
    /// return it as 16 hex digits. This makes the two match.
    static func hexIdentifier(_ value: Int64) -> String {
        let hex = String(UInt64(bitPattern: value), radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }
}

public typealias MusicAppSource = ScriptedAppSource<MusicApp>
