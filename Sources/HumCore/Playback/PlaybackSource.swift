import Foundation

/// One place music can come from: Spotify.app, Music.app, or the demo source.
///
/// Sources are main-actor objects that push state through `onStateChange`. Any slow
/// work (Apple Events, decoding) happens off the main actor inside the source; the
/// store and the UI only ever see finished `SourceState` values.
///
/// A source must not launch its app or trigger a permission prompt on its own. Only
/// `perform(_:)` of a play command may launch the app, and only
/// `requestAutomationPermission()` or a user-initiated `perform(_:)` may cause the
/// macOS Automation prompt.
@MainActor
public protocol PlaybackSource: AnyObject {
    var id: SourceID { get }
    /// Shown in menus and messages, for example "Spotify".
    var displayName: String { get }
    /// The bundle identifier of the app this source drives, if it drives one.
    var appBundleIdentifier: String? { get }
    var state: SourceState { get }
    /// Called on the main actor whenever `state` changes. The store sets this.
    var onStateChange: (@MainActor (SourceState) -> Void)? { get set }

    /// Begin observing the app. Must be cheap and must not send Apple Events to an
    /// app whose Automation permission is undetermined.
    func start()
    /// Stop all observation, timers, and in-flight work.
    func stop()
    /// Ask for fresh state if the source can get it without side effects.
    func refresh()
    /// Carry out a user command. Throws `PlaybackError`.
    func perform(_ command: PlaybackCommand) async throws
    /// Ask macOS for Automation permission. May show the system prompt, so call it
    /// only in response to a user action.
    func requestAutomationPermission() async
    /// Image bytes for `track`'s artwork, if available.
    func artwork(for track: Track) async -> Data?
    /// A web link to `track` that anyone can open, for Copy Link.
    func shareLink(for track: Track) -> URL?
    /// A URL that opens `track` in the source's app, for Show in App.
    /// `nil` means bringing the app forward is the best the source can do.
    func revealURL(for track: Track) -> URL?

    /// Whether `playSong(_:)` can start songs by their IDs, for Play Now on
    /// Echo's and the History window's songs where no library serves the
    /// source.
    var canPlaySongs: Bool { get }
    /// Whether `playSong(_:)` can start this one. Play Now is hidden for a
    /// song it can't, such as one imported from another service.
    func canPlaySong(_ id: TrackID) -> Bool
    /// Starts the song with `id` in the source's app. Like any command, it
    /// may cause the Automation prompt, so call it only for a user action.
    /// Throws `PlaybackError`.
    func playSong(_ id: TrackID) async throws
    /// Learns the Automation permission again without prompting, for the
    /// Status page, which shows it (DESIGN.md §6.3). The user may have changed
    /// it in System Settings since the source last asked.
    func refreshAutomationPermission() async
}

extension PlaybackSource {
    public func shareLink(for track: Track) -> URL? { nil }
    public func revealURL(for track: Track) -> URL? { nil }
    public var canPlaySongs: Bool { false }
    public func canPlaySong(_ id: TrackID) -> Bool { canPlaySongs }
    public func playSong(_ id: TrackID) async throws { throw PlaybackError.unsupported(.play) }
    public func refreshAutomationPermission() async {}
}
