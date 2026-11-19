import Foundation
import HumCore
import Testing

/// What build-app.sh puts in the bundle: Info.plist, the icon, Help, and the
/// widget extension.
@Suite("App bundle resources")
struct AppBundleResourceTests {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Shell
        .deletingLastPathComponent() // HumTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent()
    static let resources = repository.appendingPathComponent("Resources")

    private func infoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.resources.appendingPathComponent("Info.plist"))
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func infoPlistNamesTheVersionCopyrightAndIcon() throws {
        let info = try infoPlist()
        let version = try #require(info["CFBundleShortVersionString"] as? String)
        #expect(version.wholeMatch(of: /[0-9]+(\.[0-9]+){0,2}/) != nil)
        #expect(info["CFBundleVersion"] is String, "build-app.sh stamps over it")
        #expect(info["NSHumanReadableCopyright"] as? String == "© 2026 Miller Roberts")
        #expect(info["CFBundleIconFile"] as? String == "AppIcon")
        #expect(FileManager.default.fileExists(atPath: Self.resources.appendingPathComponent("AppIcon.icns").path))
        #expect(info["CFBundleIdentifier"] as? String == AppDirectories.bundleIdentifier)
    }

    /// build-app.sh makes a universal app, so the system picks the slice for
    /// the Mac it runs on, from the macOS that Package.swift builds for.
    @Test func infoPlistRunsOnAppleSiliconAndIntel() throws {
        let info = try infoPlist()
        #expect(info["LSArchitecturePriority"] == nil)
        let platform = try #require(try Self.file("Package.swift").firstMatch(of: /\.macOS\(\.v(\d+)\)/))
        #expect(info["LSMinimumSystemVersion"] as? String == "\(platform.1).0")
    }

    @Test func theAutomationPromptExplainsBothApps() throws {
        let reason = try #require(try infoPlist()["NSAppleEventsUsageDescription"] as? String)
        #expect(reason.contains("Spotify"))
        #expect(reason.contains("Music"))
        // Hum's library and playlists were removed (DESIGN.md §13.9).
        #expect(!reason.localizedCaseInsensitiveContains("library"))
        #expect(!reason.localizedCaseInsensitiveContains("playlist"))
        // DESIGN.md §10: plain and factual, with typographic punctuation.
        #expect(!reason.contains("!"))
        #expect(Self.straightPunctuation(in: reason).isEmpty)
    }

    /// The Help page is the guide's "Using Hum" section; their key tables match.
    @Test func helpListsTheSameKeysAsTheGuide() throws {
        let guide = try Self.file("docs/guide.md")
        let help = try String(contentsOf: Self.resources.appendingPathComponent("Help/index.html"), encoding: .utf8)

        let section = try #require(guide.components(separatedBy: "\n## Using Hum\n").dropFirst().first)
            .components(separatedBy: "\n## ").first ?? ""
        let guideRows = section.split(separator: "\n")
            .filter { $0.hasPrefix("| ") && !$0.hasPrefix("| Keys") && !$0.hasPrefix("| ---") }
            .map { line in
                line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            }
        let helpRows = help.matches(of: /<tr><td>(.+?)<\/td><td>(.+?)<\/td><\/tr>/).map { match in
            [String(match.1), String(match.2)].map {
                $0.replacing(/<\/?kbd>/, with: "").replacingOccurrences(of: "&amp;", with: "&")
            }
        }
        #expect(!guideRows.isEmpty)
        #expect(guideRows == helpRows)
    }

    private static func file(_ path: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent(path), encoding: .utf8)
    }

    /// Straight quotes and three dots in `text`, which DESIGN.md §10 sets as
    /// ’ “ ” and …, and → in a settings path, which it sets as ›.
    private static func straightPunctuation(in text: String) -> [String] {
        text.matches(of: /['"]|\.\.\.|Settings →/).map { String($0.output) }
    }

    /// The pages a reader sees on GitHub: the README and the guides beside it.
    private static let readerDocs = ["README.md", "docs/guide.md", "docs/development.md"]

    /// What a reader sees of a Markdown page: everything but its code and markup.
    private static func prose(_ path: String) throws -> String {
        try file(path)
            .replacing(/(?s)```.*?```/, with: "")
            .replacing(/`[^`\n]*`/, with: "")
            .replacing(/(?s)<!--.*?-->/, with: "")
            .replacing(/<[^>\n]+>/, with: "")
    }

    /// What a reader sees of the Help page: its text, without markup or style.
    private static func helpText() throws -> String {
        try String(contentsOf: resources.appendingPathComponent("Help/index.html"), encoding: .utf8)
            .replacing(/(?s)<style>.*?<\/style>/, with: "")
            .replacing(/(?s)<!--.*?-->/, with: "")
            .replacing(/<[^>]+>/, with: "")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    @Test func theDocsAndHelpUseTypographicPunctuation() throws {
        for path in Self.readerDocs {
            #expect(Self.straightPunctuation(in: try Self.prose(path)) == [], "\(path)")
        }
        #expect(Self.straightPunctuation(in: try Self.helpText()) == [])
        #expect(try Self.helpText().contains("Settings › Shortcuts"))
    }

    /// Every file the README and the guides link to or show is in the repository.
    @Test func theDocsLinkToFilesThatExist() throws {
        for path in Self.readerDocs {
            let text = try Self.file(path)
            let folder = Self.repository.appendingPathComponent(path).deletingLastPathComponent()
            let targets = text.matches(of: /\]\(([^)#\s]+)[^)]*\)/).map { String($0.1) }
                + text.matches(of: /(?:src|srcset)="([^"]+)"/).map { String($0.1) }
            #expect(!targets.isEmpty, "\(path)")
            for target in targets where !target.hasPrefix("http") {
                let url = folder.appendingPathComponent(target).standardizedFileURL
                #expect(FileManager.default.fileExists(atPath: url.path), "\(path) → \(target)")
            }
        }
    }

    /// Every key in DESIGN.md §4.3's table is in Help's (and so the guide's).
    @Test func helpListsEveryKeyInTheDesign() throws {
        let section = try #require(try Self.file("docs/DESIGN.md")
            .components(separatedBy: "\n### 4.3 Keyboard\n").dropFirst().first)
            .components(separatedBy: "\n### ").first ?? ""
        let designKeys = section.split(separator: "\n")
            .filter { $0.hasPrefix("| ") && !$0.hasPrefix("| Keys") && !$0.hasPrefix("| ---") }
            .compactMap { $0.split(separator: "|").first }
            .flatMap { $0.matches(of: /[⌘⌥⇧⌃]+[A-Z0-9,←→↑↓↩]|[←→↑↓↩]|\bSpace\b|\bEsc\b/).map { String($0.output) } }
        let help = try String(contentsOf: Self.resources.appendingPathComponent("Help/index.html"), encoding: .utf8)
        let helpKeys = help.matches(of: /<tr><td>(.+?)<\/td><td>/)
            .map { String($0.1).replacing(/<\/?kbd>/, with: "") }
            .joined(separator: " ")
        #expect(designKeys.count > 10)
        #expect(designKeys.filter { !helpKeys.contains($0) } == [])
        // Show/Hide Player has no default key, so Help names the action instead.
        #expect(help.contains("<td>Show or hide the player from anywhere"))
    }

    // MARK: The widget extension

    private static let widgets = resources.appendingPathComponent("HumWidgets")

    private static func plist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// The widgets' buttons are `hum://` links (DESIGN.md §7.3), so Hum claims
    /// the scheme.
    @Test func humDeclaresTheHumURLScheme() throws {
        let types = try #require(try infoPlist()["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes == [HumURLAction.scheme])
        #expect(types.first?["CFBundleURLName"] as? String == AppDirectories.bundleIdentifier)
    }

    @Test func theWidgetExtensionDeclaresTheWidgetKitExtensionPoint() throws {
        let info = try Self.plist(Self.widgets.appendingPathComponent("Info.plist"))
        let ext = try #require(info["NSExtension"] as? [String: Any])
        #expect(ext["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension")
        #expect(info["CFBundlePackageType"] as? String == "XPC!")
        #expect(info["CFBundleExecutable"] as? String == "HumWidgets")
        // An extension's identifier extends its app's.
        #expect(info["CFBundleIdentifier"] as? String == AppDirectories.bundleIdentifier + ".widgets")
        #expect(info["CFBundleDisplayName"] as? String == "Hum")
        #expect(info["LSMinimumSystemVersion"] as? String == (try infoPlist()["LSMinimumSystemVersion"] as? String))
        #expect(info["CFBundleShortVersionString"] is String && info["CFBundleVersion"] is String, "build-app.sh stamps over them")
    }

    /// Sandboxed, as WidgetKit requires, and able to read one folder: the one
    /// Hum writes the snapshot into.
    @Test func theWidgetExtensionIsSandboxedAndReadsOnlyTheWidgetFolder() throws {
        let entitlements = try Self.plist(Self.widgets.appendingPathComponent("HumWidgets.entitlements"))
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        let readable = entitlements["com.apple.security.temporary-exception.files.home-relative-path.read-only"] as? [String]
        #expect(readable == ["/" + WidgetFiles.relativePath + "/"])
        #expect(entitlements.count == 2, "\(entitlements.keys.sorted())")
    }

    /// Apps build-app.sh made from these resources: `build*/Hum.app` built since
    /// the extension's Info.plist or build-app.sh last changed, so an older
    /// build is passed over.
    static let builtApps: [URL] = {
        let fileManager = FileManager.default
        let since = [widgets.appendingPathComponent("Info.plist"), repository.appendingPathComponent("scripts/build-app.sh")]
            .compactMap { (try? fileManager.attributesOfItem(atPath: $0.path)[.modificationDate]) as? Date }
            .max()
        let folders = (try? fileManager.contentsOfDirectory(atPath: repository.path)) ?? []
        return folders.filter { $0.hasPrefix("build") }.sorted().compactMap { folder in
            let app = repository.appendingPathComponent(folder).appendingPathComponent("Hum.app")
            let info = app.appendingPathComponent("Contents/Info.plist")
            guard let built = (try? fileManager.attributesOfItem(atPath: info.path)[.modificationDate]) as? Date,
                let since, built >= since
            else { return nil }
            return app
        }
    }()

    @Test(.enabled(if: !builtApps.isEmpty, "no app built from these resources"))
    func aBuiltAppCarriesItsSignedWidgetExtension() throws {
        for app in Self.builtApps {
            let appex = app.appendingPathComponent("Contents/PlugIns/HumWidgets.appex")
            let info = try Self.plist(appex.appendingPathComponent("Contents/Info.plist"))
            let ext = try #require(info["NSExtension"] as? [String: Any], "\(app.path)")
            #expect(ext["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension")
            #expect(info["CFBundleVersion"] as? String == (try Self.plist(app.appendingPathComponent("Contents/Info.plist"))["CFBundleVersion"] as? String))
            let binary = try Data(contentsOf: appex.appendingPathComponent("Contents/MacOS/HumWidgets"))
            // The signature carries the sandbox entitlement.
            #expect(binary.range(of: Data("com.apple.security.app-sandbox".utf8)) != nil, "\(app.path)")
            // It starts at Foundation's NSExtensionMain, so it imports it;
            // started at its own `main`, it exits before WidgetKit asks for its
            // widgets.
            #expect(binary.range(of: Data("_NSExtensionMain".utf8)) != nil, "\(app.path)")
            #expect(FileManager.default.fileExists(atPath: appex.appendingPathComponent("Contents/_CodeSignature/CodeResources").path))
            #expect(!FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/HumWidgets").path))
            let built = try Self.plist(app.appendingPathComponent("Contents/Info.plist"))
            let types = built["CFBundleURLTypes"] as? [[String: Any]] ?? []
            #expect(types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } == [HumURLAction.scheme])
        }
    }

    @Test func logCategoriesShareTheAppSubsystem() {
        #expect(HumLog.subsystem == "com.millerroberts.hum")
        #expect(HumLog.Category.allCases.map(\.rawValue) == ["sources", "library", "history", "window", "app"])
    }
}
