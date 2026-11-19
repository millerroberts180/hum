import AppKit

/// The target for a menu item that runs a closure. The item keeps it alive as
/// its represented object, since a menu item holds its target weakly.
final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }
}

extension NSMenuItem {
    /// A menu item that runs `action` when chosen.
    convenience init(_ title: String, key: String = "", action: @escaping () -> Void) {
        let target = MenuAction(action)
        self.init(title: title, action: #selector(MenuAction.run), keyEquivalent: key)
        self.target = target
        representedObject = target
    }
}
