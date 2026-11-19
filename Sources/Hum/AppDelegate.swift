import AppKit
import HumCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var app: HumApp?
    private var dockPresence: DockPresence?
    /// Links that arrived before the app was ready, performed once it is.
    private var pendingActions: [HumURLAction] = []

    /// Before launch finishes, so a widget's link that launched Hum isn't
    /// missed.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        dockPresence = DockPresence()
        let app = HumApp()
        self.app = app
        MainMenu.install(MainMenu.Actions(
            showAbout: { [weak app] in AppCommands.showAbout { app?.openSettings(pane: $0) } },
            openSettings: { [weak app] in app?.openSettings() },
            showHelp: AppCommands.showHelp()
        ))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "none"
        HumLog.app.info("Launched \(version, privacy: .public) (\(build, privacy: .public))\(app.launchOptions.demo ? " in demo mode" : "", privacy: .public)")
        app.start()
        for action in pendingActions {
            app.perform(action)
        }
        pendingActions = []
    }

    func applicationWillTerminate(_ notification: Notification) {
        HumLog.app.info("Quitting")
        app?.stop()
    }

    /// A widget's `hum://` link (DESIGN.md §7.3). Anything that isn't one of
    /// Hum's actions is ignored.
    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string),
              let action = HumURLAction(url: url)
        else { return }
        // A link that launched Hum arrives before it's finished starting.
        guard let app else {
            pendingActions.append(action)
            return
        }
        app.perform(action)
    }

    /// Clicking the Dock icon while Listening History is open, or opening the
    /// app again from Finder, `open` or Line Apps' menu, shows the player.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        app?.reopen()
        return false
    }
}
