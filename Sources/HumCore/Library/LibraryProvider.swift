import Foundation

/// Why a library request didn't work, in words the UI can show as they are.
public enum LibraryError: Error, Equatable, Sendable {
    /// The source can't do this at all, or can't right now. `capability` is turned
    /// off until the source says otherwise.
    case unavailable(LibraryUnavailable)
    /// A request failed, and repeating it won't help. The message says what
    /// to do instead.
    case failed(String)
    /// A request failed for a reason that may pass, such as a timeout, a lost
    /// connection, or a busy server. Try Again repeats it (DESIGN.md §4.6).
    case transient(String)
    /// The work was superseded.
    case cancelled

    public var message: String {
        switch self {
        case .unavailable(let reason): reason.message
        case .failed(let message), .transient(let message): message
        case .cancelled: ""
        }
    }
}

/// A plain explanation of why a section can't show anything, and the one action
/// that would fix it.
public struct LibraryUnavailable: Hashable, Sendable {
    public enum Fix: Hashable, Sendable {
        /// The macOS Automation prompt, for a source that needs Apple Events.
        case allowAutomation(app: String)
        /// System Settings → Privacy & Security → Automation, after a denial.
        case openAutomationSettings
        /// Start the app of the source named, even if the library follows
        /// another by the time it's chosen.
        case openApp(SourceID, name: String)
    }

    public var title: String
    public var message: String
    public var fix: Fix?

    public init(title: String, message: String, fix: Fix? = nil) {
        self.title = title
        self.message = message
        self.fix = fix
    }

    /// The fix's button title, in Title Case.
    public var fixTitle: String? {
        switch fix {
        case .allowAutomation: "Allow Access…"
        case .openAutomationSettings: "Open System Settings"
        case .openApp(_, let name): "Open \(name)"
        case nil: nil
        }
    }
}

/// What Play Now should start.
public enum PlayRequest: Hashable, Sendable {
    /// One song. Spotify's app plays only the song it's given; for the others
    /// the list it was chosen from, when there is one, follows it.
    case track(LibraryTrack, in: PlaybackContext?)
}

/// What Hum does for a source beyond Now's controls: Play Now on Echo's and
/// the History window's songs, Favorite on any song, and the devices it can
/// play on (DESIGN.md §1.3).
///
/// One provider serves one `PlaybackSource`. A provider declares what it
/// supports in `capabilities`, which may change at any time, and calls
/// `onChange` when it does. The UI hides controls for capabilities that are
/// missing, so a provider is only asked for what it declared.
///
/// Requests throw `LibraryError`. A provider that learns it can't do something
/// throws `.unavailable` and drops the capability, rather than failing the same
/// way again.
@MainActor
public protocol LibraryProvider: AnyObject {
    var sourceID: SourceID { get }
    /// The source's name, as the user knows it.
    var displayName: String { get }
    /// Whether every request goes through the source's app, so nothing works
    /// while it's closed or Automation access is missing.
    var requiresAppAccess: Bool { get }
    /// What the provider can do right now.
    var capabilities: SourceCapabilities { get }
    /// Set when nothing works until the user acts.
    var unavailable: LibraryUnavailable? { get }
    /// Called when `capabilities` or `unavailable` change.
    var onChange: (@MainActor () -> Void)? { get set }

    func play(_ request: PlayRequest) async throws(LibraryError)
    /// Why `request` can't play, in a sentence, or `nil` when it can. Play Now
    /// is hidden for a song with a reason (DESIGN.md §4.4).
    func playBlocker(for request: PlayRequest) -> String?
    func setSaved(_ saved: Bool, track: LibraryTrack) async throws(LibraryError)
    func isSaved(_ track: LibraryTrack) async -> Bool?

    func devices() async throws(LibraryError) -> [PlaybackDevice]
    func transfer(to device: PlaybackDevice) async throws(LibraryError)

    /// Image bytes for artwork without a URL.
    func artworkData(for artwork: LibraryArtwork) async -> Data?
}

extension LibraryProvider {
    public var requiresAppAccess: Bool { false }
    public var unavailable: LibraryUnavailable? { nil }

    public func play(_ request: PlayRequest) async throws(LibraryError) { throw Self.unsupported }
    public func playBlocker(for request: PlayRequest) -> String? { nil }
    public func setSaved(_ saved: Bool, track: LibraryTrack) async throws(LibraryError) { throw Self.unsupported }
    public func isSaved(_ track: LibraryTrack) async -> Bool? { nil }
    public func devices() async throws(LibraryError) -> [PlaybackDevice] { throw Self.unsupported }
    public func transfer(to device: PlaybackDevice) async throws(LibraryError) { throw Self.unsupported }
    public func artworkData(for artwork: LibraryArtwork) async -> Data? { nil }

    private static var unsupported: LibraryError {
        .failed("This source can’t do that. Choose another in Settings › Sources.")
    }
}

extension LibraryError {
    /// A request to the app behind `source` that didn't work, in words for the
    /// History window, which may name the app (DESIGN.md §10).
    public init(_ error: PlaybackError, app name: String, source: SourceID) {
        switch error {
        case .notInstalled:
            self = .unavailable(LibraryUnavailable(
                title: "\(name) Isn’t Installed",
                message: "Install \(name), then try again."
            ))
        case .notRunning:
            self = .unavailable(LibraryUnavailable(
                title: "\(name) Isn’t Open",
                message: "Open \(name), then try again.",
                fix: .openApp(source, name: name)
            ))
        case .permissionDenied:
            self = .unavailable(LibraryUnavailable(
                title: "No Access to \(name)",
                message: "Turn on \(name) for Hum in System Settings › Privacy & Security › Automation.",
                fix: .openAutomationSettings
            ))
        case .permissionNotDetermined:
            self = .unavailable(LibraryUnavailable(
                title: "Allow Access to \(name)",
                message: "Hum needs your permission to control \(name).",
                fix: .allowAutomation(app: name)
            ))
        case .timedOut:
            self = .transient("\(name) took too long to answer.")
        case .unsupported, .launchFailed, .scriptFailed:
            self = .transient("\(name) couldn’t do that.")
        }
    }
}
