import HumCore
import SwiftUI

/// Surface 1: what's playing, with its controls. Actions whose result Now
/// doesn't show (Favorite from the keyboard or a menu, Copy Link) confirm in
/// the library's HUD.
struct NowSurface: View {
    @Environment(PlayerInteraction.self) private var interaction
    @Environment(LibraryStore.self) private var library: LibraryStore?
    /// The notice the volume HUD replaced, so it doesn't come back after.
    @State private var supersededNotice: UUID?

    var body: some View {
        // One HUD at a time, the newest: the volume HUD hides on a new notice
        // (`PlayerRootView`), and a notice gives way to the volume HUD here.
        let showsNotice = interaction.volumeHUDLevel == nil
            && (library?.notice).map { $0.id != supersededNotice } ?? true
        NowStyleSwitch()
            .hudBandOverlay {
                // Hidden rather than removed, so a new notice is still announced.
                LibraryHUD()
                    .opacity(showsNotice ? 1 : 0)
                    .accessibilityHidden(!showsNotice)
                    .animation(Motion.conceal, value: showsNotice)
            }
            .onChange(of: interaction.volumeHUDLevel == nil) { _, isHidden in
                if !isHidden { supersededNotice = library?.notice?.id }
            }
    }
}
