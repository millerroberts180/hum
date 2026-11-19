import HumCore
@testable import HumUI
import Testing

@Suite("Settings and style launch options")
struct SettingsLaunchOptionsTests {
    @Test func settingsOpensOnTheNamedPane() {
        let options = LaunchOptions(arguments: ["Hum", "--demo", "--settings", "appearance"], environment: [:])
        #expect(options.settingsPane == "appearance")
        #expect(options.settingsPane.flatMap(SettingsPane.init(rawValue:)) == .appearance)
        for pane in SettingsPane.allCases {
            let parsed = LaunchOptions(arguments: ["Hum", "--settings", pane.rawValue], environment: [:])
            #expect(parsed.settingsPane.flatMap(SettingsPane.init(rawValue:)) == pane)
        }
    }

    @Test func anUnknownPaneOpensNothing() {
        let options = LaunchOptions(arguments: ["Hum", "--settings", "everything"], environment: [:])
        #expect(options.settingsPane.flatMap(SettingsPane.init(rawValue:)) == nil)
        #expect(LaunchOptions(arguments: ["Hum", "--settings"], environment: [:]).settingsPane == nil)
    }

    @Test func styleNamesAStyle() {
        #expect(LaunchOptions(arguments: ["Hum", "--demo", "--style", "bigArt"], environment: [:]).style == .bigArt)
        #expect(LaunchOptions(arguments: ["Hum", "--demo", "--style", "compact"], environment: [:]).style == .strip)
        #expect(LaunchOptions(arguments: ["Hum", "--demo", "--style", "neon"], environment: [:]).style == nil)
        // A retired style (DESIGN.md §13.19) is as unknown as any other name.
        #expect(LaunchOptions(arguments: ["Hum", "--demo", "--style", "glass"], environment: [:]).style == nil)
        #expect(LaunchOptions(arguments: ["Hum", "--style"], environment: [:]).style == nil)
    }

    @Test func aPlainLaunchHasNeither() {
        let options = LaunchOptions(arguments: ["Hum"], environment: [:])
        #expect(options.settingsPane == nil)
        #expect(options.style == nil)
    }

    /// Find was removed, so `--summon-find` is an unknown flag now: older
    /// scripts that pass it launch as if it weren't there.
    @Test func summonFindIsIgnored() {
        #expect(
            LaunchOptions(arguments: ["Hum", "--demo", "--summon-find"], environment: [:])
                == LaunchOptions(arguments: ["Hum", "--demo"], environment: [:])
        )
        #expect(LaunchOptions(arguments: ["Hum", "--summon-find", "--style", "title"], environment: [:]).style == .title)
    }

    #if DEBUG
    @Test func slowMotionTakesAFactorOfOneOrMore() {
        #expect(LaunchOptions(arguments: ["Hum", "--demo", "--slow-motion", "10"], environment: [:]).slowMotion == 10)
        #expect(LaunchOptions(arguments: ["Hum", "--slow-motion", "0.2"], environment: [:]).slowMotion == 1)
        #expect(LaunchOptions(arguments: ["Hum", "--slow-motion", "fast"], environment: [:]).slowMotion == nil)
        #expect(LaunchOptions(arguments: ["Hum"], environment: [:]).slowMotion == nil)
    }

    @MainActor
    @Test func slowMotionStretchesTheStyleSwitchWithoutChangingItsShape() {
        let previous = Motion.slowMotion
        defer { Motion.slowMotion = previous }
        Motion.slowMotion = 1
        #expect(Motion.styleSwitchSpring == Motion.smoothSpring)
        Motion.slowMotion = 10
        #expect(Motion.styleSwitchSpring.response == 3.5)
        #expect(Motion.styleSwitchSpring.dampingRatio == 1)
    }
    #endif
}
