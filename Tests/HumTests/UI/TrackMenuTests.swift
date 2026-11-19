import HumCore
import HumSources
@testable import HumUI
import Testing

@Suite("Track menu")
struct TrackMenuTests {
    static func menu(
        _ capabilities: SourceCapabilities,
        isSaved: Bool = false,
        context: TrackMenu.Context = .now
    ) -> TrackMenu {
        TrackMenu(capabilities: capabilities, isSaved: isSaved, context: context)
    }

    @Test func actionsTheSourceCantDoAreLeftOut() {
        #expect(Self.menu([]).isEmpty)
        #expect(Self.menu(.transport).isEmpty)
        #expect(Self.menu([.favorite]).entries == [.action(.toggleSave)])
    }

    @Test func separatorsOnlySitBetweenGroups() {
        let menu = Self.menu([.favorite, .shareLink, .reveal])
        #expect(menu.entries == [.action(.toggleSave), .separator, .action(.copyLink), .action(.reveal)])
    }

    /// The playing song has nothing for Play Now to do (§4.4).
    @Test func playNowIsOnlyOfferedAwayFromNow() {
        #expect(Self.menu([.playItems, .favorite], context: .now).actions == [.toggleSave])
        #expect(Self.menu([.playItems, .saveItems], context: .history).actions == [.playNow, .toggleSave])
    }

    /// The deleted queue, playlist, browse and station items stay gone, whatever
    /// the source says it can do.
    @Test func onlyTheFourSongItemsAreEverOffered() {
        let everything = SourceCapabilities(rawValue: ~0)
        #expect(Self.menu(everything, context: .history).actions == [.playNow, .toggleSave, .copyLink, .reveal])
        #expect(Self.menu(everything, context: .now).actions == [.toggleSave, .copyLink, .reveal])
    }

    /// No title names the music app (§10).
    @Test func titlesNeverNameTheApp() {
        #expect(Self.menu([.favorite]).title(for: .toggleSave) == "Favorite")
        #expect(Self.menu([.favorite], isSaved: true).title(for: .toggleSave) == "Remove from Favorites")
        #expect(Self.menu([.reveal]).title(for: .reveal) == "Show in App")
        #expect(Self.menu([.shareLink]).title(for: .copyLink) == "Copy Link")
        #expect(Self.menu([.playItems], context: .history).title(for: .playNow) == "Play Now")
        let menu = Self.menu(SourceCapabilities(rawValue: ~0), context: .history)
        for action in menu.actions {
            #expect(!menu.title(for: action).contains("Spotify"))
            #expect(!menu.title(for: action).contains("Music"))
        }
    }

    @Test func saveIsAStar() {
        #expect(SaveVocabulary.symbol(isSaved: false) == HumIcon.favorite)
        #expect(SaveVocabulary.symbol(isSaved: true) == HumIcon.favoriteOn)
        #expect(SaveVocabulary.title(isSaved: false) == "Favorite")
    }

    /// Spotify's app can't save songs, so the playing song's menu there is
    /// Copy Link and Show in App.
    @Test func aSpotifySongsMenuIsItsLinks() {
        #expect(Self.menu(SpotifyApp.capabilities).entries == [.action(.copyLink), .action(.reveal)])
    }

    /// Music has no web links, so its song's menu is Favorite, then Show in App.
    @Test func aMusicSongsMenuIsFavoriteThenShow() {
        #expect(Self.menu(MusicApp.capabilities).entries == [.action(.toggleSave), .separator, .action(.reveal)])
    }
}

@Suite("Player menu")
struct PlayerMenuTests {
    @Test func theSectionIsNamedAsTheDesignSays() {
        #expect(PlayerMenu.styleTitle == "Style")
        #expect(PlayerMenu.pinTitle == "Pin to")
        #expect(PlayerMenu.showTitle == "Show")
        #expect(PlayerMenu.moveToMenuBarTitle == "Move to Menu Bar")
        #expect(PlayerMenu.hidePlayerTitle == "Hide Player")
    }

    /// Style ▸ lists the styles with a window; Menu Bar has its own item.
    @Test func styleListsTheWindowStylesInOrder() {
        #expect(PlayerMenu.styles == [.artOnly, .title, .text, .strip, .wide, .bigArt])
        #expect(!PlayerMenu.styles.contains(.menuBar))
    }

    @Test func pinToHasThreeGroupsOfThree() {
        #expect(PlayerMenu.pinGroups.count == 3)
        #expect(PlayerMenu.pinGroups.allSatisfy { $0.count == 3 })
        #expect(Set(PlayerMenu.pinGroups.flatMap(\.self)) == Set(PinPosition.allCases))
        #expect(PlayerMenu.pinGroups[0] == [.topLeft, .top, .topRight])
        #expect(PlayerMenu.pinGroups[2] == [.bottomLeft, .bottom, .bottomRight])
    }

    /// Every pin draws its own place on the screen.
    @Test func everyPinHasItsOwnSymbol() {
        let symbols = PinPosition.allCases.map(PlayerMenu.symbol(for:))
        #expect(Set(symbols).count == PinPosition.allCases.count)
        #expect(PlayerMenu.symbol(for: .topLeft) == "rectangle.inset.topleft.filled")
        #expect(PlayerMenu.symbol(for: .center) == "rectangle.center.inset.filled")
    }

    @Test func showListsTheSurfacesWithTheirShortcuts() {
        #expect(PlayerMenu.surfaces == [.now, .echo, .status])
        #expect(PlayerMenu.surfaces.map(PlayerMenu.title(for:)) == ["Now", "History", "Status"])
        #expect(PlayerMenu.surfaces.map(PlayerMenu.shortcutDigit(for:)) == ["1", "2", "3"])
    }
}
