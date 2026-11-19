import AppKit
import HumCore
import SwiftUI
import UniformTypeIdentifiers

// The drawings inside Settings' choice tiles (DESIGN.md §8). Each draws what
// its option does, in Hum's tokens and color roles, and is hidden from
// VoiceOver: the tile reads its title.

// MARK: Appearance

/// Appearance › Appearance: a small window on the desktop in each appearance,
/// as System Settings draws its own. System shows half of each.
struct AppearanceModeTileArt: View {
    var mode: AppearanceMode

    var body: some View {
        Group {
            switch mode {
            case .light:
                MiniWindowScene().environment(\.colorScheme, .light)
            case .dark:
                MiniWindowScene().environment(\.colorScheme, .dark)
            case .system:
                ZStack {
                    MiniWindowScene().environment(\.colorScheme, .light)
                    MiniWindowScene().environment(\.colorScheme, .dark)
                        .mask {
                            HStack(spacing: 0) {
                                Color.clear
                                Color.black
                            }
                        }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A window with a sidebar and a few lines of text, on the desktop.
private struct MiniWindowScene: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        TileDesktop()
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 2.5) {
                        ForEach(0..<3, id: \.self) { _ in
                            MiniDot(side: 3.5, color: .tertiaryLabel)
                        }
                    }
                    HStack(alignment: .top, spacing: 6) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(HumColor.fillTertiary)
                            .frame(width: 16, height: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            MiniBar(width: 30, height: 4, color: .label)
                            MiniBar(width: 38, height: 3, color: .secondaryLabel)
                            MiniBar(width: 26, height: 3, color: .secondaryLabel)
                        }
                    }
                }
                .padding(6)
                .frame(width: 92, height: 60, alignment: .topLeading)
                .background(.background, in: shape)
                .overlay(shape.strokeBorder(HumColor.separator, lineWidth: 0.5))
                .humShadow(.listArt)
                .offset(x: 18, y: 14)
            }
    }
}

/// Appearance › Material: a small panel of each material over the cover.
struct MaterialTileArt: View {
    var material: GlassMaterial

    var body: some View {
        TileDesktop()
            .overlay { panel }
            .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            MiniBar(width: 40, height: 5, color: .label)
            MiniBar(width: 28, height: 4, color: .secondaryLabel)
        }
        .frame(width: 76, height: 40, alignment: .leading)
        .padding(.leading, Spacing.m)
    }

    @ViewBuilder
    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        if material == .liquidGlass {
            if #available(macOS 26, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                frosted(shape)
            }
        } else {
            frosted(shape)
        }
    }

    private func frosted(_ shape: RoundedRectangle) -> some View {
        content
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(HumColor.glassStroke, lineWidth: 0.5))
    }
}

/// Appearance › Accent: the color each source gives, as a swatch. Album's sits
/// on the cover it comes from; Custom's is ringed with every hue.
struct AccentTileArt: View {
    var source: AccentSource
    var custom: PaletteColor

    @Environment(NowPlayingStore.self) private var store

    var body: some View {
        Group {
            switch source {
            case .album:
                ZStack(alignment: .bottomTrailing) {
                    ArtworkView(artwork: store.artwork)
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.artSmall, style: .continuous))
                        .humShadow(.listArt)
                    AccentSwatch(color: Color(store.artwork?.palette.accent ?? .systemAccent), side: 20)
                        .offset(x: 8, y: 6)
                }
                .offset(x: -4, y: -3)
            case .system:
                AccentSwatch(color: Color(nsColor: .controlAccentColor), side: 26)
            case .custom:
                ZStack {
                    Circle()
                        .strokeBorder(
                            AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red], center: .center),
                            lineWidth: 3
                        )
                        .frame(width: 34, height: 34)
                    AccentSwatch(color: Color(custom), side: 22)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct AccentSwatch: View {
    var color: Color
    var side: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(HumColor.glassStroke, lineWidth: 0.5))
            .frame(width: side, height: side)
            .humShadow(.listArt)
    }
}

/// Appearance › Corners: the player's top-leading corner at its real size,
/// rounded at the tile's scale.
struct CornersTileArt: View {
    var choice: CornerChoice
    var style: PlayerStyleID
    var size: PlayerSize?

    var body: some View {
        TileDesktop()
            .overlay(alignment: .topLeading) {
                StyleMiniature(style: style, scale: 1, size: size, cornerRadiusScale: choice.scale)
                    .offset(x: 22, y: 16)
            }
            .accessibilityHidden(true)
    }
}

/// Appearance › Opacity at rest: the player over a pattern, at the tile's
/// opacity, so the pattern shows through.
struct OpacityTileArt: View {
    var choice: OpacityChoice
    var style: PlayerStyleID
    var cornerRadiusScale: Double

    nonisolated static let box = CGSize(width: 84, height: 44)

    var body: some View {
        CheckerPattern()
            .overlay {
                StyleMiniature(
                    style: style,
                    scale: StyleMiniature.fittingScale(style, in: Self.box),
                    cornerRadiusScale: cornerRadiusScale
                )
                .opacity(choice.opacity)
            }
            .accessibilityHidden(true)
    }
}

/// A checkerboard in a quiet label color, for translucency to show against.
struct CheckerPattern: View {
    var square: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let columns = Int((size.width / square).rounded(.up))
            let rows = Int((size.height / square).rounded(.up))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    path.addRect(CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square))
                }
            }
            context.fill(path, with: .style(HumColor.tertiaryLabel))
        }
    }
}

/// Appearance › Progress: Art Only's cover at rest with each indicator: none,
/// a hairline along the bottom, or a ring inside the edge.
struct ProgressTileArt: View {
    var kind: ProgressIndicator

    nonisolated static let side: CGFloat = 52
    /// How much of the song the drawing shows played.
    nonisolated static let played: CGFloat = 0.38

    var body: some View {
        let scale = Self.side / StyleMiniature.realSize(.artOnly, size: nil).width
        let real = StyleMiniature.realSize(.artOnly, size: nil)
        let radius = max(StyleMiniature.windowRadius(.artOnly, real: real) * scale, 1.5)
        TileDesktop()
            .overlay {
                StyleMiniature(style: .artOnly, scale: scale)
                    .overlay { indicator(radius: radius) }
            }
            .accessibilityHidden(true)
    }

    // Not a `switch`: the kinds grow (None arrives with Art Only's new default).
    @ViewBuilder
    private func indicator(radius: CGFloat) -> some View {
        let line: CGFloat = 1.5
        if kind == .line {
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(HumColor.trackFill).frame(height: line)
                Rectangle().fill(HumColor.label).frame(width: Self.side * Self.played, height: line)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .environment(\.humColorContext, .artwork)
        } else if kind == .ring {
            ZStack {
                PanelRing(cornerRadius: radius - line).stroke(HumColor.trackFill, lineWidth: line)
                PanelRing(cornerRadius: radius - line)
                    .trim(from: 0, to: Self.played)
                    .stroke(HumColor.label, style: StrokeStyle(lineWidth: line, lineCap: .round))
            }
            .padding(line)
            .environment(\.humColorContext, .artwork)
        }
    }
}

/// Appearance › Album tint: Text's capsule on glass, or in the cover's colors.
struct AlbumTintTileArt: View {
    var isTinted: Bool

    var body: some View {
        TileDesktop()
            .overlay {
                StyleMiniature(
                    style: .text,
                    scale: StyleMiniature.fittingScale(.text, in: StyleTileArt.box),
                    albumTint: isTinted
                )
            }
            .accessibilityHidden(true)
    }
}

// MARK: Player

/// Player › Size: the style at each preset, all three at one scale so they
/// compare as the real sizes do.
struct SizeTileArt: View {
    var preset: PlayerSizePreset
    var style: PlayerStyleID
    var cornerRadiusScale: Double

    nonisolated static let box = CGSize(width: 104, height: 64)

    /// The one scale for all three tiles: the one that fits Large.
    static func scale(for style: PlayerStyleID) -> CGFloat {
        StyleMiniature.fittingScale(style, size: PlayerSizePreset.large.size(for: style), in: box)
    }

    var body: some View {
        TileDesktop()
            .overlay {
                StyleMiniature(
                    style: style,
                    scale: Self.scale(for: style),
                    size: preset.size(for: style),
                    cornerRadiusScale: cornerRadiusScale
                )
            }
            .accessibilityHidden(true)
    }
}

/// Player › Show the player: Always draws the player on the screen; On Track
/// Change, the player with a note appearing; Under Menu Bar, the player
/// hanging from the menu bar; On Request, a key cap.
struct VisibilityTileArt: View {
    var mode: PlayerVisibility
    var style: PlayerStyleID

    nonisolated static let menuBarHeight: CGFloat = 7
    nonisolated static let box = CGSize(width: 44, height: 34)

    var body: some View {
        let scale = StyleMiniature.fittingScale(style, in: Self.box)
        TileDesktop()
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    switch mode {
                    case .pinned:
                        StyleMiniature(style: style, scale: scale)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, Self.menuBarHeight + Spacing.s)
                            .padding(.trailing, Spacing.m)
                    case .trackChanges:
                        StyleMiniature(style: style, scale: scale)
                            .overlay(alignment: .topLeading) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(HumColor.onAccent)
                                    .frame(width: 16, height: 16)
                                    .background(Circle().fill(Color.accentColor))
                                    .offset(x: -8, y: -6)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, Self.menuBarHeight + Spacing.s + 2)
                            .padding(.trailing, Spacing.m)
                    case .tucked:
                        StyleMiniature(style: style, scale: scale)
                            .padding(.top, Self.menuBarHeight)
                    case .summoned:
                        KeyCap()
                            .frame(maxHeight: .infinity)
                    }
                    MenuBarSliver(height: Self.menuBarHeight)
                }
            }
            .accessibilityHidden(true)
    }
}

/// The top of a screen: a thin menu bar.
private struct MenuBarSliver: View {
    var height: CGFloat

    var body: some View {
        Rectangle()
            .fill(.bar)
            .frame(height: height)
            .overlay(alignment: .bottom) {
                Rectangle().fill(HumColor.separator).frame(height: 0.5)
            }
    }
}

/// A keyboard key with the Command glyph.
private struct KeyCap: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Image(systemName: "command")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(HumColor.label)
            .frame(width: 34, height: 32)
            .background(.background, in: shape)
            .overlay(shape.strokeBorder(HumColor.separator, lineWidth: 0.5))
            .background {
                // The key's lower edge.
                shape.fill(HumColor.fillTertiary).offset(y: 2)
            }
            .humShadow(.listArt)
    }
}

// MARK: Sources

/// Sources › Control: each app's own icon, from its bundle (DESIGN.md
/// §3.5.7); Automatic shows both.
struct SourceTileArt: View {
    var choice: SourceChoice

    var body: some View {
        Group {
            switch choice {
            case .automatic:
                HStack(spacing: -Spacing.s) {
                    SourceAppIcon(choice: .music, side: 34)
                    SourceAppIcon(choice: .spotify, side: 34)
                }
            case .music, .spotify:
                SourceAppIcon(choice: choice, side: 40)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SourceAppIcon: View {
    var choice: SourceChoice
    var side: CGFloat

    var body: some View {
        Image(nsImage: SourceApps.icon(for: choice))
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
    }
}

/// Where the source apps are, read from Launch Services. Nothing here opens,
/// asks or sends anything to an app.
@MainActor
enum SourceApps {
    static func isInstalled(_ choice: SourceChoice) -> Bool {
        guard let bundleIdentifier = choice.bundleIdentifier else { return true }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    /// Music's or Spotify's own icon, or the generic application icon when
    /// the app can't be found.
    static func icon(for choice: SourceChoice, lookup: AppIconLookup = .workspace) -> NSImage {
        guard let bundleIdentifier = choice.bundleIdentifier else { return lookup.genericIcon() }
        return lookup.icon(bundleIdentifier: bundleIdentifier)
    }
}
