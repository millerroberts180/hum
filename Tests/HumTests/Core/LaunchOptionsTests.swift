import HumCore
import Testing

@Suite("Launch options")
struct LaunchOptionsTests {
    @Test func plainLaunchUsesRealSources() {
        let options = LaunchOptions(arguments: ["Hum"], environment: [:])
        #expect(options == LaunchOptions())
        #expect(!options.demo)
    }

    @Test func demoFromFlagOrEnvironment() {
        #expect(LaunchOptions(arguments: ["Hum", "--demo"], environment: [:]).demo)
        #expect(LaunchOptions(arguments: ["Hum"], environment: ["HUM_DEMO": "1"]).demo)
        #expect(LaunchOptions(arguments: ["Hum"], environment: ["HUM_DEMO": "YES"]).demo)
        #expect(!LaunchOptions(arguments: ["Hum"], environment: ["HUM_DEMO": "0"]).demo)
        let playing = LaunchOptions(arguments: ["Hum", "--demo-playing"], environment: [:])
        #expect(playing.demo && playing.demoStartsPlaying)
    }

    @Test func screenshotSwitches() {
        let options = LaunchOptions(
            arguments: ["Hum", "--demo", "--appearance", "dark", "--player-size", "420", "--reveal-controls", "--surface", "echo", "--reset-window"],
            environment: [:]
        )
        #expect(options.appearance == .dark)
        #expect(options.playerSize == 420)
        #expect(options.revealControls)
        #expect(options.surface == .echo)
        #expect(options.resetWindow)
    }

    @Test func badValuesAreIgnored() {
        let options = LaunchOptions(arguments: ["Hum", "--appearance", "sepia", "--surface", "nowhere", "--player-size"], environment: [:])
        #expect(options.appearance == nil)
        #expect(options.surface == nil)
        #expect(options.playerSize == nil)
    }

    /// Play and Find were removed; scripts that still open on them land on Now.
    @Test(arguments: [("now", Surface.now), ("echo", .echo), ("status", .status), ("play", .now), ("find", .now)])
    func surfaceFlagTakesEachSurfaceAndTheRemovedOnes(name: String, expected: Surface) {
        #expect(LaunchOptions(arguments: ["Hum", "--surface", name], environment: [:]).surface == expected)
    }

    @Test(arguments: PinPosition.allCases)
    func pinTakesEachPositionByItsStoredName(pin: PinPosition) {
        let options = LaunchOptions(arguments: ["Hum", "--pin", pin.rawValue], environment: [:])
        #expect(options.pin == pin)
        #expect(!options.demo)
    }

    @Test func pinIgnoresAnUnknownOrMissingPosition() {
        #expect(LaunchOptions(arguments: ["Hum", "--pin", "middle"], environment: [:]).pin == nil)
        #expect(LaunchOptions(arguments: ["Hum", "--pin"], environment: [:]).pin == nil)
        #expect(LaunchOptions(arguments: ["Hum"], environment: [:]).pin == nil)
    }

    @Test func demoAutomationTakesEachStateAndImpliesTheDemo() {
        let states: [(String, AutomationPermission)] = [("denied", .denied), ("undetermined", .notDetermined), ("granted", .granted)]
        for (name, permission) in states {
            let options = LaunchOptions(arguments: ["Hum", "--demo-automation", name], environment: [:])
            #expect(options.demoAutomation == permission)
            #expect(options.demo)
        }
        #expect(LaunchOptions(arguments: ["Hum", "--demo-automation", "maybe"], environment: [:]).demoAutomation == nil)
        #expect(LaunchOptions(arguments: ["Hum", "--demo"], environment: [:]).demoAutomation == nil)
    }
}
