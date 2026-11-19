import Foundation
import HumCore

/// Everything app-specific about controlling a scriptable player.
///
/// A conforming type is pure description (scripts, notification parsing, state
/// parsing), with no state of its own. `ScriptedAppSource` supplies the behavior,
/// so Spotify and Music share one implementation of observation, permission,
/// polling, launching, and optimistic commands.
public protocol ScriptableMusicApp: Sendable {
    static var sourceID: SourceID { get }
    static var displayName: String { get }
    static var bundleIdentifier: String { get }
    /// Posted on the distributed notification center when playback changes.
    static var playbackNotification: Notification.Name { get }
    static var capabilities: SourceCapabilities { get }

    /// Returns the player's state as a list; see `parseState(_:at:)`.
    static var stateScript: String { get }
    static var artwork: ArtworkStrategy { get }
    /// The script that carries out `command`, or `nil` if the app can't.
    static func commandScript(for command: PlaybackCommand) -> String?

    /// Reads a playback notification. Fields the notification doesn't carry are `nil`.
    static func parseNotification(_ userInfo: [AnyHashable: Any], at date: Date) -> PlaybackSnapshot
    /// Reads the result of `stateScript`. Returns `nil` if the app wasn't running.
    static func parseState(_ value: ScriptValue, at date: Date) -> PlaybackSnapshot?

    /// A public web link to `track`, if the app's identifiers map to one.
    static func shareLink(for track: Track) -> URL?
    /// A URL that opens `track` in the app.
    static func revealURL(for track: Track) -> URL?
    /// Whether `playScript(forTrack:)` starts songs, so Play Now on Echo's
    /// and the History window's songs goes through the app. Only apps with no
    /// `LibraryProvider` of their own need it.
    static var canPlaySongs: Bool { get }
    /// The script that starts the song with `id`, or `nil` when the app can't
    /// start that one.
    static func playScript(forTrack id: TrackID) -> String?
}

extension ScriptableMusicApp {
    public static func shareLink(for track: Track) -> URL? { nil }
    public static func revealURL(for track: Track) -> URL? { nil }
    public static var canPlaySongs: Bool { false }
    public static func playScript(forTrack id: TrackID) -> String? { nil }
}
