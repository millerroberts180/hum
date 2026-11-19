import HumCore
import SwiftUI

/// The music apps Hum plays from (DESIGN.md §8).
///
/// Whether Hum may control each app is shown on the player's Status page
/// (§6.3), not here; Hum asks for that permission the first time a control is
/// used, never from Settings.
struct SourcesSettingsPane: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let selection = SourceChoice(preferred: settings.playback.preferredSource)
        Form {
            Section {
                TileRow(title: "Control", detail: detail(selection)) {
                    ChoiceTiles(
                        SourceChoice.allCases,
                        selection: selection,
                        columns: 3,
                        artHeight: 60,
                        title: \.title,
                        caption: { SourceApps.isInstalled($0) ? nil : "Not installed" },
                        isAvailable: SourceApps.isInstalled,
                        pick: { choice in
                            if settings.playback.preferredSource != choice.sourceID {
                                settings.playback.preferredSource = choice.sourceID
                            }
                        }
                    ) { choice in
                        SourceTileArt(choice: choice)
                    }
                }
            } header: {
                Text("Music App")
            } footer: {
                FooterNote("See whether Hum can control each app on the player’s Status page.")
            }
        }
        .formStyle(.grouped)
    }

    private func detail(_ choice: SourceChoice) -> String {
        switch choice {
        case .automatic: "Hum follows whichever app is playing."
        case .music, .spotify: "Hum follows whichever app is playing. When both are, \(choice.title) wins."
        }
    }
}
