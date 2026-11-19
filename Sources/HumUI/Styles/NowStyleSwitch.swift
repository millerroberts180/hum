import HumCore
import SwiftUI

/// Picks the Now layout for the chosen player style.
///
/// Switching style is live: the old layout gives way to the new one on
/// `Motion.styleSwitch`, the same spring the window uses to take the new
/// style's shape, so the two read as one movement. Under Reduce Motion it's a crossfade.
struct NowStyleSwitch: View {
    @Environment(\.playerLook) private var look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let style = look.style
        ZStack {
            content(style)
                .id(style)
                .transition(.opacity)
        }
        .animation(reduceMotion ? Motion.crossfade : Motion.styleSwitch, value: style)
    }

    @ViewBuilder
    private func content(_ style: PlayerStyleID) -> some View {
        switch style {
        case .artOnly:
            ArtFirstNowLayout()
        case .title:
            TitleNowLayout()
        case .text:
            TextNowLayout()
        case .strip:
            StripNowLayout()
        case .wide:
            WideNowLayout()
        case .bigArt:
            BigArtNowLayout()
        // Menu Bar has no window (§7.1); the menu bar's popover draws Now
        // with `MenuBarNowView`. A player shown in it anyway, as the
        // Settings preview may, gets Art Only.
        case .menuBar:
            ArtFirstNowLayout()
        }
    }
}
