#if DEBUG
import HumCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Previews run against a demo player (DESIGN.md §12.4). They're
// `PreviewProvider`s: the Command Line Tools don't ship the `#Preview` macro.
//
//     struct SeekBar_Previews: PreviewProvider {
//         static var previews: some View {
//             PreviewGallery(backdrop: .artwork) { SeekBar() }
//         }
//     }

/// One way to show a preview: a player side, an appearance, and the service
/// the demo names.
struct PlayerPreviewCase: Hashable, Identifiable {
    var side: CGFloat
    var colorScheme: ColorScheme
    /// `"Spotify"` makes the demo do what Spotify can and can't (DESIGN.md §1.3).
    var demoAttribution: String?

    var id: Self { self }

    /// A side in the S size class.
    static let smallSide: CGFloat = 200
    /// A side in the L size class.
    static let largeSide: CGFloat = 440

    static let smallLight = PlayerPreviewCase(side: smallSide, colorScheme: .light)
    static let smallDark = PlayerPreviewCase(side: smallSide, colorScheme: .dark)
    static let largeLight = PlayerPreviewCase(side: largeSide, colorScheme: .light)
    static let largeDark = PlayerPreviewCase(side: largeSide, colorScheme: .dark)

    /// S and L, each light and dark.
    static let standard: [PlayerPreviewCase] = [.smallLight, .smallDark, .largeLight, .largeDark]

    /// The same case with the demo naming Spotify.
    var spotify: PlayerPreviewCase {
        var copy = self
        copy.demoAttribution = DemoAttribution.spotifyName
        return copy
    }

    var name: String {
        let size = PlayerSizeClass(side: side) == .small ? "S" : (PlayerSizeClass(side: side) == .large ? "L" : "M")
        let scheme = colorScheme == .dark ? "Dark" : "Light"
        return [size, scheme, demoAttribution].compactMap(\.self).joined(separator: " · ")
    }
}

/// What a previewed view sits on.
enum PlayerPreviewBackdrop {
    /// The window's material, as on Echo and Status.
    case material
    /// The demo cover, as on Now. Views over it resolve colors for artwork.
    case artwork
}

/// The objects a player window has, around a demo source.
final class PreviewPlayer {
    let source: PreviewSource
    let store: NowPlayingStore
    let settings = SettingsStore(fileURL: nil)
    let pager = SurfacePager()
    let interaction = PlayerInteraction()
    let services = AppServices()

    init(
        isPlaying: Bool = true,
        demoAttribution: String? = nil,
        revealsControls: Bool = false,
        capabilities: SourceCapabilities = PreviewSource.capabilities
    ) {
        interaction.alwaysReveal = revealsControls
        source = PreviewSource(isPlaying: isPlaying, capabilities: capabilities)
        store = NowPlayingStore(sources: [source], preferredSourceID: .demo)
        services.provide(\.demoAttribution, demoAttribution)
        store.start()
    }
}

extension View {
    /// This view in a demo player's environment, at `preview`'s side and
    /// appearance, laid out in a square of that side or, with `isSquare` off,
    /// at that width. `style` sets the look, as the player's own style would;
    /// a bar (Title, Text, Strip) or Big Art lays out in its own shape that
    /// wide. `revealsControls` shows what hover shows.
    func playerPreview(
        _ preview: PlayerPreviewCase = .largeDark,
        backdrop: PlayerPreviewBackdrop = .material,
        isSquare: Bool = true,
        isPlaying: Bool = true,
        style: PlayerStyleID? = nil,
        revealsControls: Bool = false
    ) -> some View {
        PlayerPreviewHost(
            preview: preview,
            backdrop: backdrop,
            isSquare: isSquare,
            player: PreviewPlayer(
                isPlaying: isPlaying, demoAttribution: preview.demoAttribution, revealsControls: revealsControls
            ),
            style: style,
            content: self
        )
    }
}

/// `content` once per case, labeled.
struct PreviewGallery<Content: View>: View {
    var cases: [PlayerPreviewCase] = PlayerPreviewCase.standard
    var backdrop: PlayerPreviewBackdrop = .material
    var isSquare = true
    var isPlaying = true
    var style: PlayerStyleID?
    var revealsControls = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.l) {
            ForEach(cases) { preview in
                VStack(spacing: Spacing.s) {
                    content()
                        .playerPreview(
                            preview,
                            backdrop: backdrop,
                            isSquare: isSquare,
                            isPlaying: isPlaying,
                            style: style,
                            revealsControls: revealsControls
                        )
                    Text(preview.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Spacing.l)
    }
}

private struct PlayerPreviewHost<Content: View>: View {
    var preview: PlayerPreviewCase
    var backdrop: PlayerPreviewBackdrop
    var isSquare: Bool
    var style: PlayerStyleID?
    var content: Content

    @State private var player: PreviewPlayer

    init(
        preview: PlayerPreviewCase,
        backdrop: PlayerPreviewBackdrop,
        isSquare: Bool,
        player: @autoclosure () -> PreviewPlayer,
        style: PlayerStyleID?,
        content: Content
    ) {
        self.preview = preview
        self.backdrop = backdrop
        self.isSquare = isSquare
        self.style = style
        self.content = content
        _player = State(initialValue: player())
    }

    var body: some View {
        let style = style ?? player.settings.appearance.style
        let shaped = style.isSquare ? nil : style.shape.size(width: Double(preview.side))
        let width = shaped.map { CGFloat($0.width) } ?? preview.side
        let height = shaped.map { CGFloat($0.height) } ?? (isSquare ? preview.side : nil)
        // Size classes follow the width, as the player's do (DESIGN.md §6.1).
        let metrics = PlayerMetrics(side: style.isSquare ? min(width, height ?? width) : width)
        let appearance = LookAppearance(preview.colorScheme)
        let scheme = backdrop == .artwork ? ColorScheme.dark : preview.colorScheme
        player.services.inject(
            content
                .environment(\.colorScheme, scheme)
                .environment(\.humColorContext, backdrop == .artwork ? .artwork : .material)
                .frame(width: width, height: height)
                .background { PlayerPreviewBackground(backdrop: backdrop, artwork: player.store.artwork) }
                .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
                .environment(\.playerMetrics, metrics)
                .environment(\.playerLook, PlayerLook(
                    style: style,
                    look: player.settings.appearance.look(for: style, in: appearance),
                    appearance: appearance,
                    isBar: style.isBar || style.isLandscape
                ))
                .environment(player.store)
                .environment(player.settings)
                .environment(player.pager)
                .environment(player.interaction)
                .environment(\.playerActions, PlayerActions())
        )
        .environment(\.colorScheme, preview.colorScheme)
    }
}

private struct PlayerPreviewBackground: View {
    var backdrop: PlayerPreviewBackdrop
    var artwork: ArtworkImage?

    var body: some View {
        switch backdrop {
        case .material:
            Color(nsColor: .windowBackgroundColor)
        case .artwork:
            if let artwork {
                Image(decorative: artwork.cgImage, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray
            }
        }
    }
}

/// A demo source for previews: one song, playing or paused, with every control
/// (or the ones given) and a cover drawn in code.
final class PreviewSource: PlaybackSource {
    let id = SourceID.demo
    let displayName = "Demo"
    let appBundleIdentifier: String? = nil
    private(set) var state: SourceState
    var onStateChange: (@MainActor (SourceState) -> Void)?

    static let track = Track(
        id: TrackID("preview:1"),
        title: "Paper Lanterns",
        artist: "The Quiet Hours",
        album: "Northern Windows",
        duration: 214
    )

    static let capabilities: SourceCapabilities = [
        .playPause, .skipNext, .skipPrevious, .seek, .volume, .shuffle,
        .repeatAll, .repeatOne, .favorite, .artwork, .scan,
    ]

    init(isPlaying: Bool, capabilities: SourceCapabilities = PreviewSource.capabilities) {
        state = SourceState(
            availability: .running,
            permission: .notRequired,
            capabilities: capabilities,
            snapshot: PlaybackSnapshot(
                track: Self.track,
                status: isPlaying ? .playing : .paused,
                position: 74,
                volume: 0.6,
                shuffle: false,
                repeatMode: .off,
                isFavorite: false
            )
        )
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func requestAutomationPermission() async {}

    func perform(_ command: PlaybackCommand) async throws {}

    func artwork(for track: Track) async -> Data? {
        Self.coverData
    }

    /// A two-color diagonal gradient, encoded as PNG.
    static let coverData: Data? = {
        let side = 600
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let gradient = CGGradient(
            colorsSpace: space,
            colors: [
                CGColor(srgbRed: 0.93, green: 0.55, blue: 0.36, alpha: 1),
                CGColor(srgbRed: 0.27, green: 0.20, blue: 0.52, alpha: 1),
            ] as CFArray,
            locations: [0, 1]
        ) else { return nil }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }()
}
#endif
