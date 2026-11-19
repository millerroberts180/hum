import HumCore
import SwiftUI

/// The root SwiftUI view with the player's shared objects in its environment.
struct PlayerWindowContent: View {
    let store: NowPlayingStore
    let settings: SettingsStore
    let pager: SurfacePager
    let interaction: PlayerInteraction
    let actions: PlayerActions
    let services: AppServices
    /// The content started or stopped asking for the window's own glass
    /// (`WindowMaterialBackground`, macOS 26).
    var onWindowGlassChange: (Bool) -> Void = { _ in }
    /// The look's resting opacity for that glass (`WindowOpacityKey`).
    var onWindowOpacityChange: (Double) -> Void = { _ in }

    var body: some View {
        services.inject(
            PlayerRootView()
                .modifier(PlayerRestingOpacity())
                .modifier(PlayerLookProvider())
                .environment(store)
                .environment(settings)
                .environment(pager)
                .environment(interaction)
                .environment(\.playerActions, actions)
        )
        .onPreferenceChange(WindowGlassKey.self) { onWindowGlassChange($0) }
        .onPreferenceChange(WindowOpacityKey.self) { onWindowOpacityChange($0) }
    }
}
