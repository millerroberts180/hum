import HumCore
import SwiftUI

/// What the player is drawn with right now: the chosen style, that style's look
/// in the appearance on screen, and whether the window is currently a bar.
///
/// The player and the Settings preview each put one in the environment, so a
/// style's views never read settings to decide how they look, and the preview
/// can show a look the player isn't using.
nonisolated struct PlayerLook: Equatable, Sendable {
    var style: PlayerStyleID
    var look: StyleLook
    var appearance: LookAppearance
    /// The window is a short bar (Title, Text, Strip) or Wide's landscape
    /// card, which has no page indicator either. One grown to a square for
    /// History or Status is not (DESIGN.md §7.2).
    var isBar: Bool

    init(style: PlayerStyleID, look: StyleLook, appearance: LookAppearance, isBar: Bool) {
        self.style = style
        self.look = look
        self.appearance = appearance
        self.isBar = isBar
    }

    static let standard = PlayerLook(style: .artOnly, look: StyleLook(), appearance: .dark, isBar: false)

    /// The hover controls that show at `sizeClass`: the look's choice, limited to
    /// what that size class has room for (DESIGN.md §6.1).
    func hoverControls(at sizeClass: PlayerSizeClass) -> HoverControls {
        look.hoverControls.intersection(Self.room(at: sizeClass))
    }

    nonisolated static func room(at sizeClass: PlayerSizeClass) -> HoverControls {
        switch sizeClass {
        case .small: [.seekBar, .shuffleRepeat, .save]
        case .medium: [.trackInfo, .album, .seekBar, .shuffleRepeat, .save]
        case .large: .all
        }
    }
}

private nonisolated struct PlayerLookKey: EnvironmentKey {
    static let defaultValue = PlayerLook.standard
}

extension EnvironmentValues {
    nonisolated var playerLook: PlayerLook {
        get { self[PlayerLookKey.self] }
        set { self[PlayerLookKey.self] = newValue }
    }
}

extension LookAppearance {
    init(_ colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }
}

/// Resolves the player's look from settings and the appearance on screen.
struct PlayerLookProvider: ViewModifier {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @State private var isBar = false

    func body(content: Content) -> some View {
        let appearance = LookAppearance(colorScheme)
        let style = settings.appearance.style
        content
            .environment(\.playerLook, PlayerLook(
                style: style,
                look: settings.appearance.look(for: style, in: appearance),
                appearance: appearance,
                isBar: (style.isBar || style.isLandscape) && isBar
            ))
            // Measure the space the window gives, not the size the content
            // asks for: a cover filling a square reports a square even
            // inside a bar, and the bar would never be noticed.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .onGeometryChange(for: Bool.self) { proxy in
                PlayerShapeReader.isBar(proxy.size)
            } action: { value in
                isBar = value
            }
    }
}

nonisolated enum PlayerShapeReader {
    /// A frame at least twice as wide as it is tall, to within a point, is a
    /// bar: Wide's card is exactly twice, whatever rounding the window does.
    /// Squares and Big Art never are, and a bar animating toward a square
    /// stops being one about halfway.
    static func isBar(_ size: CGSize) -> Bool {
        size.height > 0 && size.width + 1 >= size.height * 2
    }
}

/// The look's resting opacity (DESIGN.md §8): the player fades back while
/// nothing is using it, and comes to full for the pointer, the keyboard, a
/// scrub, VoiceOver, or any surface other than Now.
///
/// On macOS 26 a style whose window is glass (Title, Text, Strip) holds its
/// content inside the window's `NSGlassEffectView`, so the window fades glass
/// and content together (`WindowOpacityKey`) and the content stays at full
/// within it, rather than fading twice.
struct PlayerRestingOpacity: ViewModifier {
    @Environment(\.playerLook) private var look
    @Environment(PlayerInteraction.self) private var interaction
    @Environment(SurfacePager.self) private var pager
    @State private var usesWindowGlass = false

    func body(content: Content) -> some View {
        let isFull = interaction.isRevealed || pager.current != .now
        let opacity = Self.opacity(isFull: isFull, resting: look.look.opacity, usesWindowGlass: usesWindowGlass)
        content
            .opacity(opacity.content)
            .animation(isFull ? Motion.reveal : Motion.conceal, value: isFull)
            .onPreferenceChange(WindowGlassKey.self) { usesWindowGlass = $0 }
            .preference(key: WindowOpacityKey.self, value: opacity.window)
    }

    /// How opaque the content and the window's glass are.
    nonisolated static func opacity(isFull: Bool, resting: Double, usesWindowGlass: Bool) -> (content: Double, window: Double) {
        let shown = isFull ? 1 : resting
        return usesWindowGlass ? (1, shown) : (shown, 1)
    }
}

/// The opacity the window's own glass should take (macOS 26).
nonisolated struct WindowOpacityKey: PreferenceKey {
    static let defaultValue = 1.0

    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = min(value, nextValue())
    }
}
