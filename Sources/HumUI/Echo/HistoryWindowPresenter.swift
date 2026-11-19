import AppKit
import HumCore
import Observation
import SwiftUI

/// Opens the Listening History window: a standard window with a sidebar, built
/// from the same services as every other window.
///
/// Provided through `AppServices`, so any view can open it:
/// `@Environment(HistoryWindowPresenter.self) private var historyWindow: HistoryWindowPresenter?`.
@MainActor
@Observable
public final class HistoryWindowPresenter {
    /// The section showing in the window.
    public var section: HistorySection = .thisWeek
    /// Whether the sidebar shows. The window opens with it collapsed, for more
    /// room (DESIGN.md §6.5), and keeps what people choose while Hum runs.
    public var columnVisibility = HistoryWindowPresenter.initialColumnVisibility

    nonisolated static let initialColumnVisibility = NavigationSplitViewVisibility.detailOnly

    @ObservationIgnored private let history: ListeningHistory
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let store: NowPlayingStore
    @ObservationIgnored private let actions: PlayerActions
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var window: NSWindow?

    public init(
        history: ListeningHistory,
        settings: SettingsStore,
        store: NowPlayingStore,
        actions: PlayerActions,
        services: AppServices
    ) {
        self.history = history
        self.settings = settings
        self.store = store
        self.actions = actions
        self.services = services
        #if DEBUG
        // Screenshots: `HUM_DEBUG_OPEN_HISTORY=thisWeek|calendar|history|top|rediscover`.
        if let name = ProcessInfo.processInfo.environment["HUM_DEBUG_OPEN_HISTORY"],
           let section = HistorySection(rawValue: name) {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.show(section: section)
            }
        }
        #endif
    }

    public func show(section: HistorySection? = nil) {
        if let section { self.section = section }
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let content = services.inject(
            HistoryWindowView()
                .modifier(AccentTransition())
                .environment(self)
                .environment(history)
                .environment(settings)
                .environment(store)
                .environment(\.playerActions, actions)
                .environment(\.playerMetrics, PlayerMetrics(side: PlayerMetrics.maximumSide))
        )
        let controller = NSHostingController(rootView: content)
        // The window keeps the size people give it; only its minimum comes from
        // the content.
        controller.sizingOptions = [.minSize]
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: HistoryWindowView.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Listening History"
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(HistoryWindowView.defaultSize)
        window.contentMinSize = HistoryWindowView.minimumSize
        // The demo keeps nothing outside its own folder, window frames included.
        if LaunchOptions.current.demo {
            ClearOfPlayer.center(window)
        } else {
            window.setFrameAutosaveName("ListeningHistory")
            if !window.setFrameUsingName("ListeningHistory") { ClearOfPlayer.center(window) }
        }
        let launchAppearance = LaunchOptions.current.appearance
        observeChanges { [weak self, weak window] in
            guard let self, let window else { return }
            // Follows Hum's Light, Dark, or System choice, like the player.
            window.appearance = switch launchAppearance ?? self.settings.appearance.mode {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
        return window
    }
}

/// The History window's sidebar sections.
public enum HistorySection: String, CaseIterable, Identifiable, Sendable {
    case thisWeek, calendar, history, top, rediscover

    public var id: Self { self }

    public var title: String {
        switch self {
        case .thisWeek: "This Week"
        case .calendar: "Calendar"
        case .history: "History"
        case .top: "Top"
        case .rediscover: "Rediscover"
        }
    }

    public var systemImage: String {
        switch self {
        case .thisWeek: "doc.plaintext"
        case .calendar: "calendar"
        case .history: "clock"
        case .top: "list.number"
        case .rediscover: "arrow.uturn.backward.circle"
        }
    }
}
