import Foundation
@testable import HumCore
@testable import HumUI
import Testing

@Suite("Style looks")
struct StyleLookTests {
    @Test func everyStyleShipsTheSameBuiltInLook() {
        for style in PlayerStyleID.allCases {
            for appearance in LookAppearance.allCases {
                #expect(StyleLook.builtIn(for: style, in: appearance) == StyleLook())
            }
        }
    }

    /// DESIGN.md §13.11: every style's transport has shuffle and repeat, on by
    /// default, Art Only and Text included, and Settings can switch them off.
    @Test(arguments: PlayerStyleID.allCases)
    func everyStyleShipsWithShuffleAndRepeat(style: PlayerStyleID) {
        for appearance in LookAppearance.allCases {
            #expect(StyleLook.builtIn(for: style, in: appearance).hoverControls.contains(.shuffleRepeat))
        }
        #expect(style.hoverChoices.contains(.shuffleRepeat))
    }

    /// Every control §6.1 lists, so L shows the album, volume and devices.
    @Test func artOnlyOffersEveryHoverControl() {
        #expect(PlayerStyleID.artOnly.hoverChoices == .all)
        for appearance in LookAppearance.allCases {
            #expect(StyleLook.builtIn(for: .artOnly, in: appearance).hoverControls == .all)
        }
    }

    /// The other shapes offer only the pieces §7 gives them.
    @Test func theOtherShapesOfferOnlyTheirOwnPieces() {
        #expect(PlayerStyleID.title.hoverChoices == [.seekBar, .shuffleRepeat])
        #expect(PlayerStyleID.text.hoverChoices == [.shuffleRepeat])
        #expect(PlayerStyleID.strip.hoverChoices == [.seekBar, .shuffleRepeat])
        // The cards: the same stack, with the album only on Big Art.
        #expect(PlayerStyleID.wide.hoverChoices == [.seekBar, .shuffleRepeat, .save, .volume])
        #expect(PlayerStyleID.bigArt.hoverChoices == [.album, .seekBar, .shuffleRepeat, .save, .volume])
        #expect(PlayerStyleID.menuBar.hoverChoices == [.shuffleRepeat])
    }

    /// Wide's default has every piece it offers on (§7).
    @Test(arguments: [PlayerStyleID.wide, .bigArt])
    func theCardsShipWithEveryPieceOn(style: PlayerStyleID) {
        for appearance in LookAppearance.allCases {
            let shown = StyleLook.builtIn(for: style, in: appearance).hoverControls
            #expect(shown.isSuperset(of: style.hoverChoices))
        }
    }

    /// Settings says where each piece has room: the cards keep the volume
    /// row at every size, where Art Only has room for it only at L.
    @Test func theCardsShowTheVolumeAtEverySize() {
        #expect(HoverControls.volume.sizeClasses(in: .artOnly) == "Large players")
        #expect(HoverControls.volume.sizeClasses(in: .wide) == "Every size")
        #expect(HoverControls.volume.sizeClasses(in: .bigArt) == "Every size")
        #expect(HoverControls.album.sizeClasses(in: .bigArt) == "Medium and large players")
        #expect(HoverControls.seekBar.sizeClasses(in: .wide) == "Every size")
    }

    @Test func onlyArtOnlyChoosesAProgressIndicatorAndOnlyTextATint() {
        #expect(PlayerStyleID.allCases.filter(\.offersProgressChoice) == [.artOnly])
        #expect(PlayerStyleID.allCases.filter(\.offersAlbumTint) == [.text])
    }

    /// Someone who never touched shuffle and repeat gets the new default; an
    /// explicit choice stays.
    @Test func hoverEditsAreStoredRelativeToTheBuiltIn() {
        var settings = AppearanceSettings()
        settings.updateLookInBothAppearances(for: .artOnly) { $0.hoverControls.remove(.album) }
        let stored = settings.overrides[AppearanceSettings.key(.artOnly, .dark)]?.hoverControls
        #expect(stored == HoverControlsChange(hidden: .album))
        #expect(settings.look(for: .artOnly, in: .dark).hoverControls == HoverControls.all.subtracting(.album))

        settings.updateLookInBothAppearances(for: .bigArt) { $0.hoverControls.remove(.shuffleRepeat) }
        #expect(!settings.look(for: .bigArt, in: .light).hoverControls.contains(.shuffleRepeat))
        // Turning it back on leaves nothing behind.
        settings.updateLookInBothAppearances(for: .bigArt) { $0.hoverControls.insert(.shuffleRepeat) }
        #expect(!settings.isCustomized(.bigArt))
    }

    @Test func aChangeAppliesToWhateverTheBuiltInIs() {
        let change = HoverControlsChange(shown: .shuffleRepeat, hidden: [.album, .volume])
        #expect(change.applied(to: [.trackInfo, .album]) == [.trackInfo, .shuffleRepeat])
        #expect(change.applied(to: .all) == HoverControls.all.subtracting([.album, .volume]))
        // Something can't be both shown and hidden; shown wins.
        #expect(HoverControlsChange(shown: .save, hidden: .save) == HoverControlsChange(shown: .save))
        #expect(HoverControlsChange(from: .all, to: .all).isEmpty)
    }

    @Test func anEditInOneAppearanceLeavesTheOtherBuiltIn() {
        var settings = AppearanceSettings()
        settings.updateLook(for: .bigArt, in: .dark) { $0.opacity = 0.8 }
        #expect(settings.look(for: .bigArt, in: .dark).opacity == 0.8)
        #expect(settings.look(for: .bigArt, in: .light) == StyleLook.builtIn(for: .bigArt, in: .light))
        #expect(settings.look(for: .artOnly, in: .dark) == StyleLook.builtIn(for: .artOnly, in: .dark))
        #expect(settings.isCustomized(.bigArt))
        #expect(!settings.isCustomized(.artOnly))
    }

    @Test func onlyTheDifferenceIsStored() {
        var settings = AppearanceSettings()
        settings.updateLook(for: .artOnly, in: .light) { $0.progress = .ring }
        #expect(settings.overrides[AppearanceSettings.key(.artOnly, .light)]?.progress == .ring)
        #expect(settings.overrides[AppearanceSettings.key(.artOnly, .light)]?.opacity == nil)
        // Setting it back to the built-in value leaves nothing behind.
        settings.updateLook(for: .artOnly, in: .light) { $0.progress = StyleLook().progress }
        #expect(settings.overrides.isEmpty)
        #expect(!settings.isCustomized(.artOnly))
    }

    @Test func aChangedBuiltInStillReachesFieldsTheUserNeverTouched() {
        var override = LookOverride()
        override.opacity = 0.75
        let look = StyleLook.builtIn(for: .text, in: .light).applying(override)
        #expect(look.opacity == 0.75)
        #expect(look.hoverControls == .all)
        #expect(look.albumTint == false)
    }

    @Test func resetReturnsBothAppearancesToTheBuiltIn() {
        var settings = AppearanceSettings()
        settings.updateLookInBothAppearances(for: .text) { $0.albumTint = true }
        settings.updateLook(for: .text, in: .dark) { $0.cornerRadiusScale = 1.4 }
        settings.updateLook(for: .bigArt, in: .light) { $0.opacity = 0.9 }
        settings.resetLook(for: .text)
        #expect(settings.look(for: .text, in: .light) == StyleLook.builtIn(for: .text, in: .light))
        #expect(settings.look(for: .text, in: .dark) == StyleLook.builtIn(for: .text, in: .dark))
        #expect(!settings.isCustomized(.text))
        // Other styles keep their edits.
        #expect(settings.look(for: .bigArt, in: .light).opacity == 0.9)
    }

    @Test func theCurrentStylesLookFollowsTheStyle() {
        var settings = AppearanceSettings()
        settings.updateLook(for: .bigArt, in: .dark) { $0.progress = .ring }
        settings.style = .bigArt
        #expect(settings.look(in: .dark).progress == .ring)
        settings.style = .artOnly
        #expect(settings.look(in: .dark).progress == StyleLook().progress)
    }

    @Test func slidersCannotLeaveTheirRanges() {
        var look = StyleLook(cornerRadiusScale: 9, opacity: 0.1)
        #expect(look.cornerRadiusScale == StyleLook.cornerRadiusScaleRange.upperBound)
        #expect(look.opacity == StyleLook.opacityRange.lowerBound)
        look.opacity = 4
        #expect(look.opacity == 1)
        look.cornerRadiusScale = -1
        #expect(look.cornerRadiusScale == 0.5)
        look.opacity = .nan
        #expect(look.opacity == 1)
        look.cornerRadiusScale = .infinity
        #expect(look.cornerRadiusScale == StyleLook.cornerRadiusScaleRange.upperBound)
    }

    @Test func storedOverridesAreClampedOnTheWayIn() throws {
        let json = #"{"opacity": 0.05, "cornerRadiusScale": 12, "progress": "spiral", "hoverControls": 1023}"#
        let override = try JSONDecoder().decode(LookOverride.self, from: Data(json.utf8))
        #expect(override.opacity == 0.7)
        #expect(override.cornerRadiusScale == 1.5)
        // An unknown progress indicator follows the built-in instead.
        #expect(override.progress == nil)
        // Bits from a newer Hum are dropped, and a set that matches the
        // built-in stores nothing.
        #expect(override.hoverControls == nil)
    }

    @Test func hoverControlsShowOnlyWhereThereIsRoom() {
        let look = PlayerLook(style: .artOnly, look: StyleLook(), appearance: .dark, isBar: false)
        // DESIGN.md §6.1: S has shuffle and repeat, the bar alone and Save;
        // M adds the title and album; L adds volume and devices.
        #expect(look.hoverControls(at: .small) == [.seekBar, .shuffleRepeat, .save])
        #expect(look.hoverControls(at: .medium) == [.trackInfo, .album, .seekBar, .shuffleRepeat, .save])
        #expect(look.hoverControls(at: .large) == .all)

        var trimmed = StyleLook()
        trimmed.hoverControls = [.seekBar]
        let quiet = PlayerLook(style: .artOnly, look: trimmed, appearance: .dark, isBar: false)
        #expect(quiet.hoverControls(at: .large) == [.seekBar])
    }

    @Test func everyHoverControlHasATitleAndSizeClasses() {
        for control in HoverControls.ordered {
            #expect(!control.title.isEmpty)
            #expect(!control.sizeClasses.isEmpty)
        }
        #expect(HoverControls(HoverControls.ordered) == .all)
    }
}

@Suite("Appearance settings migration")
struct AppearanceMigrationTests {
    private func decode(_ json: String) throws -> AppearanceSettings {
        try JSONDecoder().decode(AppearanceSettings.self, from: Data(json.utf8))
    }

    @Test func theOldFlatAccentCarriesIntoEveryStyle() throws {
        let settings = try decode("""
        {"style": "bigArt", "mode": "dark", "accent": "custom",
         "customAccent": {"red": 0.9, "green": 0.1, "blue": 0.3}}
        """)
        #expect(settings.style == .bigArt)
        #expect(settings.mode == .dark)
        let color = PaletteColor(red: 0.9, green: 0.1, blue: 0.3)
        for style in PlayerStyleID.allCases {
            for appearance in LookAppearance.allCases {
                let look = settings.look(for: style, in: appearance)
                #expect(look.accent == .custom)
                #expect(look.customAccent == color)
            }
        }
    }

    @Test func aDefaultOldAccentStoresNothing() throws {
        let settings = try decode(#"{"style": "artOnly", "accent": "system"}"#)
        #expect(settings.overrides.isEmpty)
    }

    @Test func newOverridesWinOverTheOldFields() throws {
        let settings = try decode("""
        {"accent": "album", "overrides": {"artOnly.dark": {"opacity": 0.8}}}
        """)
        #expect(settings.look(for: .artOnly, in: .dark).opacity == 0.8)
        #expect(settings.look(for: .artOnly, in: .dark).accent == .system)
        #expect(settings.look(for: .bigArt, in: .light).accent == .system)
    }

    @Test func oneBadOverrideDoesNotCostTheOthers() throws {
        let settings = try decode("""
        {"overrides": {"artOnly.dark": {"opacity": 0.8}, "bigArt.light": 42, "minimal.light": {"albumTint": true}}}
        """)
        #expect(settings.look(for: .artOnly, in: .dark).opacity == 0.8)
        #expect(settings.look(for: .text, in: .light).albumTint)
        #expect(settings.look(for: .bigArt, in: .light) == StyleLook.builtIn(for: .bigArt, in: .light))
    }

    /// DESIGN.md §13.19: a saved Glass, Data or Session opens as Art Only, and
    /// the looks saved for them are dropped; the rest carries over.
    @Test(arguments: ["glass", "data", "session"])
    func aRetiredStyleOpensAsArtOnlyWithoutItsLooks(retired: String) throws {
        let settings = try decode("""
        {"style": "\(retired)", "lastWindowStyle": "\(retired)", "mode": "dark",
         "overrides": {"\(retired).dark": {"opacity": 0.8}, "\(retired).light": {"progress": "ring"},
                       "minimal.light": {"albumTint": true}}}
        """)
        #expect(settings.style == .artOnly)
        #expect(settings.lastWindowStyle == .artOnly)
        #expect(settings.mode == .dark)
        #expect(Array(settings.overrides.keys) == ["minimal.light"])
        #expect(settings.look(for: .text, in: .light).albumTint)
        #expect(settings.look(for: .artOnly, in: .dark) == StyleLook.builtIn(for: .artOnly, in: .dark))
        let written = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        #expect(!written.contains(retired))
    }

    /// Before the redesign an override held the whole set. Art Only's and
    /// Minimal's built-ins then left shuffle and repeat off, so a set without
    /// them wasn't a choice: those players get them now. Elsewhere it was.
    @Test func oldWholeSetsTurnIntoChangesFromTheirDaysBuiltIn() throws {
        let withoutShuffleRepeat = HoverControls.all.subtracting(.shuffleRepeat)
        let withoutAlbum = withoutShuffleRepeat.subtracting(.album)
        let settings = try decode("""
        {"overrides": {
          "artOnly.dark": {"hoverControls": \(withoutAlbum.rawValue)},
          "artOnly.light": {"hoverControls": \(HoverControls.all.subtracting(.album).rawValue)},
          "minimal.dark": {"hoverControls": \(withoutShuffleRepeat.rawValue), "albumTint": true},
          "compact.dark": {"hoverControls": \(withoutShuffleRepeat.rawValue)},
          "compact.light": {"hoverControls": \(HoverControls.all.rawValue)}
        }}
        """)
        // Never chose shuffle and repeat: the new default, with the album choice kept.
        #expect(settings.look(for: .artOnly, in: .dark).hoverControls == HoverControls.all.subtracting(.album))
        // Turned them on: still on.
        #expect(settings.look(for: .artOnly, in: .light).hoverControls == HoverControls.all.subtracting(.album))
        #expect(settings.look(for: .text, in: .dark).hoverControls == .all)
        #expect(settings.look(for: .text, in: .dark).albumTint)
        // Switched them off where they were on: still off.
        #expect(settings.look(for: .strip, in: .dark).hoverControls == withoutShuffleRepeat)
        // A set equal to its day's built-in stores nothing.
        #expect(settings.overrides[AppearanceSettings.key(.strip, .light)] == nil)
    }

    /// Art Only at rest is the cover alone (DESIGN.md §13.10); None comes
    /// first among the choices.
    @Test func restingProgressIsOffByDefault() throws {
        #expect(StyleLook().progress == .none)
        #expect(AppearanceSettings().look(for: .artOnly, in: .light).progress == .none)
        #expect(ProgressIndicator.allCases == [.none, .line, .ring])
        #expect(ProgressIndicator.allCases.map(\.title) == ["None", "Line", "Ring"])
        let settings = try decode("""
        {"overrides": {"artOnly.dark": {"progress": "none"}}}
        """)
        #expect(settings.look(for: .artOnly, in: .dark).progress == .none)
    }

    @Test func theOldProgressChoicesStillDecode() throws {
        let settings = try decode("""
        {"overrides": {"artOnly.dark": {"progress": "ring"}, "artOnly.light": {"progress": "line"}}}
        """)
        #expect(settings.look(for: .artOnly, in: .dark).progress == .ring)
        #expect(settings.look(for: .artOnly, in: .light).progress == .line)
    }

    /// Text no longer offers hiding the cover; a saved choice decodes and
    /// changes nothing else.
    @Test func aSavedArtworkChoiceDecodesHarmlessly() throws {
        let settings = try decode("""
        {"overrides": {"minimal.light": {"showsArtwork": false, "opacity": 0.8}}}
        """)
        #expect(settings.look(for: .text, in: .light).opacity == 0.8)
    }

    @Test func roundTripsThroughJSON() throws {
        var settings = AppearanceSettings()
        settings.style = .text
        settings.updateLookInBothAppearances(for: .text) { $0.albumTint = true }
        settings.updateLookInBothAppearances(for: .artOnly) { $0.hoverControls.remove(.volume) }
        settings.updateLook(for: .strip, in: .light) { $0.accent = .album }
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppearanceSettings.self, from: data) == settings)
    }

    @Test func theCompatibilityAccentEditsTheCurrentStyle() {
        var settings = AppearanceSettings()
        settings.style = .bigArt
        settings.accent = .album
        #expect(settings.look(for: .bigArt, in: .light).accent == .album)
        #expect(settings.look(for: .bigArt, in: .dark).accent == .album)
        #expect(settings.look(for: .artOnly, in: .light).accent == .system)
        #expect(settings.accent == .album)
    }

    /// A window that is glass (macOS 26) holds the content inside it, so the
    /// resting fade belongs to the window and the content never fades twice.
    @Test func theRestingFadeIsTheWindowsWhenItsGlassHoldsTheContent() {
        let glass = PlayerRestingOpacity.opacity(isFull: false, resting: 0.8, usesWindowGlass: true)
        #expect(glass.content == 1)
        #expect(glass.window == 0.8)
        let plain = PlayerRestingOpacity.opacity(isFull: false, resting: 0.8, usesWindowGlass: false)
        #expect(plain.content == 0.8)
        #expect(plain.window == 1)
        for usesWindowGlass in [true, false] {
            let revealed = PlayerRestingOpacity.opacity(isFull: true, resting: 0.8, usesWindowGlass: usesWindowGlass)
            #expect(revealed.content == 1)
            #expect(revealed.window == 1)
        }
    }
}
