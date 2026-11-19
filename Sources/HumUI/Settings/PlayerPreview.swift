import HumCore
import SwiftUI

/// The player as it looks right now, drawn inside Settings: the chosen style's
/// Now layout with the track that's playing, at the player's size, in the light
/// or dark look, at rest or with its controls showing.
///
/// It's a picture, not a second player: it takes no clicks, Tab passes it by,
/// and VoiceOver reads it as one image. Every look change shows here as it's made.
struct PlayerPreview: View {
    var style: PlayerStyleID
    var appearance: LookAppearance
    var showsControls: Bool

    /// The most room the preview may take; a larger player is drawn smaller.
    var room = CGSize(width: 380, height: 240)

    @Environment(SettingsStore.self) private var settings
    @Environment(NowPlayingStore.self) private var store
    @Environment(PlayerSizing.self) private var sizing: PlayerSizing?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var interaction = PlayerInteraction()

    /// The player's own size, so the preview lays out the way the player does;
    /// the style's default before the player has a size.
    static func size(for style: PlayerStyleID, playerSize: PlayerSize?) -> CGSize {
        CGSize(StyleGeometry.clamp(playerSize ?? StyleGeometry.defaultSize(for: style), for: style))
    }

    /// Drawn at full size when it fits `room`, otherwise scaled down whole.
    static func scale(for size: CGSize, in room: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(1, room.width / size.width, room.height / size.height)
    }

    var body: some View {
        let size = Self.size(for: style, playerSize: sizing?.size)
        let scale = Self.scale(for: size, in: room)
        let look = settings.appearance.look(for: style, in: appearance)
        let metrics = PlayerMetrics(side: min(size.width, size.height), cornerRadiusScale: CGFloat(look.cornerRadiusScale))
        // The window's own corners: a card's for Title, Strip, Wide and Big
        // Art, a capsule for Text, a panel's for Art Only.
        let radius = PlayerContentView.CornerShape(style).radius(for: size, scale: metrics.cornerRadiusScale)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        NowStyleSwitch()
            .modifier(AccentTransition())
            .environment(\.playerMetrics, metrics)
            .frame(width: size.width, height: size.height)
            // As in the player's root: concentric shapes inside follow the
            // preview's corners.
            .containerShape(shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(HumColor.glassStroke, lineWidth: 0.5))
            // A stand-in for the system window shadow the player has. It's
            // drawn from the shape, behind the player, not taken from the
            // player: a shadow of the player flattens it together with its
            // in-window materials.
            .background { PreviewShadow(shape: shape) }
            .opacity(showsControls ? 1 : look.opacity)
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
            .environment(\.playerLook, PlayerLook(style: style, look: look, appearance: appearance, isBar: style.isBar || style.isLandscape))
            .environment(interaction)
            .environment(\.colorScheme, appearance == .dark ? .dark : .light)
            .environment(\.humMaterialsStayInWindow, true)
            // Under Reduce Motion the new size is simply there, as the window's is.
            .animation(reduceMotion ? nil : Motion.smooth, value: size)
            .allowsHitTesting(false)
            // Out of the key-view loop. The player's controls draw the same
            // either way; they read this only for hover and focus.
            .disabled(true)
            .onAppear {
                interaction.alwaysReveal = showsControls
                interaction.isWindowVisible = true
            }
            .onDisappear {
                interaction.isWindowVisible = false
            }
            .onChange(of: showsControls) { _, shows in
                interaction.alwaysReveal = shows
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of the \(style.title) style in \(appearance.title.lowercased()) appearance")
            .accessibilityAddTraits(.isImage)
    }
}

/// The preview's window shadow on its own: the shape's shadow with the shape
/// cut out, so a translucent player shows what's behind it rather than a dark
/// fill.
struct PreviewShadow<S: Shape>: View {
    var shape: S

    var body: some View {
        shape.fill(.black)
            .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
            .overlay(shape.fill(.black).blendMode(.destinationOut))
            .compositingGroup()
            .allowsHitTesting(false)
    }
}

/// A stand-in desktop behind the preview, so translucent styles and the resting
/// opacity have something to show through to: the player's own `ArtBackdrop`
/// for the cover that's playing, in the preview's appearance. Every cover is
/// drawn the same way, whichever app it comes from (DESIGN.md §13.17).
struct PreviewBackdrop: View {
    var appearance: LookAppearance

    @Environment(NowPlayingStore.self) private var store

    var body: some View {
        // Exactly the room it's given: the backdrop's cover is filled past it,
        // and would otherwise spread behind the controls under the preview.
        Color.clear
            .overlay {
                ArtBackdrop(artwork: store.artwork)
                    .environment(\.colorScheme, appearance == .dark ? .dark : .light)
            }
            .clipped()
    }
}

#if DEBUG
struct PlayerPreview_Previews: PreviewProvider {
    /// The preview in the appearance it's shown in.
    private struct Sample: View {
        var style: PlayerStyleID
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            PlayerPreview(style: style, appearance: LookAppearance(colorScheme), showsControls: false)
        }
    }

    static var previews: some View {
        PreviewGallery(cases: [.largeLight, .largeDark], isSquare: false) {
            VStack(spacing: Spacing.m) {
                Sample(style: .artOnly)
                Sample(style: .bigArt)
            }
            .padding(Spacing.m)
        }
    }
}
#endif
