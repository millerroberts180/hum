import HumCore
import SwiftUI

/// Global shortcuts, and a reference card for the keys inside the player
/// (DESIGN.md §4.3).
struct ShortcutsSettingsPane: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                LabeledContent {
                    ShortcutRecorder(
                        chord: $settings.shortcuts.togglePlayer,
                        defaultChord: nil,
                        action: .togglePlayer
                    )
                } label: {
                    DetailLabel(
                        title: "Show or hide the player",
                        detail: settings.shortcuts.togglePlayer == nil
                            ? "None until you set one. It also appears in the menu bar menu."
                            : "Also shown in the menu bar menu. In Menu Bar, it opens and closes the player there."
                    )
                }
            } header: {
                Text("From Anywhere")
            } footer: {
                FooterNote("Click a shortcut, then press the new keys. A shortcut needs ⌘, ⌥, or ⌃. Escape cancels.")
            }

            Section {
                ForEach(PlayerKeyReference.all) { entry in
                    LabeledContent {
                        ShortcutKeys(keys: entry.keys)
                    } label: {
                        Text(entry.action)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("In the Player")
            } footer: {
                FooterNote("These work while the player is the active window.")
            }
        }
        .formStyle(.grouped)
    }
}

/// One line of the in-player key reference.
nonisolated struct PlayerKeyReference: Identifiable, Sendable {
    var action: String
    var keys: [String]

    var id: String { action }

    static let all: [PlayerKeyReference] = [
        PlayerKeyReference(action: "Play or Pause", keys: ["Space"]),
        PlayerKeyReference(action: "Next or Previous Track", keys: ["⌘→", "⌘←"]),
        PlayerKeyReference(action: "Volume Up or Down", keys: ["⌘↑", "⌘↓"]),
        PlayerKeyReference(action: "Favorite", keys: ["⌥⇧B"]),
        PlayerKeyReference(action: "Now, History, Status", keys: ["⌘1", "⌘2", "⌘3"]),
        PlayerKeyReference(action: "Previous or Next Surface", keys: ["←", "→"]),
        PlayerKeyReference(action: "Move and Choose in Lists", keys: ["↑", "↓", "↩"]),
        PlayerKeyReference(action: "Back Out One Level", keys: ["Esc"]),
        PlayerKeyReference(action: "Hide Player", keys: ["⌘W"]),
        PlayerKeyReference(action: "Settings", keys: ["⌘,"]),
    ]
}
