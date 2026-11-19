import HumCore
import SwiftUI

/// A style's player drawn small for Settings: its window shape and its layout
/// around the cover that's playing, at `scale` points per player point. Rounded
/// bars stand for lines of text and dots for glyphs, each in a `HumColor` role.
///
/// The Style, Size, Position, Corners and Opacity tiles all draw it, so the
/// player looks the same in each. Every cover is drawn the same way, whichever
/// app it comes from (DESIGN.md §13.17).
struct StyleMiniature: View {
    var style: PlayerStyleID
    var scale: CGFloat
    /// The player's size; the style's default when `nil`.
    var size: PlayerSize?
    /// The look's corner radius scale.
    var cornerRadiusScale: Double = 1
    /// Text's album tint: the capsule in the cover's own colors.
    var albumTint = false

    @Environment(NowPlayingStore.self) private var store

    /// The size the miniature takes: the player's, brought into the style's
    /// shape, at `scale`.
    static func drawnSize(_ style: PlayerStyleID, size: PlayerSize?, scale: CGFloat) -> CGSize {
        let real = realSize(style, size: size)
        return CGSize(width: real.width * scale, height: real.height * scale)
    }

    /// The largest scale at which `style` at `size` fits in `box`.
    static func fittingScale(_ style: PlayerStyleID, size: PlayerSize? = nil, in box: CGSize) -> CGFloat {
        let real = realSize(style, size: size)
        guard real.width > 0, real.height > 0 else { return 1 }
        return min(box.width / real.width, box.height / real.height)
    }

    static func realSize(_ style: PlayerStyleID, size: PlayerSize?) -> CGSize {
        CGSize(size.map { StyleGeometry.clamp($0, for: style) } ?? StyleGeometry.defaultSize(for: style))
    }

    /// The player window's own corner radius at `real` size, by the window's
    /// rule for the style's shape: a capsule for Text, a card's corners for
    /// Title, Strip, Wide and Big Art, a panel's for the rest.
    static func windowRadius(_ style: PlayerStyleID, real: CGSize, cornerRadiusScale: Double = 1) -> CGFloat {
        PlayerContentView.CornerShape(style).radius(for: real, scale: CGFloat(cornerRadiusScale))
    }

    var body: some View {
        let real = Self.realSize(style, size: size)
        let drawn = CGSize(width: real.width * scale, height: real.height * scale)
        // Never sharper than 1.5 pt, so the smallest miniature still reads as a window.
        let radius = max(Self.windowRadius(style, real: real, cornerRadiusScale: cornerRadiusScale) * scale, 1.5)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        layout(drawn)
            .frame(width: drawn.width, height: drawn.height)
            .clipShape(shape)
            .overlay(shape.stroke(HumColor.glassStroke, lineWidth: 0.5))
            .humShadow(.listArt)
    }

    @ViewBuilder
    private func layout(_ drawn: CGSize) -> some View {
        switch style {
        case .artOnly, .menuBar: cover
        case .title: title(drawn)
        case .text: text(drawn)
        case .strip: strip(drawn)
        case .wide: wide(drawn)
        case .bigArt: bigArt(drawn)
        }
    }

    private var u: CGFloat { scale }

    private var cover: some View {
        ArtworkView(artwork: store.artwork)
    }

    private func cover(side: CGFloat, radius: CGFloat) -> some View {
        cover
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: max(radius, 1), style: .continuous))
    }

    /// The window-level glass of Title, Text, Strip, Wide and Big Art.
    private var glass: some View {
        Rectangle().fill(.regularMaterial)
    }

    /// The title over the artist, as two bars.
    private func titleAndArtist(width: CGFloat, spacing: CGFloat, title: HumColor = .label, artist: HumColor = .secondaryLabel) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            MiniBar(width: width, height: 9 * u, color: title)
            MiniBar(width: width * 0.65, height: 7 * u, color: artist)
        }
    }

    /// Shuffle · previous · play/pause · next · repeat, as dots.
    private func transport(spacing: CGFloat, play: CGFloat = 16) -> some View {
        HStack(spacing: spacing * u) {
            ForEach(Array([9, 10, play, 10, 9].enumerated()), id: \.offset) { index, side in
                Circle()
                    .fill(index == 2 ? HumColor.label : HumColor.secondaryLabel)
                    .frame(width: max(side * u, 1.5), height: max(side * u, 1.5))
            }
        }
    }

    /// A seek bar, `fraction` played.
    private func seekBar(width: CGFloat, fraction: CGFloat = 0.38) -> some View {
        ZStack(alignment: .leading) {
            MiniBar(width: width, height: 3 * u, color: .trackFill)
            MiniBar(width: width * fraction, height: 3 * u, color: .secondaryLabel)
        }
    }

    private func title(_ drawn: CGSize) -> some View {
        HStack(spacing: 8 * u) {
            cover(side: 56 * u, radius: Radius.artMedium * u)
            titleAndArtist(width: drawn.width * 0.42, spacing: 6 * u)
            Spacer(minLength: 0)
        }
        .padding(.leading, 8 * u)
        .background { glass }
    }

    private func text(_ drawn: CGSize) -> some View {
        let palette = albumTint ? store.artwork?.palette : nil
        let context: HumColorContext = if let palette { .tinted(palette) } else { .material }
        return titleAndArtist(width: drawn.width * 0.5, spacing: 5 * u)
            .padding(.horizontal, Spacing.l * u)
            .frame(width: drawn.width, height: drawn.height, alignment: .leading)
            .background { TextTileBackground(palette: palette) }
            .environment(\.humColorContext, context)
    }

    private func strip(_ drawn: CGSize) -> some View {
        // The transport's five dots and four 7-pt gaps; the cover, its insets
        // and the gaps either side of the notch.
        let transportWidth: CGFloat = 82 * u
        let fixedWidth: CGFloat = 68 * u
        let notch = max(drawn.width - fixedWidth - transportWidth, 4)
        return HStack(spacing: 8 * u) {
            cover(side: 36 * u, radius: Radius.artSmall * u)
            seekBar(width: notch)
            transport(spacing: 7)
        }
        .padding(.leading, 6 * u)
        .padding(.trailing, 10 * u)
        .frame(width: drawn.width, height: drawn.height, alignment: .leading)
        .background { glass }
    }

    /// The cover at the leading edge, inset on three sides, and the card's
    /// stack beside it, centered on the card's height.
    private func wide(_ drawn: CGSize) -> some View {
        let inset = Spacing.m * u
        let side = max(drawn.height - 2 * inset, 1)
        let column = max(drawn.width - inset - side - 2 * inset, 1)
        return HStack(spacing: inset) {
            cover(side: side, radius: Radius.card * u)
            cardStack(width: column, height: min(drawn.height, BigArtNowLayout.stackRoom * u))
        }
        .padding(.leading, inset)
        .frame(width: drawn.width, height: drawn.height, alignment: .leading)
        .background { glass }
    }

    /// The cover inset at the top, and the card's stack under it.
    private func bigArt(_ drawn: CGSize) -> some View {
        let inset = Spacing.m * u
        let side = max(drawn.width - 2 * inset, 1)
        return VStack(spacing: inset) {
            cover(side: side, radius: Radius.card * u)
            cardStack(width: side, height: BigArtNowLayout.stackRoom * u)
        }
        .padding(inset)
        .frame(width: drawn.width, height: drawn.height, alignment: .top)
        .background { glass }
    }

    /// Wide's and Big Art's stack, its rows spread over the height the real
    /// one takes: the title row with Save and More, the seek bar with its
    /// times, the transport across the width, and the volume row.
    private func cardStack(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4 * u) {
                titleAndArtist(width: width * 0.55, spacing: 6 * u)
                Spacer(minLength: 0)
                MiniDot(side: 9 * u, color: .secondaryLabel)
                MiniDot(side: 9 * u, color: .secondaryLabel)
            }
            Spacer(minLength: 0)
            VStack(spacing: 4 * u) {
                seekBar(width: width)
                HStack {
                    MiniBar(width: 14 * u, height: 4 * u, color: .tertiaryLabel)
                    Spacer(minLength: 0)
                    MiniBar(width: 16 * u, height: 4 * u, color: .tertiaryLabel)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(Array([9, 11, 12, 11, 9].enumerated()), id: \.offset) { index, side in
                    if index > 0 {
                        Spacer(minLength: 0)
                    }
                    MiniDot(side: CGFloat(side) * u, color: index == 2 ? .label : .secondaryLabel)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6 * u) {
                MiniDot(side: 7 * u, color: .tertiaryLabel)
                MiniBar(width: max(width - 30 * u, 1), height: 3 * u, color: .trackFill)
                MiniDot(side: 9 * u, color: .tertiaryLabel)
            }
        }
        .frame(width: width, height: height)
    }
}

/// A rounded bar standing for a line of text or a slider.
struct MiniBar: View {
    var width: CGFloat
    var height: CGFloat
    var color: HumColor

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: max(width, 1), height: max(height, 1))
    }
}

/// A dot standing for a glyph.
struct MiniDot: View {
    var side: CGFloat
    var color: HumColor

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: max(side, 1.5), height: max(side, 1.5))
    }
}

/// Text's capsule: the glass, or the cover's own background with album tint.
private struct TextTileBackground: View {
    var palette: ArtworkPalette?

    var body: some View {
        if let palette {
            Rectangle().fill(Color(palette.background))
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }
}

/// A stand-in desktop for a tile to draw the player on: the playing cover
/// blurred, as the preview's backdrop is, in the tile's appearance.
struct TileDesktop: View {
    @Environment(NowPlayingStore.self) private var store

    var body: some View {
        // The backdrop's cover is filled past the room it's given, which would
        // make it report a taller size; this takes exactly the room, so drawings
        // aligned to the desktop's top, such as its menu bar, land on its edge.
        Color.clear
            .overlay { ArtBackdrop(artwork: store.artwork) }
            .clipped()
    }
}

/// The art for each style's tile in Appearance › Style (DESIGN.md §8): the
/// style's miniature on the desktop, or for Menu Bar a strip of menu bar with
/// the mini player in it. The art is the same whether or not the tile is
/// chosen; the tile's ring marks the choice.
struct StyleTileArt: View {
    var style: PlayerStyleID

    nonisolated static let artHeight: CGFloat = 76
    /// The room a miniature gets in its tile.
    nonisolated static let box = CGSize(width: 104, height: 58)

    /// How the tile draws `style`.
    nonisolated enum Layout: Equatable {
        /// The player's miniature on the desktop.
        case miniature
        /// A strip of menu bar holding the mini player.
        case menuBar
    }

    nonisolated static func layout(for style: PlayerStyleID) -> Layout {
        style.hasWindow ? .miniature : .menuBar
    }

    var body: some View {
        ZStack {
            TileDesktop()
            switch Self.layout(for: style) {
            case .miniature:
                StyleMiniature(style: style, scale: StyleMiniature.fittingScale(style, in: Self.box))
            case .menuBar:
                MenuBarStripArt()
            }
        }
        .accessibilityHidden(true)
    }
}

/// A strip of menu bar with Menu Bar's mini player at its trailing end: the
/// cover, the title, play/pause and next (DESIGN.md §7.1). Menu titles at the
/// leading end are bars.
struct MenuBarStripArt: View {
    var height: CGFloat = 18

    @Environment(NowPlayingStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Array([7, 12, 10, 9].enumerated()), id: \.offset) { _, width in
                    MiniBar(width: CGFloat(width), height: 3, color: .tertiaryLabel)
                }
                Spacer(minLength: Spacing.xs)
                HStack(spacing: 3) {
                    ArtworkView(artwork: store.artwork)
                        .frame(width: height * 0.62, height: height * 0.62)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    MiniBar(width: 26, height: 3.5, color: .label)
                    Image(systemName: store.isPlaying ? HumIcon.pause : HumIcon.play)
                    Image(systemName: HumIcon.next)
                }
                .font(.system(size: height * 0.36, weight: .semibold))
                .foregroundStyle(HumColor.label)
            }
            .padding(.horizontal, 6)
            .frame(height: height)
            .background(.bar)
            .overlay(alignment: .bottom) {
                Rectangle().fill(HumColor.separator).frame(height: 0.5)
            }
            Spacer(minLength: 0)
        }
    }
}
