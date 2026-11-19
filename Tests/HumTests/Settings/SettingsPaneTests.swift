import AppKit
import Foundation
import HumCore
@testable import HumUI
import Testing

@Suite("Settings panes")
@MainActor
struct SettingsPaneTests {
    @Test func openingAPaneRoutesToIt() {
        let navigation = SettingsNavigation()
        #expect(navigation.pane == .general)
        navigation.open(.shortcuts)
        #expect(navigation.pane == .shortcuts)
        navigation.open(.echoPrivacy)
        #expect(navigation.pane == .echoPrivacy)
    }

    @Test func openingWithoutAPaneStaysWhereItWas() {
        let navigation = SettingsNavigation(pane: .appearance)
        navigation.open(nil)
        #expect(navigation.pane == .appearance)
    }

    @Test func everyPaneHasATitleAGlyphAndASummary() {
        for pane in SettingsPane.allCases {
            #expect(!pane.title.isEmpty)
            #expect(!pane.systemImage.isEmpty)
            #expect(!pane.summary.isEmpty)
            #expect(pane.id == pane.rawValue)
        }
        #expect(Set(SettingsPane.allCases.map(\.title)).count == SettingsPane.allCases.count)
    }

    @Test func thePanesComeInSidebarOrder() {
        #expect(SettingsPane.allCases == [.general, .appearance, .player, .shortcuts, .sources, .echoPrivacy, .about])
        #expect(SettingsSidebarGroup.all.flatMap(\.panes) == SettingsPane.allCases)
    }

    /// DESIGN.md §8: General alone, Player, Music, then Hum alone.
    @Test func theSidebarIsGroupedByPurpose() {
        let groups = SettingsSidebarGroup.all.map { ($0.title, $0.panes) }
        #expect(groups.count == 4)
        #expect(groups[0].0 == nil && groups[0].1 == [.general])
        #expect(groups[1].0 == "Player" && groups[1].1 == [.appearance, .player, .shortcuts])
        #expect(groups[2].0 == "Music" && groups[2].1 == [.sources, .echoPrivacy])
        #expect(groups[3].0 == nil && groups[3].1 == [.about])
        // The sidebar writes the sections out by name, in this order.
        #expect(SettingsSidebarGroup.all == [.general, .player, .music, .hum])
    }

    /// Player is the group now, so its old pane is Behavior; Echo is History;
    /// About is Hum (§13.23, §13.27).
    @Test func thePanesHaveTheirNewTitles() {
        #expect(SettingsPane.allCases.map(\.title) == [
            "General", "Appearance", "Behavior", "Shortcuts", "Sources", "History & Privacy", "Hum",
        ])
        for pane in SettingsPane.allCases {
            #expect(!pane.title.contains("Echo"), "\(pane)")
        }
    }

    /// Stored selections and `--settings` keep the first names.
    @Test func theRawValuesStay() {
        #expect(SettingsPane.allCases.map(\.rawValue) == [
            "general", "appearance", "player", "shortcuts", "sources", "echoPrivacy", "about",
        ])
    }

    @Test func theSettingsArgumentTakesARawValueOrHum() {
        for pane in SettingsPane.allCases {
            #expect(SettingsPane(argument: pane.rawValue) == pane)
        }
        #expect(SettingsPane(argument: "hum") == .about)
        #expect(SettingsPane(argument: "Hum") == nil)
        #expect(SettingsPane(argument: "behavior") == nil)
        #expect(SettingsPane(argument: "") == nil)
    }

    /// Sources names only the apps.
    @Test func theSummariesSayWhatThePanesHold() {
        #expect(SettingsPane.about.summary == "What Hum is, its version, and how to quit it.")
        #expect(SettingsPane.sources.summary == "The music apps Hum plays from.")
    }

    /// The Hum pane's copy, as DESIGN.md §8 gives it.
    @Test func theHumPaneSaysWhatHumIsAndWhoseTheMusicIs() {
        #expect(HumSettingsPane.tagline == "The song you’re playing, always at hand.")
        #expect(HumSettingsPane.description.hasPrefix("Hum shows what Music or Spotify is playing as a floating window of album art"))
        #expect(HumSettingsPane.description.hasSuffix("Your listening history stays on this Mac."))
        #expect(HumSettingsPane.requirement == "Requires macOS 15 or later")
        #expect(HumSettingsPane.notice == "Covers, titles and playback come from the music apps you use, and belong to their owners. Spotify is a trademark of Spotify AB. Apple Music is a trademark of Apple Inc. Hum is not affiliated with or endorsed by either.")
        #expect(HumSettingsPane.iconSize == 64)
    }

    @Test func theVersionLineComesFromInfoPlist() {
        #expect(HumSettingsPane.version(from: ["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1"]) == "Version 1.0.0 (1)")
        #expect(HumSettingsPane.version(from: ["CFBundleShortVersionString": "1.2", "CFBundleVersion": "1.2"]) == "Version 1.2")
        #expect(HumSettingsPane.version(from: ["CFBundleShortVersionString": "1.2"]) == "Version 1.2")
        #expect(HumSettingsPane.version(from: ["CFBundleVersion": "7"]) == "Development build")
        #expect(HumSettingsPane.version(from: nil) == "Development build")
    }

    /// Every pane's name fits the sidebar whole, at the largest sidebar text
    /// size (15 pt, System Settings › Appearance › Sidebar icon size), beside
    /// its tile and inside the list's own insets.
    @Test func everyPaneNameFitsTheSidebar() {
        let font = NSFont.systemFont(ofSize: 15)
        // The tile's gap to its title, and the list's insets on both sides.
        let chrome = SettingsMetrics.sidebarTile + 8 + 2 * 18
        for pane in SettingsPane.allCases {
            let title = (pane.title as NSString).size(withAttributes: [.font: font]).width
            #expect(title + chrome <= SettingsMetrics.sidebarWidth, "\(pane.title)")
        }
    }
}

@Suite("Behavior settings")
struct BehaviorSettingsTests {
    @Test func swipingMovesBetweenSurfacesAndNeverSkipsUntilAsked() {
        let behavior = BehaviorSettings()
        #expect(behavior.swipeBetweenSurfaces)
        #expect(!behavior.swipeToSkip)
    }

    @Test func settingsFromBeforeTheGestureSwitchesStillLoad() throws {
        let json = """
        { "visibility": "pinned", "alwaysOnTop": false, "showOnAllSpaces": true,
          "snapToCorners": false, "trackChangeDisplaySeconds": 6 }
        """
        let behavior = try JSONDecoder().decode(BehaviorSettings.self, from: Data(json.utf8))
        #expect(!behavior.alwaysOnTop)
        #expect(!behavior.snapToCorners)
        #expect(behavior.swipeBetweenSurfaces)
        #expect(!behavior.swipeToSkip)
    }

    @Test func theOldTrackChangeDelayIsIgnoredAndDropped() throws {
        // The delay is fixed now (DESIGN.md §4.5); a file that still has it loads.
        let json = #"{ "trackChangeDisplaySeconds": 600, "alwaysOnTop": false, "swipeToSkip": "yes" }"#
        let behavior = try JSONDecoder().decode(BehaviorSettings.self, from: Data(json.utf8))
        #expect(!behavior.alwaysOnTop)
        #expect(!behavior.swipeToSkip)
        let saved = try String(decoding: JSONEncoder().encode(behavior), as: UTF8.self)
        #expect(!saved.contains("trackChangeDisplaySeconds"))
        #expect(saved.contains("alwaysOnTop"))
    }
}
