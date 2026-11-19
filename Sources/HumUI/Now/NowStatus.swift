import HumCore

/// What the Now surface should show instead of (or alongside) a track.
nonisolated enum NowStatus: Equatable, Sendable {
    /// A track to show. Controls appear on hover.
    case ready
    /// Neither music app is installed.
    case noSources
    case notRunning(app: String)
    /// The app is starting because the user pressed play.
    case launching(app: String)
    /// macOS hasn't asked yet whether Hum may control the app.
    case permissionNeeded(app: String)
    case permissionDenied(app: String)
    /// The app is open but has nothing loaded.
    case nothingPlaying(app: String)

    static func resolve(
        appName: String?,
        availability: SourceAvailability,
        permission: AutomationPermission,
        hasTrack: Bool,
        isLaunching: Bool
    ) -> NowStatus {
        guard let appName else { return .noSources }
        if isLaunching { return .launching(app: appName) }
        switch availability {
        case .notInstalled:
            return .noSources
        case .notRunning:
            return .notRunning(app: appName)
        case .running:
            // A track is still worth showing without control: the notifications
            // that report it need no permission.
            if hasTrack { return .ready }
            switch permission {
            case .denied: return .permissionDenied(app: appName)
            case .notDetermined: return .permissionNeeded(app: appName)
            case .notRequired, .unknown, .granted: return .nothingPlaying(app: appName)
            }
        }
    }
}

extension NowStatus {
    @MainActor
    init(_ store: NowPlayingStore) {
        self = .resolve(
            appName: store.activeSource?.displayName,
            availability: store.availability,
            permission: store.permission,
            hasTrack: store.track != nil,
            isLaunching: store.isLaunching
        )
    }
}
