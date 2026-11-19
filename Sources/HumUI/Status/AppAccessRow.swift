import HumCore

/// One app on Status's Apps card, and whether Hum may control it (DESIGN.md
/// §6.3). Pure, so each state's words, glyph and button can be tested.
nonisolated struct AppAccessRow: Equatable, Sendable, Identifiable {
    /// A music app Hum supports, in the order Status lists them.
    struct App: Equatable, Sendable {
        var id: SourceID
        var name: String
        /// Where Status finds the app and its own icon (§3.5.7).
        var bundleIdentifier: String
    }

    enum Access: Equatable, Sendable {
        case allowed
        case notAllowed
        case notAsked
        /// macOS reports an app's permission only while the app runs, and Hum
        /// never opens an app on its own to ask.
        case notOpen
        case notInstalled
    }

    enum Action: Equatable, Sendable {
        /// Privacy & Security › Automation in System Settings.
        case openSystemSettings
        /// macOS's own prompt, asked for only on a click.
        case allow
    }

    /// The glyph before the state, and its color.
    struct Glyph: Equatable, Sendable {
        enum Tint: Equatable, Sendable {
            case secondaryLabel, warning, tertiaryLabel
        }

        var symbol: String
        var tint: Tint
    }

    static let music = App(id: .musicApp, name: "Music", bundleIdentifier: "com.apple.Music")
    static let spotify = App(id: .spotifyApp, name: "Spotify", bundleIdentifier: "com.spotify.client")
    /// Music, then Spotify.
    static let apps = [music, spotify]

    var app: App
    var access: Access

    var id: SourceID { app.id }

    /// The row for `app`. A source Hum runs reports its own state; the demo
    /// shows the apps as installed on this Mac with `demoPermission` for each;
    /// an app Hum has no source for can only be installed or not.
    static func make(
        _ app: App,
        state: SourceState?,
        isInstalled: Bool,
        demoPermission: AutomationPermission? = nil
    ) -> AppAccessRow {
        let access: Access
        if let demoPermission {
            access = isInstalled ? Self.access(availability: .running, permission: demoPermission) : .notInstalled
        } else if let state {
            access = Self.access(availability: state.availability, permission: state.permission)
        } else {
            access = isInstalled ? .notOpen : .notInstalled
        }
        return AppAccessRow(app: app, access: access)
    }

    /// What Status says for an app in `availability` with `permission`. A
    /// decision learned while the app ran outlives it; an app that's closed
    /// can't be asked, so with nothing learned it's Not open.
    static func access(availability: SourceAvailability, permission: AutomationPermission) -> Access {
        switch (availability, permission) {
        case (.notInstalled, _): .notInstalled
        case (_, .granted), (_, .notRequired): .allowed
        case (_, .denied): .notAllowed
        case (.notRunning, _): .notOpen
        // An open app that hasn't answered yet can still be asked; macOS
        // answers at once if the user already decided.
        case (.running, .notDetermined), (.running, .unknown): .notAsked
        }
    }

    var statusText: String {
        switch access {
        case .allowed: "Allowed"
        case .notAllowed: "Not allowed"
        case .notAsked: "Not asked yet"
        case .notOpen: "Not open"
        case .notInstalled: "Not installed"
        }
    }

    /// No green for Allowed (§3.5.6); Not open and Not installed have none.
    var glyph: Glyph? {
        switch access {
        case .allowed: Glyph(symbol: "checkmark.circle.fill", tint: .secondaryLabel)
        case .notAllowed: Glyph(symbol: "exclamationmark.triangle.fill", tint: .warning)
        case .notAsked: Glyph(symbol: "questionmark.circle", tint: .tertiaryLabel)
        case .notOpen, .notInstalled: nil
        }
    }

    var action: Action? {
        switch access {
        case .notAllowed: .openSystemSettings
        case .notAsked: .allow
        case .allowed, .notOpen, .notInstalled: nil
        }
    }

    var actionTitle: String? {
        switch action {
        case .openSystemSettings: "Open System Settings…"
        case .allow: "Allow…"
        case nil: nil
        }
    }

    /// Not installed dims the row and takes the generic glyph.
    var isDimmed: Bool { access == .notInstalled }

    /// The row as VoiceOver reads it: "Spotify, not allowed".
    var accessibilityLabel: String {
        "\(app.name), \(statusText.lowercased())"
    }
}

extension AppAccessRow {
    /// Status's rows for `store`, Music then Spotify. The demo shows the apps
    /// on this Mac with `demoAutomation`'s permission, Allowed without it, and
    /// Allowed for any whose Allow… was clicked.
    @MainActor
    static func rows(
        in store: NowPlayingStore,
        installed: Set<SourceID>,
        demoAutomation: AutomationPermission?,
        demoAllowed: Set<SourceID>
    ) -> [AppAccessRow] {
        let isDemo = store.source(for: .demo) != nil
        return apps.map { app in
            let demoPermission: AutomationPermission? = isDemo
                ? (demoAllowed.contains(app.id) ? .granted : demoAutomation ?? .granted)
                : nil
            return make(
                app,
                state: store.sourceStates[app.id] ?? store.source(for: app.id)?.state,
                isInstalled: installed.contains(app.id),
                demoPermission: demoPermission
            )
        }
    }

    /// Asks each app's source what macOS says now, without prompting. The
    /// demo asks nothing.
    @MainActor
    static func refreshPermissions(in store: NowPlayingStore) async {
        guard store.source(for: .demo) == nil else { return }
        for source in apps.compactMap({ store.source(for: $0.id) }) {
            await source.refreshAutomationPermission()
        }
    }
}

/// Status's Connected to card: the app Hum follows and what it's doing
/// (DESIGN.md §6.3).
nonisolated struct StatusConnection: Equatable, Sendable {
    enum Icon: Equatable, Sendable {
        /// The app's own icon, from its bundle: Music's or Spotify's
        /// (§3.5.7), or the generic one if the app is gone.
        case app(bundleIdentifier: String)
        /// The system's generic application icon.
        case generic
        /// Hum's own icon, for the demo.
        case hum
    }

    var icon: Icon?
    var name: String
    var status: String
    /// "Chosen automatically", when Settings › Sources is Automatic.
    var caption: String?

    static let noApp = StatusConnection(
        icon: nil,
        name: "No Music App",
        status: "Install Music or Spotify, or open one of them.",
        caption: nil
    )

    /// The card for the source Hum follows, or `noApp` when there's none it
    /// could follow.
    static func make(
        sourceID: SourceID?,
        displayName: String?,
        state: SourceState?,
        isAutomatic: Bool
    ) -> StatusConnection {
        guard let sourceID, let state, state.availability.isInstalled else { return .noApp }
        let name: String
        let icon: Icon
        switch sourceID {
        case .demo:
            name = "Demo"
            icon = .hum
        case AppAccessRow.music.id:
            name = AppAccessRow.music.name
            icon = .app(bundleIdentifier: AppAccessRow.music.bundleIdentifier)
        case AppAccessRow.spotify.id:
            name = AppAccessRow.spotify.name
            icon = .app(bundleIdentifier: AppAccessRow.spotify.bundleIdentifier)
        default:
            name = displayName ?? "Music App"
            icon = .generic
        }
        return StatusConnection(
            icon: icon,
            name: name,
            status: Self.status(state),
            caption: isAutomatic ? "Chosen automatically" : nil
        )
    }

    /// "Playing", "Paused", "Open, nothing playing", "Not open" or "Not
    /// installed".
    static func status(_ state: SourceState) -> String {
        switch state.availability {
        case .notInstalled: "Not installed"
        case .notRunning: "Not open"
        case .running:
            if state.snapshot.status.isPlaying {
                "Playing"
            } else if state.snapshot.track != nil {
                "Paused"
            } else {
                "Open, nothing playing"
            }
        }
    }
}
