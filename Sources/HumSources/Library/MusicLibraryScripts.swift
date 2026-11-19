import Foundation
import HumCore

/// AppleScript for what Hum does with Music's songs beyond Now: Play Now,
/// Favorite, artwork, and AirPlay devices.
enum MusicLibraryScripts {
    static let bundleIdentifier = MusicApp.bundleIdentifier

    /// A string as an AppleScript literal.
    static func literal(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }

    static func guarded(_ body: String, timeout: Int = 10) -> String {
        ScriptTemplate.guarded(bundleIdentifier, timeout: timeout, body)
    }

    // MARK: References

    static let library = "library playlist 1"

    static func playlist(_ persistentID: String) -> String {
        "(first playlist whose persistent ID is \(literal(persistentID)))"
    }

    static func track(_ persistentID: String) -> String {
        "(first track of \(library) whose persistent ID is \(literal(persistentID)))"
    }

    // MARK: Devices

    /// `{persistent ID, name, kind, selected, available}` for each AirPlay device.
    static let devices = guarded("""
        set ds to a reference to (every AirPlay device)
        if (count of ds) is 0 then return {}
        set kinds to {}
        repeat with k in (get kind of ds)
        \tset end of kinds to ((contents of k) as string)
        end repeat
        return {persistent ID of ds, name of ds, kinds, selected of ds, available of ds}
        """)

    // MARK: Commands

    static func play(track persistentID: String, inPlaylist playlistID: String?) -> String {
        if let playlistID {
            return guarded("play (first track of \(playlist(playlistID)) whose persistent ID is \(literal(persistentID)))")
        }
        return guarded("play \(track(persistentID))")
    }

    static func setFavorite(_ favorite: Bool, track persistentID: String) -> String {
        guarded("""
            set t to \(track(persistentID))
            try
            \tset favorited of t to \(favorite)
            on error
            \tset loved of t to \(favorite)
            end try
            """)
    }

    static func isFavorite(track persistentID: String) -> String {
        guarded("""
            set t to \(track(persistentID))
            try
            \treturn favorited of t
            on error
            \treturn loved of t
            end try
            """)
    }

    static func selectDevice(_ persistentID: String) -> String {
        guarded("set current AirPlay devices to {(first AirPlay device whose persistent ID is \(literal(persistentID)))}")
    }

    static func artwork(track persistentID: String) -> String {
        guarded("""
            set t to \(track(persistentID))
            if (count of artworks of t) is 0 then return missing value
            return raw data of artwork 1 of t
            """)
    }

    static func artwork(playlist persistentID: String) -> String {
        guarded("""
            set p to \(playlist(persistentID))
            if (count of tracks of p) is 0 then return missing value
            set t to track 1 of p
            if (count of artworks of t) is 0 then return missing value
            return raw data of artwork 1 of t
            """)
    }
}
