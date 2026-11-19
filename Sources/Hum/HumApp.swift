import AppKit
import HumCore
import HumSources
import HumUI

/// The composition root: builds the stores, sources, player, menu, and global
/// shortcuts, and keeps settings and the store in step.
final class HumApp {
    let launchOptions: LaunchOptions
    let settings: SettingsStore
    let store: NowPlayingStore
    /// Feature objects (library, listening history) every window's views can read.
    let services = AppServices()
    /// Save, devices, and Echo's Play Now for the active source.
    let library: LibraryStore
    private(set) var player: PlayerWindowController!
    private let history: ListeningHistory
    private var historyWindow: HistoryWindowPresenter!
    private var historySleep: HistorySleepObserver?
    private var settingsWindow: SettingsWindowPresenter!
    private var menuBar: MenuBarController!
    /// The Menu Bar style's popover, once the menu-bar item has made it, so
    /// Show can tell whether it's already open.
    private weak var menuBarPopover: MenuBarPopover?
    /// What the widgets show, written as it changes (DESIGN.md §7.3).
    private var widgetSnapshot: WidgetSnapshotWriter!
    private let hotKeys = GlobalHotKeyCenter()
    /// Which global shortcuts macOS turned down, for the shortcut recorders.
    private let shortcutStatus = GlobalShortcutStatus()

    init(launchOptions: LaunchOptions = .current) {
        self.launchOptions = launchOptions
        let directories = AppDirectories.standard
        settings = SettingsStore(fileURL: directories.settingsFile(demo: launchOptions.demo))
        // `--style` changes only the demo's own settings.
        if launchOptions.demo, let style = launchOptions.style {
            settings.appearance.style = style
        }
        // Demo artwork is generated on the fly; there's nothing worth keeping on disk.
        let artworkCache = ArtworkCache(directory: launchOptions.demo ? nil : directories.artworkCache)
        store = NowPlayingStore(
            sources: Self.makeSources(launchOptions),
            artworkCache: artworkCache,
            preferredSourceID: settings.playback.preferredSource,
            lastActiveSourceID: settings.playback.lastActiveSource
        )
        // The demo keeps its own history file, so it never mixes with real listening.
        let historyStore = HistoryStore.openOrFallback(url: directories.historyDatabase(demo: launchOptions.demo))
        history = ListeningHistory(
            store: historyStore.store,
            nowPlaying: store,
            settings: settings,
            artworkCache: artworkCache,
            storageProblem: historyStore.problem
        )
        if launchOptions.demoHistory {
            Self.seedDemoHistory(history, namesContexts: !DemoAttribution.namesSpotify(launchOptions.demoAttribution))
        } else if launchOptions.demo {
            Self.fillDemoArtwork(history)
        }
        services.provide(history)
        library = Self.makeLibrary(store: store, options: launchOptions, directories: directories)
        services.provide(library)
        services.provide(shortcutStatus)
        services.provide(\.demoAttribution, launchOptions.demoAttribution)

        let actions = PlayerActions(
            openSettings: { [weak self] in self?.settingsWindow.show() },
            openSettingsPane: { [weak self] pane in self?.settingsWindow.show(pane: pane) },
            hidePlayer: { [weak self] in self?.player.hide(animated: true) },
            showSurface: { [weak self] surface in self?.player.go(to: surface) },
            suspendGlobalShortcuts: { [weak self] suspended in
                guard let self else { return }
                // A chord just recorded is registered as shortcuts resume, so
                // the recorder can say at once if macOS turned it down.
                if !suspended { hotKeys.register(settings.shortcuts) }
                hotKeys.isSuspended = suspended
            }
        )
        historyWindow = HistoryWindowPresenter(
            history: history,
            settings: settings,
            store: store,
            actions: actions,
            services: services
        )
        services.provide(historyWindow)
        player = PlayerWindowController(
            store: store,
            settings: settings,
            launchOptions: launchOptions,
            actions: actions,
            services: services
        )
        services.provide(player.sizing)
        settingsWindow = SettingsWindowPresenter(settings: settings, store: store, actions: actions, services: services)
        let services = services
        menuBar = MenuBarController(
            store: store,
            settings: settings,
            player: player,
            openSettings: actions.openSettings,
            openHistory: { [weak self] in self?.historyWindow.show() },
            makePopover: { [weak self, store, settings] popOut in
                let popover = MenuBarPopover(store: store, settings: settings, actions: actions, services: services, popOut: popOut)
                self?.menuBarPopover = popover
                return popover
            }
        )
        menuBar.togglePlayerShortcut = { [weak self] in
            guard let self, !hotKeys.unavailable.contains(.togglePlayer) else { return nil }
            return settings.shortcuts.togglePlayer
        }
        player.onVisibilityChange = { [weak self] _ in self?.menuBar.refreshStatusItem() }
        // In Menu Bar the item is the player: summoning it opens its popover,
        // and the window comes and goes from where the item is. Show leaves an
        // open popover open; only Toggle Player closes it.
        player.onSummonInMenuBar = { [weak self] summon in
            guard let self, summon.togglesPopover(isShown: menuBarPopover?.isShown == true) else { return }
            menuBar.togglePopover()
        }
        player.statusItemFrame = { [weak self] in self?.menuBar.statusItemFrame }
        widgetSnapshot = WidgetSnapshotWriter(store: store)
        widgetSnapshot.settings = settings

        hotKeys.onAvailabilityChange = { [weak self] unavailable in
            self?.shortcutStatus.update(unavailable: Set(unavailable.map { action in
                switch action {
                case .togglePlayer: .togglePlayer
                }
            }))
        }
        hotKeys.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .togglePlayer: player.toggle()
            }
        }
    }

    /// Real sources talk to the installed apps; the demo never does.
    private static func makeSources(_ options: LaunchOptions) -> [any PlaybackSource] {
        if options.demo {
            return [DemoSource(
                playlist: demoPlaylist,
                startsPlaying: options.demoStartsPlaying,
                followsSpotify: DemoAttribution.namesSpotify(options.demoAttribution)
            )]
        }
        return [SpotifyAppSource(), MusicAppSource()]
    }

    /// The demo's songs. In a debug build, `HUM_DEMO_LONG_SONG=1` gives the first
    /// a very long title and artist, so the menu-bar menu cutting them short
    /// (DESIGN.md §5.8) can be seen.
    private static var demoPlaylist: [DemoTrack] {
        var tracks = DemoPlaylist.tracks
        #if DEBUG
        if ProcessInfo.processInfo.environment["HUM_DEMO_LONG_SONG"] == "1" {
            tracks[0].track.title = "Low Tide Radio (Live at the Harbour Hall, with the Whole Choir)"
            tracks[0].track.artist = "Marlow Fields & The Coastline Hours Chamber Orchestra"
        }
        #endif
        return tracks
    }

    /// The library providers for the sources that have one.
    @MainActor
    private static func makeLibrary(
        store: NowPlayingStore,
        options: LaunchOptions,
        directories: AppDirectories
    ) -> LibraryStore {
        var providers: [any LibraryProvider] = []
        for source in store.sources {
            if let demo = source as? DemoSource {
                providers.append(DemoLibrary(source: demo, playingOn: options.demoDevice, attribution: options.demoAttribution))
            } else if source.id == .musicApp {
                providers.append(MusicLibrary())
            }
        }
        return LibraryStore(
            nowPlaying: store,
            providers: providers,
            // Demo covers are drawn on the fly; real ones are worth keeping.
            thumbnails: ThumbnailCache(directory: options.demo ? nil : ThumbnailCache.directory(in: directories))
        )
    }

    /// `--demo-history`: about six months of invented listening, written only to
    /// the demo's history file, with the demo covers for its songs. While the
    /// demo follows Spotify, no listen names what it played from (§1.3).
    private static func seedDemoHistory(_ history: ListeningHistory, namesContexts: Bool) {
        let catalog = DemoPlaylist.tracks
        let listens = DemoHistory.generate(
            catalog: catalog.map(\.track),
            endingAt: Date(),
            calendar: .autoupdatingCurrent,
            namesContexts: namesContexts
        )
        history.replaceAll(with: listens) { await demoCover(for: $0) }
    }

    /// The demo's covers live in memory, so demo history kept from an earlier
    /// run gets them again, the same way `seedDemoHistory` gives them.
    private static func fillDemoArtwork(_ history: ListeningHistory) {
        history.fillArtwork { await demoCover(for: $0) }
    }

    /// The demo cover for a listen: its song's, or, for a song added only for
    /// the history, its album's or its single's.
    nonisolated private static func demoCover(for listen: Listen) async -> Data? {
        guard let cover = DemoPlaylist.cover(for: listen.trackID, album: listen.album) else { return nil }
        return await DemoArtwork.pngData(for: cover)
    }

    func start() {
        hotKeys.install()
        keepInStep()
        history.start()
        historySleep = HistorySleepObserver(history: history)
        store.start()
        widgetSnapshot.start()
        // A widget extension still running from the copy of Hum this one
        // replaced would keep the widgets frozen (DESIGN.md §7.3).
        Task { await StaleWidgetExtension().retire() }
        player.start()
        if let pane = launchOptions.settingsPane.flatMap(SettingsPane.init(argument:)) {
            // Launched from a script or a terminal: in front, but the keyboard
            // stays with the app in use.
            settingsWindow.show(pane: pane, activate: false)
        }
    }

    /// A widget's link (DESIGN.md §7.3): the transport, shuffle and repeat go
    /// straight to the source, without a window or bringing Hum forward;
    /// Show opens the player, or its popover in Menu Bar.
    func perform(_ action: HumURLAction) {
        if action == .show {
            player.show()
            return
        }
        let snapshot = store.snapshot
        guard let command = URLActions.command(
            for: action,
            capabilities: store.capabilities,
            shuffle: snapshot.shuffle ?? false,
            repeatMode: snapshot.repeatMode ?? .off
        ) else { return }
        store.send(command)
    }

    /// Settings… in the app menu: the same window the player and menu-bar menu open.
    func openSettings(pane: SettingsPane? = nil) {
        settingsWindow.show(pane: pane)
    }

    /// Opening Hum again shows the player. In Menu Bar, while the item is
    /// collapsed into Line Apps' line, the popover has nothing to hang from,
    /// so Settings opens instead.
    func reopen() {
        if player.isInMenuBar, menuBar.isCollapsedIntoLine {
            settingsWindow.show()
        } else {
            player.show()
        }
    }

    func stop() {
        player.saveState()
        history.stop()
        store.stop()
        hotKeys.unregisterAll()
        settings.flush()
    }

    private func keepInStep() {
        observeChanges { [weak self] in
            guard let self else { return }
            hotKeys.register(settings.shortcuts)
        }
        observeChanges { [weak self] in
            guard let self else { return }
            let preferred = settings.playback.preferredSource
            if store.preferredSourceID != preferred {
                store.preferredSourceID = preferred
            }
        }
        observeChanges { [weak self] in
            guard let self else { return }
            let lastActive = store.lastActiveSourceID
            if lastActive != nil, settings.playback.lastActiveSource != lastActive {
                settings.playback.lastActiveSource = lastActive
            }
        }
    }
}
