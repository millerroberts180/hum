import HumCore
import SwiftUI

/// What Now shows when there's no track: why, and the one thing to do about it,
/// as the shared `EmptyState` (§5.5).
struct NowEmptyState: View {
    var status: NowStatus
    /// The blurred placeholder behind it. Wide and Big Art leave it out, so
    /// the state sits on their card (§7).
    var drawsBackdrop = true

    @Environment(NowPlayingStore.self) private var store

    var body: some View {
        let content = EmptyStateContent(status)
        let state = EmptyState(
            symbol: content.symbol,
            title: content.title,
            message: content.message,
            action: content.action.map { action in
                EmptyState.Action(title: action.title) { perform(action) }
            }
        )
        Group {
            if content.showsSpinner {
                // Opening an app is ongoing, so the spinner shows after 400 ms
                // in place of an action (§4.6).
                VStack(spacing: Spacing.s) {
                    state.fixedSize(horizontal: false, vertical: true)
                    DelayedSpinner()
                }
            } else {
                state
            }
        }
        .disabled(store.isRequestingPermission)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if drawsBackdrop {
                ArtBackdrop(artwork: nil)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func perform(_ action: EmptyStateContent.Action) {
        switch action {
        case .play:
            store.send(.play)
        case .requestPermission:
            Task { await store.requestPermission() }
        case .openSettings:
            PermissionGuide.openAutomationSettings()
        }
    }
}

/// The words and the single action for each empty state.
nonisolated struct EmptyStateContent: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case play
        case requestPermission
        case openSettings

        var title: String {
            switch self {
            case .play: "Play"
            case .requestPermission: "Continue"
            case .openSettings: "Open System Settings"
            }
        }
    }

    var symbol: String
    var title: String
    var message: String?
    var action: Action?
    var showsSpinner = false

    /// Now never names the music app (DESIGN.md §6.2, §10).
    static let nothingPlayingTitle = "Nothing Playing"
    static let nothingPlayingMessage = "Start music in your music app."

    init(_ status: NowStatus) {
        switch status {
        case .ready, .nothingPlaying, .noSources:
            symbol = HumIcon.musicNote
            title = Self.nothingPlayingTitle
            message = Self.nothingPlayingMessage
            if case .nothingPlaying = status {
                action = .play
            } else {
                action = nil
            }
        case .notRunning:
            symbol = HumIcon.playCircle
            title = Self.nothingPlayingTitle
            message = "Press Play to open your music app and pick up where you left off."
            action = .play
        case .launching:
            symbol = HumIcon.playCircle
            title = "Opening Your Music App…"
            showsSpinner = true
        case .permissionNeeded:
            symbol = HumIcon.permission
            title = PermissionGuide.playerNeededTitle
            message = PermissionGuide.playerNeededMessage
            action = .requestPermission
        case .permissionDenied:
            symbol = HumIcon.permission
            title = PermissionGuide.playerDeniedTitle
            message = PermissionGuide.playerDeniedMessage
            action = .openSettings
        }
    }
}

#if DEBUG
struct NowEmptyState_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreviewGallery { NowEmptyState(status: .nothingPlaying(app: "Music")) }
            PreviewGallery(cases: [.smallLight, .largeDark]) { NowEmptyState(status: .notRunning(app: "Music")) }
            PreviewGallery(cases: [.smallLight, .largeDark]) { NowEmptyState(status: .permissionDenied(app: "Spotify")) }
            PreviewGallery(cases: [.smallLight, .largeDark]) { NowEmptyState(status: .noSources) }
        }
    }
}
#endif
