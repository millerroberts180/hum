import Foundation
import HumCore

/// Spotify.app, described for `ScriptedAppSource`.
///
/// Spotify's dictionary has no favorite command, so Save is absent and the UI
/// hides it. Its repeat is only on or off: repeat one is Hum's
/// (`.repeatOneByRestart`), so this is only ever asked for off or all.
public enum SpotifyApp: ScriptableMusicApp {
    public static let sourceID = SourceID.spotifyApp
    public static let displayName = "Spotify"
    public static let bundleIdentifier = "com.spotify.client"
    public static let playbackNotification = Notification.Name("com.spotify.client.PlaybackStateChanged")

    public static let capabilities: SourceCapabilities = [
        .playPause, .skipNext, .skipPrevious, .seek, .volume, .shuffle, .repeatAll, .repeatOne, .repeatOneByRestart,
        .artwork, .launch, .shareLink, .reveal,
    ]

    /// `{state, volume, shuffling, repeating}` or, with a track,
    /// `{state, volume, shuffling, repeating, id, name, artist, album, duration ms, position s, artwork url}`.
    public static let stateScript = ScriptTemplate.guarded(bundleIdentifier, """
        set ps to (player state as string)
        set vol to sound volume
        set shf to shuffling
        set rpt to repeating
        try
        \tset t to current track
        \tset tid to id of t
        \tset nm to name of t
        \tset ar to artist of t
        \tset al to album of t
        \tset dur to duration of t
        \tset pos to player position
        \tset art to ""
        \ttry
        \t\tset art to artwork url of t
        \tend try
        \treturn {ps, vol, shf, rpt, tid, nm, ar, al, dur, pos, art}
        on error
        \treturn {ps, vol, shf, rpt}
        end try
        """)

    public static let artwork = ArtworkStrategy.remoteURL(
        script: ScriptTemplate.guarded(bundleIdentifier, "return artwork url of current track")
    )

    public static func commandScript(for command: PlaybackCommand) -> String? {
        let body: String
        switch command {
        case .play: body = "play"
        case .pause: body = "pause"
        case .togglePlayPause: body = "playpause"
        case .next: body = "next track"
        case .previous: body = "previous track"
        case .seek(let position): body = "set player position to \(ScriptFormat.seconds(position))"
        case .setVolume(let volume): body = "set sound volume to \(ScriptFormat.percent(volume))"
        case .setShuffle(let enabled): body = "set shuffling to \(enabled)"
        // Repeat one is Hum's: the store sends repeat all and starts the song over.
        case .setRepeat(.one), .setFavorite, .beginScan, .endScan: return nil
        case .setRepeat(let mode): body = "set repeating to \(mode == .all)"
        }
        return ScriptTemplate.guarded(bundleIdentifier, body)
    }

    // MARK: Parsing

    public static func parseNotification(_ userInfo: [AnyHashable: Any], at date: Date) -> PlaybackSnapshot {
        let status = PlaybackStatus(playerState: NotificationFields.string(userInfo["Player State"])) ?? .stopped
        var track: Track?
        if let trackID = NotificationFields.nonEmpty(userInfo["Track ID"]) {
            track = Track(
                id: TrackID(trackID),
                title: NotificationFields.string(userInfo["Name"]) ?? "",
                artist: NotificationFields.string(userInfo["Artist"]) ?? "",
                album: NotificationFields.string(userInfo["Album"]) ?? "",
                duration: NotificationFields.double(userInfo["Duration"]).flatMap(seconds(fromDuration:))
            )
        }
        return PlaybackSnapshot(
            track: track,
            status: track == nil ? .stopped : status,
            position: NotificationFields.double(userInfo["Playback Position"]).map { max(0, $0) },
            timestamp: date
        )
    }

    public static func parseState(_ value: ScriptValue, at date: Date) -> PlaybackSnapshot? {
        guard let fields = value.list, fields.count >= 4 else { return nil }
        var snapshot = PlaybackSnapshot(
            status: PlaybackStatus(playerState: fields[0].string) ?? .stopped,
            timestamp: date,
            volume: fields[1].double.map { min(1, max(0, $0 / 100)) },
            shuffle: fields[2].bool,
            repeatMode: fields[3].bool.map { $0 ? .all : .off }
        )
        if fields.count >= 11, let trackID = fields[4].string, !trackID.isEmpty {
            snapshot.track = Track(
                id: TrackID(trackID),
                title: fields[5].string ?? "",
                artist: fields[6].string ?? "",
                album: fields[7].string ?? "",
                duration: fields[8].double.flatMap(seconds(fromDuration:)),
                artworkURL: fields[10].string.flatMap { $0.isEmpty ? nil : URL(string: $0) }
            )
            snapshot.position = fields[9].double.map { max(0, $0) }
        } else {
            snapshot.status = .stopped
        }
        return snapshot
    }

    /// Spotify reports durations in milliseconds. Values under 1000 can't be a real
    /// millisecond duration, so they're taken as seconds (older versions did that).
    static func seconds(fromDuration value: Double) -> TimeInterval? {
        guard value.isFinite, value > 0 else { return nil }
        return value < 1000 ? value : value / 1000
    }

    // MARK: Links

    /// Spotify identifies tracks as `spotify:track:<id>`; the public link for one
    /// is `https://open.spotify.com/track/<id>`.
    public static func shareLink(for track: Track) -> URL? {
        let parts = track.id.rawValue.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify", parts[1] == "track",
              parts[2].allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return URL(string: "https://open.spotify.com/track/\(parts[2])")
    }

    /// The track's own `spotify:` URI opens it in the app.
    public static func revealURL(for track: Track) -> URL? {
        shareLink(for: track) == nil ? nil : URL(string: track.id.rawValue)
    }

    // MARK: Playing one song

    public static let canPlaySongs = true

    /// `play track "spotify:track:<id>"`, for Play Now on Echo's and the History
    /// window's songs: Spotify's app plays one song it's given, and nothing
    /// more (DESIGN.md §1.3). `nil` for anything but a Spotify song's URI,
    /// which never reaches a script.
    public static func playScript(forTrack id: TrackID) -> String? {
        guard isTrackURI(id.rawValue) else { return nil }
        return ScriptTemplate.guarded(bundleIdentifier, timeout: 5, "play track \(MusicLibraryScripts.literal(id.rawValue))")
    }

    /// Exactly `spotify:track:` and a 22-character base-62 ID, as Spotify's app
    /// reports songs and its data download names them.
    static func isTrackURI(_ uri: String) -> Bool {
        let prefix = "spotify:track:"
        guard uri.hasPrefix(prefix) else { return false }
        let id = uri.utf8.dropFirst(prefix.utf8.count)
        return id.count == 22 && id.allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
        }
    }
}

public typealias SpotifyAppSource = ScriptedAppSource<SpotifyApp>
