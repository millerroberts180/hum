/// Everything the store needs to know about one source.
public struct SourceState: Equatable, Sendable {
    public var availability: SourceAvailability
    public var permission: AutomationPermission
    /// What the source supports. The UI should read `effectiveCapabilities`, which
    /// accounts for permission and availability.
    public var capabilities: SourceCapabilities
    public var snapshot: PlaybackSnapshot

    public init(
        availability: SourceAvailability,
        permission: AutomationPermission,
        capabilities: SourceCapabilities,
        snapshot: PlaybackSnapshot = .empty
    ) {
        self.availability = availability
        self.permission = permission
        self.capabilities = capabilities
        self.snapshot = snapshot
    }

    public static let notInstalled = SourceState(
        availability: .notInstalled,
        permission: .unknown,
        capabilities: []
    )

    public var hasTrack: Bool { snapshot.track != nil }
    public var isPlaying: Bool { availability.isRunning && snapshot.status.isPlaying }

    /// Capabilities the user can act on right now.
    ///
    /// While permission hasn't been decided, controls stay visible: pressing one is
    /// how the user asks to be prompted. When it's denied, everything but play is
    /// hidden so the permission explanation has room. When the app isn't running,
    /// only play remains, and only for sources that can launch their app.
    public var effectiveCapabilities: SourceCapabilities {
        switch availability {
        case .notInstalled:
            return []
        case .notRunning:
            return capabilities.contains(.launch) ? [.playPause, .launch] : []
        case .running:
            if permission == .denied { return [] }
            return capabilities
        }
    }
}
