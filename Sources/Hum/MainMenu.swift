import AppKit

/// The menu bar Hum shows while the Listening History window is open: the
/// standard app, Edit, Window, and Help menus, with the standard titles in the
/// standard order. AppKit routes key equivalents through it either way, so they
/// work in Settings too, where Hum stays a menu-bar app and shows no menu bar:
/// ⌘, from any Hum window, ⌘W, ⌘Q, and the Edit commands text fields rely on
/// for cut, copy, paste, undo, and select all.
enum MainMenu {
    /// The items Hum handles itself; the rest go to the responder chain.
    struct Actions {
        /// About Hum: Settings on the Hum pane (`AppCommands.showAbout`).
        var showAbout: () -> Void
        var openSettings: () -> Void
        /// Nil when there's no help page to open; Hum Help is then disabled.
        var showHelp: (() -> Void)?
    }

    /// Make the menu Hum's menu bar, with its Services, Window, and Help menus.
    static func install(_ actions: Actions) {
        let menu = make(actions)
        NSApp.mainMenu = menu
        NSApp.servicesMenu = menu.item(withTitle: "Hum")?.submenu?.item(withTitle: "Services")?.submenu
        NSApp.windowsMenu = menu.item(withTitle: "Window")?.submenu
        // The Help menu gets the system's search field above its items.
        NSApp.helpMenu = menu.item(withTitle: "Help")?.submenu
    }

    static func make(_ actions: Actions) -> NSMenu {
        let menu = NSMenu()

        let appMenu = NSMenu(title: "Hum")
        appMenu.addItem(NSMenuItem("About Hum", action: actions.showAbout))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem("Settings…", key: ",", action: actions.openSettings))
        appMenu.addItem(.separator())
        appMenu.addItem(submenu: NSMenu(title: "Services"))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Hum", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Hum", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(submenu: appMenu)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(submenu: editMenu)

        // Hum has no documents, so no File menu: Close lives here, as in
        // System Settings.
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        menu.addItem(submenu: windowMenu)

        // ⌘? works, but macOS draws no shortcut beside it, in Apple's apps
        // too: it's the key for the system's Show Help Menu (⇧⌘/), and menus
        // leave that key out.
        let helpMenu = NSMenu(title: "Help")
        if let showHelp = actions.showHelp {
            helpMenu.addItem(NSMenuItem("Hum Help", key: "?", action: showHelp))
        } else {
            // With no action, AppKit draws the item disabled, and ⌘? with it.
            helpMenu.addItem(withTitle: "Hum Help", action: nil, keyEquivalent: "?")
        }
        menu.addItem(submenu: helpMenu)

        return menu
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
