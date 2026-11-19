import AppKit
import HumCore
import SwiftUI

/// Appearance's preview while the style is Menu Bar (DESIGN.md §7.1, §8): the
/// status item in a strip of menu bar, with its Now Playing popover open under
/// it, at full size and scaled down whole to fit. The popover is the real one,
/// `MenuBarNowView`, in the look being edited.
///
/// Like `PlayerPreview` it's a picture: it takes no clicks, Tab passes it by,
/// and VoiceOver reads it as one image.
struct MenuBarPreview: View {
    var appearance: LookAppearance
    var room = CGSize(width: 380, height: 240)

    @Environment(NowPlayingStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @State private var interaction = PlayerInteraction()

    nonisolated static let menuBarHeight: CGFloat = 24
    nonisolated static let itemCover: CGFloat = 18
    nonisolated static let itemCoverRadius: CGFloat = 4
    nonisolated static let titleWidth: CGFloat = 160
    nonisolated static let itemGap: CGFloat = 6
    /// Between the menu bar and the popover, where its arrow would be.
    nonisolated static let popoverGap: CGFloat = Spacing.s

    /// The whole drawing's size at full scale: the popover with room for its
    /// shadow, under the menu bar.
    static let fullSize = CGSize(width: MenuBarNowView.width + 2 * Spacing.xl, height: 480)

    static func scale(in room: CGSize) -> CGFloat {
        min(1, room.width / fullSize.width, room.height / fullSize.height)
    }

    var body: some View {
        let scale = Self.scale(in: room)
        let look = settings.appearance.look(for: .menuBar, in: appearance)
        VStack(spacing: Self.popoverGap) {
            menuBar
            popover
                .environment(\.playerLook, PlayerLook(style: .menuBar, look: look, appearance: appearance, isBar: false))
        }
        .frame(width: Self.fullSize.width, height: Self.fullSize.height, alignment: .top)
        .modifier(AccentTransition())
        .environment(interaction)
        .environment(\.colorScheme, appearance == .dark ? .dark : .light)
        .scaleEffect(scale)
        .frame(width: Self.fullSize.width * scale, height: Self.fullSize.height * scale)
        .allowsHitTesting(false)
        .disabled(true)
        .onAppear {
            // The popover shows its controls whenever it's open.
            interaction.alwaysReveal = true
            interaction.isWindowVisible = true
        }
        .onDisappear {
            interaction.isWindowVisible = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the Menu Bar style in \(appearance.title.lowercased()) appearance")
        .accessibilityAddTraits(.isImage)
    }

    /// The status item as the mini player: the cover, the title, play/pause
    /// and next, 6 pt apart, in the menu bar's font.
    private var menuBar: some View {
        HStack(spacing: Self.itemGap) {
            ArtworkView(artwork: store.artwork)
                .frame(width: Self.itemCover, height: Self.itemCover)
                .clipShape(RoundedRectangle(cornerRadius: Self.itemCoverRadius, style: .continuous))
            Text(store.track?.title ?? "Nothing Playing")
                .font(Font(NSFont.menuBarFont(ofSize: 0)))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: Self.titleWidth, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            itemGlyph(store.isPlaying ? HumIcon.pause : HumIcon.play)
            itemGlyph(HumIcon.next)
        }
        .foregroundStyle(HumColor.label)
        .frame(height: Self.menuBarHeight)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(HumColor.separator).frame(height: 0.5)
        }
    }

    /// A bare template glyph in its 22-pt-wide hit area.
    private func itemGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 22)
    }

    /// The popover's content on the popover material, as the system draws it.
    private var popover: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return MenuBarNowView(popOut: {})
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(HumColor.glassStroke, lineWidth: 0.5))
            .background { PreviewShadow(shape: shape) }
            .environment(\.humMaterialsStayInWindow, true)
    }
}
