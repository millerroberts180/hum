import HumCore
import SwiftUI

/// The Text style (DESIGN.md §7): a capsule 44 pt tall on `glassCapsule`, with
/// the title over the artist and nothing else.
///
/// On hover or focus the words fade out and the five transport glyphs fade in,
/// spread evenly across the capsule: shuffle and repeat at the tertiary size,
/// the others at the secondary. With album tint the capsule takes the cover
/// palette's `background` and every color comes from the palette (§3.5.4).
/// A HUD takes the words' place for its hold (`BarHUD`).
struct TextNowLayout: View {
    @Environment(NowPlayingStore.self) private var store
    @Environment(PlayerInteraction.self) private var interaction
    @Environment(\.playerLook) private var look
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The words' side padding.
    nonisolated static let textInset = Spacing.l
    /// From the capsule's ends to the outer glyphs' hit targets, which keeps
    /// their backings clear of the curve.
    nonisolated static let glyphInset = Spacing.s

    var body: some View {
        let status = NowStatus(store)
        let track = status == .ready ? store.track : nil
        let isRevealed = interaction.isRevealed && track != nil
        let palette = look.look.albumTint ? store.artwork?.palette : nil
        let menu = TrackMenu.current(store)
        BarHUD {
            ZStack {
                Group {
                    if let track {
                        BarTitleStack(track: track, titleRole: .textTitle, artistRole: .textArtist)
                    } else {
                        BarStatus(status: status, titleRole: .textTitle)
                    }
                }
                .padding(.horizontal, Self.textInset)
                .opacity(isRevealed ? 0 : 1)
                .accessibilityHidden(isRevealed)
                if track != nil {
                    TextControls()
                        .padding(.horizontal, Self.glyphInset)
                        .offset(y: isRevealed || reduceMotion ? 0 : Motion.revealTravel)
                        .opacity(isRevealed ? 1 : 0)
                        .allowsHitTesting(isRevealed)
                        .accessibilityHidden(!isRevealed)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(isRevealed ? Motion.reveal : Motion.conceal, value: isRevealed)
        .animation(Motion.color(reduceMotion: reduceMotion), value: palette)
        .barMetrics(playsAtSecondarySize: true)
        .environment(\.humColorContext, palette.map { HumColorContext.tinted($0) } ?? .material)
        .environment(\.colorScheme, palette.map { $0.isDark ? .dark : .light } ?? colorScheme)
        .environment(\.humAccent, Self.monochrome)
        .background {
            if let palette {
                // From cover to cover through OKLCH (§3.5.5).
                PaletteFill(palette.background)
                    .accessibilityHidden(true)
            }
        }
        .modifier(TextCapsuleMaterial(isTinted: palette != nil))
        .help(track.map(BarText.titleAndArtist) ?? "")
        .nowContextMenu(menu)
    }

    /// One color for every glyph, on or off: white on dark, black on light. An
    /// active toggle is a `label` glyph with a `label` dot under it, so on and
    /// off stay distinct.
    static let monochrome = AccentColors(onDark: .white, onLight: .black)
}

/// `glassCapsule` at the window level, unless album tint fills the capsule.
private struct TextCapsuleMaterial: ViewModifier {
    var isTinted: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isTinted {
            content.environment(\.isInWindowGlass, false)
        } else {
            content.windowMaterial(.glassCapsule)
        }
    }
}

/// The five glyphs, spread across the capsule.
private struct TextControls: View {
    @Environment(\.playerMetrics) private var metrics
    @Environment(\.playerLook) private var look

    var body: some View {
        TransportRow(
            showsShuffleRepeat: look.look.hoverControls.contains(.shuffleRepeat),
            fit: .spread(max(0, metrics.side - TextNowLayout.glyphInset * 2))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
struct TextNowLayout_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreviewGallery(style: .text) { TextNowLayout() }
            PreviewGallery(style: .text, revealsControls: true) { TextNowLayout() }
        }
    }
}
#endif
