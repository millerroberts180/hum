import HumCore
@testable import HumSources
@testable import HumUI
import Testing

/// A song's menu in Echo and the History window: Play Now, then Favorite, then
/// Copy Link and Show in App, with a separator only between groups that have
/// something (DESIGN.md §4.4).
@Suite("Track menu groups")
struct TrackMenuGroupingTests {
    static func menu(_ capabilities: SourceCapabilities, canPlay: Bool = true) -> TrackMenu {
        TrackMenu(capabilities: capabilities, isSaved: false, context: .history, canPlay: canPlay)
    }

    @Test func everyGroupIsSeparated() {
        let menu = Self.menu([.playItems, .saveItems, .shareLink, .reveal])
        #expect(menu.entries == [
            .action(.playNow), .separator,
            .action(.toggleSave), .separator,
            .action(.copyLink), .action(.reveal),
        ])
    }

    @Test func anEmptyGroupLeavesNoSeparator() {
        #expect(Self.menu([.playItems, .shareLink]).entries == [.action(.playNow), .separator, .action(.copyLink)])
        #expect(Self.menu([.saveItems, .reveal]).entries == [.action(.toggleSave), .separator, .action(.reveal)])
        #expect(Self.menu([.playItems]).entries == [.action(.playNow)])
        #expect(Self.menu([]).isEmpty)
    }

    /// A song the source can't start keeps the rest of its menu.
    @Test func aSongThatCantPlayLosesOnlyPlayNow() {
        let menu = Self.menu([.playItems, .saveItems, .shareLink], canPlay: false)
        #expect(menu.entries == [.action(.toggleSave), .separator, .action(.copyLink)])
    }

    /// Favorite in a list needs a source that can save any song, not just
    /// the one playing.
    @Test func favoriteInAListNeedsSaveItems() {
        #expect(!Self.menu([.favorite]).actions.contains(.toggleSave))
        #expect(Self.menu([.saveItems]).actions.contains(.toggleSave))
    }
}

/// Start Station stays out until a source can start radio: no source or
/// library offers it.
@MainActor
@Suite("Radio is hidden")
struct RadioHiddenTests {
    static let every: [(String, SourceCapabilities)] = [
        ("Spotify", SpotifyApp.capabilities),
        ("Music", MusicApp.capabilities),
        ("Demo", DemoSource.capabilities),
        ("Demo as Spotify", DemoSource.spotifyCapabilities),
    ]

    @Test func noSourceOffersRadio() {
        for (name, capabilities) in Self.every {
            #expect(!capabilities.contains(.radio), "\(name) offers radio")
        }
    }

    @Test func noLibraryOffersRadio() {
        let source = DemoSource(startsPlaying: false, startPosition: 0, latency: .zero)
        let demo = DemoLibrary(source: source, listLatency: .zero)
        let music = MusicLibrary { _ throws(PlaybackError) in .null }
        #expect(!demo.capabilities.contains(.radio))
        #expect(!music.capabilities.contains(.radio))
    }
}
