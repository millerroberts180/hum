import Foundation

/// Command-line switches, mostly for demos, screenshots, and development.
///
/// - `--demo` or `HUM_DEMO=1`: use the built-in demo source and never touch Spotify
///   or Music.
/// - `--demo-playing`: start the demo playing instead of paused.
/// - `--demo-history`: refill the demo's listening history with six months of
///   made-up listening. Implies `--demo`; real history is never touched.
/// - `--demo-device <name>`: start the demo playing on another device, such as
///   `kitchen`, `living-room`, `phone`, or `headphones`. Implies `--demo`.
/// - `--demo-attribution <name>`: the demo names a service as the source of its
///   songs. `Spotify` makes it show what a Spotify listener sees: no Save, no
///   devices, and no album or playlist a song plays from (DESIGN.md §1.3).
///   Implies `--demo`.
/// - `--demo-automation denied|undetermined|granted`: what the demo's Status
///   page says macOS answered for Music and Spotify (DESIGN.md §6.3), so each
///   state can be seen without changing a real permission. Implies `--demo`.
/// - `--appearance light|dark`: force an appearance.
/// - `--player-size N`: open the player N points square.
/// - `--reveal-controls`: keep the Now controls revealed.
/// - `--surface now|echo|status`: open on a surface. `play` and `find`, the
///   surfaces that were removed, open on Now.
/// - `--reset-window`: ignore remembered window placement.
/// - `--settings <pane>`: open Settings on a pane after launch (`general`,
///   `appearance`, `player`, `shortcuts`, `sources`, `echoPrivacy`, `about`).
/// - `--style <id>`: start the demo in a player style. Only the demo's own
///   settings change; without `--demo` it's ignored.
/// - `--pin <position>`: pin the player to one of the nine positions, by its
///   stored name (`topLeft`, `top`, … `bottomRight`).
/// - `--slow-motion N` (debug builds only): style switches run N times slower,
///   so a frame from the middle of one can be captured. Release builds don't
///   know the flag.
public struct LaunchOptions: Equatable, Sendable {
    public var demo = false
    public var demoStartsPlaying = false
    public var demoHistory = false
    /// The demo device that starts out playing, by name.
    public var demoDevice: String?
    /// The service the demo names as the source of its songs.
    public var demoAttribution: String?
    /// What the demo's Status page shows for every app's Automation permission.
    public var demoAutomation: AutomationPermission?
    public var appearance: AppearanceMode?
    public var playerSize: Double?
    public var revealControls = false
    public var surface: Surface?
    public var resetWindow = false
    /// The Settings pane to open after launch, as its raw value.
    public var settingsPane: String?
    /// The style the demo starts in.
    public var style: PlayerStyleID?
    /// Where to pin the player.
    public var pin: PinPosition?
    #if DEBUG
    /// How many times slower style switches run.
    public var slowMotion: Double?
    #endif

    public init() {}

    public init(arguments: [String], environment: [String: String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--demo":
                demo = true
            case "--demo-playing":
                demo = true
                demoStartsPlaying = true
            case "--demo-history":
                demo = true
                demoHistory = true
            case "--demo-device":
                demo = true
                demoDevice = iterator.next()
            case "--demo-attribution":
                demo = true
                demoAttribution = iterator.next()
            case "--demo-automation":
                demo = true
                demoAutomation = iterator.next().flatMap(Self.demoAutomation(named:))
            case "--appearance":
                appearance = iterator.next().flatMap(AppearanceMode.init(rawValue:))
            case "--player-size":
                playerSize = iterator.next().flatMap(Double.init).map { max(1, $0) }
            case "--reveal-controls":
                revealControls = true
            case "--surface":
                surface = iterator.next().flatMap(Surface.init(storedValue:))
            case "--reset-window":
                resetWindow = true
            case "--settings":
                settingsPane = iterator.next()
            case "--style":
                style = iterator.next().flatMap(PlayerStyleID.init(rawValue:))
            case "--pin":
                pin = iterator.next().flatMap(PinPosition.init(rawValue:))
            #if DEBUG
            case "--slow-motion":
                slowMotion = iterator.next().flatMap(Double.init).map { max(1, $0) }
            #endif
            default:
                continue
            }
        }
        if let flag = environment["HUM_DEMO"], ["1", "true", "yes"].contains(flag.lowercased()) {
            demo = true
        }
    }

    /// The permissions `--demo-automation` takes, by the word macOS's own
    /// states go by.
    static func demoAutomation(named name: String) -> AutomationPermission? {
        switch name {
        case "denied": .denied
        case "undetermined": .notDetermined
        case "granted": .granted
        default: nil
        }
    }

    public static var current: LaunchOptions {
        LaunchOptions(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
    }
}
