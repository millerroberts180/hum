import AppKit

// Hum is a menu-bar app with one floating player. It has no Dock icon or menu
// bar except while Settings, Listening History, or About is open (DockPresence).
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)

// Quit normally on SIGTERM (`kill`, logout scripts) so settings and the
// window's placement are saved, instead of the process just vanishing.
signal(SIGTERM, SIG_IGN)
let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminationSource.setEventHandler {
    MainActor.assumeIsolated { NSApp.terminate(nil) }
}
terminationSource.resume()

application.run()
