import os

/// Hum's diagnostic log: one unified-logging category per area, all under the
/// app's subsystem, so `log stream --predicate 'subsystem == "com.millerroberts.hum"'`
/// or Console shows a field problem's trail.
///
/// ```swift
/// HumLog.sources.error("Spotify didn't answer: \(code, privacy: .public)")
/// HumLog.history.debug("Recorded \(listen.title, privacy: .private)")
/// ```
///
/// - Track titles, artist and album names, playlist names, and search text
///   are always `privacy: .private`.
/// - Anything that could identify an account is never logged, not even as
///   `.private`.
/// - Error codes, states, counts, and durations are `.public`; that's what
///   makes a log useful once it leaves the Mac.
public enum HumLog {
    public static let subsystem = AppDirectories.bundleIdentifier

    public enum Category: String, CaseIterable, Sendable {
        /// Spotify.app, Music.app, and the demo: Apple Events, notifications, state.
        case sources
        /// Play and Find: the Music library, playing songs from Echo, caches.
        case library
        /// Listening history: recording, the database, export.
        case history
        /// The player window, Settings, and the History window.
        case window
        /// Launch, quit, menus, global shortcuts.
        case app
    }

    public static let sources = logger(.sources)
    public static let library = logger(.library)
    public static let history = logger(.history)
    public static let window = logger(.window)
    public static let app = logger(.app)

    public static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
}
