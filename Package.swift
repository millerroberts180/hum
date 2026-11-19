// swift-tools-version: 6.2
import Foundation
import PackageDescription

/// Swift 6.2 "approachable concurrency": `async` functions stay on the caller's actor
/// unless marked `@concurrent`, and conformances infer the conforming type's isolation.
let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

/// UI-facing modules run on the main actor by default.
let mainActorByDefault: [SwiftSetting] = approachableConcurrency + [
    .defaultIsolation(MainActor.self),
]

/// The Command Line Tools ship Swift Testing outside the default framework search
/// path. When the active developer directory is the CLT (no Xcode.app selected),
/// point the test target at it so a plain `swift test` works. With Xcode selected,
/// nothing is added and Xcode's own copy is used.
let commandLineToolsFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
/// Same order `xcode-select -p` uses: the environment, then the selected path, then
/// Xcode if it is installed, and the Command Line Tools otherwise.
let activeDeveloperDirectory = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))
    ?? (FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
        ? "/Applications/Xcode.app/Contents/Developer"
        : "/Library/Developer/CommandLineTools")
let usesCommandLineTools = activeDeveloperDirectory.contains("CommandLineTools")
    && FileManager.default.fileExists(atPath: commandLineToolsFrameworks + "/Testing.framework")

// The CLT copy of Swift Testing's Foundation overlay ships without a module
// interface, so cross-import overlays are turned off for the tests (they use
// nothing from it).
let testingSearchPaths: [SwiftSetting] = usesCommandLineTools
    ? [.unsafeFlags(["-F", commandLineToolsFrameworks, "-Xfrontend", "-disable-cross-import-overlays"])]
    : []
let testingLinkerPaths: [LinkerSetting] = usesCommandLineTools
    ? [.unsafeFlags(["-F", commandLineToolsFrameworks, "-Xlinker", "-rpath", "-Xlinker", commandLineToolsFrameworks])]
    : []

let package = Package(
    name: "Hum",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Hum", targets: ["Hum"]),
        .executable(name: "HumWidgets", targets: ["HumWidgets"]),
    ],
    targets: [
        // Models, the playback-source protocol, stores, settings, artwork cache.
        // No AppKit or SwiftUI: everything here is testable without a window.
        .target(
            name: "HumCore",
            swiftSettings: approachableConcurrency
        ),
        // Concrete playback sources: Spotify.app, Music.app, and the demo source.
        .target(
            name: "HumSources",
            dependencies: ["HumCore"],
            swiftSettings: approachableConcurrency
        ),
        // The player window, surfaces, shared components, and design tokens.
        // Depends only on HumCore so it never knows which source is playing.
        .target(
            name: "HumUI",
            dependencies: ["HumCore"],
            swiftSettings: mainActorByDefault
        ),
        // The menu-bar agent: composition root, menu, global shortcut.
        .executableTarget(
            name: "Hum",
            dependencies: ["HumCore", "HumSources", "HumUI"],
            swiftSettings: mainActorByDefault,
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        // The widget extension (DESIGN.md §7.3): one widget per display, drawn
        // from the snapshot Hum writes. Its `@main` is a `WidgetBundle`, whose
        // `main()` starts the extension. scripts/build-app.sh links it as an app
        // extension and wraps it in Hum.app/Contents/PlugIns/HumWidgets.appex.
        // Restricted to the APIs app extensions may use.
        .executableTarget(
            name: "HumWidgets",
            dependencies: ["HumCore"],
            swiftSettings: approachableConcurrency + [.unsafeFlags(["-application-extension"])]
        ),
        .testTarget(
            name: "HumTests",
            dependencies: ["HumCore", "HumSources", "HumUI", "Hum", "HumWidgets"],
            swiftSettings: approachableConcurrency + testingSearchPaths,
            linkerSettings: testingLinkerPaths
        ),
    ],
    swiftLanguageModes: [.v6]
)
