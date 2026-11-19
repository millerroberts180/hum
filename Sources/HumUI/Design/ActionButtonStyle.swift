import AppKit
import SwiftUI

/// DESIGN.md §5.9, family 9.
///
/// A soft rounded tile with a hairline edge, for every button in Settings and
/// the buttons in the Listening History window's content. Label it with an
/// `ActionLabel`: an optional accent symbol, then the title.
///
/// Hover lights the edge; pressing fills the tile with the accent, glows, and
/// scales it to 0.97 from mouse-down, and the action commits on mouse-up
/// inside. `isSelected` marks the shown side of a two-way switch, such as the
/// preview's Light and Dark. A `Button(role: .destructive)` draws its title
/// and symbol in `systemRed`. `compact` is for buttons inside list rows, and
/// `.capsule` is family 10's shape (the pill menus).
///
/// The accent is the system's, as on the choice tiles' ring: Hum's own accent
/// belongs to the player.
struct ActionButtonStyle: ButtonStyle {
    enum Shape { case rounded, capsule }

    var compact = false
    var isSelected = false
    var shape: Shape = .rounded

    func makeBody(configuration: Configuration) -> some View {
        ActionButtonBody(
            configuration: configuration,
            compact: compact,
            isSelected: isSelected,
            isCapsule: shape == .capsule
        )
    }
}

/// An optional accent symbol, then the title.
struct ActionLabel: View {
    var title: String
    var symbol: String?

    init(_ title: String, symbol: String? = nil) {
        self.title = title
        self.symbol = symbol
    }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.actionButtonIsDestructive) private var isDestructive

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: ActionButtonMetrics.symbolSize, weight: .semibold))
                    .foregroundStyle(ActionButtonLook.symbolColor(isEnabled: isEnabled, isDestructive: isDestructive))
                    // The title names the button; the symbol only illustrates it.
                    .accessibilityHidden(true)
            }
            Text(title)
        }
    }
}

/// Family 9's measurements (DESIGN.md §5.9).
nonisolated enum ActionButtonMetrics {
    static let cornerRadius: CGFloat = 9
    static let compactCornerRadius: CGFloat = 7
    static let titleSize: CGFloat = 12
    static let compactTitleSize: CGFloat = 11
    static let symbolSize: CGFloat = 11
    /// The tile's height, at least: the default macOS control size (§3.8),
    /// and 24 for the compact buttons in list rows.
    static let minHeight: CGFloat = 28
    static let compactMinHeight: CGFloat = 24
    static let horizontalPadding = Spacing.m
    static let compactHorizontalPadding = Spacing.s
    static let verticalPadding = Spacing.xs
    /// The accent glow while pressed.
    static let glowRadius: CGFloat = 5
    /// How long the edge takes to light up, and the fill to deepen, on hover.
    static let hoverDuration = 0.12

    static func cornerRadius(compact: Bool) -> CGFloat {
        compact ? compactCornerRadius : cornerRadius
    }

    static func titleSize(compact: Bool) -> CGFloat {
        compact ? compactTitleSize : titleSize
    }
}

/// What an action button looks like in one state, apart from the view
/// (DESIGN.md §5.9, family 9's row of the states table).
nonisolated struct ActionButtonLook: Equatable {
    enum Tint: Equatable {
        /// `primary`: black in light, white in dark.
        case primary
        /// The system accent.
        case accent
    }

    var fill: Tint
    var fillOpacity: Double
    var edge: Tint
    var edgeOpacity: Double
    var edgeWidth: CGFloat
    /// The accent glow's opacity; zero for none.
    var glowOpacity: Double
    var scale: CGFloat
    var titleWeight: Font.Weight
    /// The whole button's opacity: 0.6 while disabled.
    var opacity: Double

    static let rest = ActionButtonLook(
        fill: .primary, fillOpacity: 0.05,
        edge: .primary, edgeOpacity: 0.10, edgeWidth: 1,
        glowOpacity: 0, scale: 1, titleWeight: .medium, opacity: 1
    )

    /// The look for a state. A disabled button takes no hover or press; a
    /// press shows over the selected look.
    static func resolve(
        isPressed: Bool,
        isHovered: Bool,
        isSelected: Bool,
        isEnabled: Bool,
        reduceMotion: Bool = false
    ) -> ActionButtonLook {
        var look = rest
        if isSelected {
            look.fillOpacity = 0.10
            look.edge = .accent
            look.edgeOpacity = 1
            look.edgeWidth = 1.5
            look.titleWeight = .semibold
        }
        guard isEnabled else {
            look.opacity = 0.6
            return look
        }
        if isPressed {
            look.fill = .accent
            look.fillOpacity = 0.20
            look.edge = .accent
            look.edgeOpacity = 1
            look.edgeWidth = 1.5
            look.glowOpacity = 0.45
            // Reduce Motion: no scale (§9).
            look.scale = reduceMotion ? 1 : 0.97
        } else if isHovered, !isSelected {
            look.fillOpacity = 0.10
            look.edge = .accent
            look.edgeOpacity = 0.45
        }
        return look
    }

    /// The title's color: `label`, `systemRed` for a destructive button, and
    /// `tertiaryLabel` while disabled.
    static func titleColor(isEnabled: Bool, isDestructive: Bool) -> Color {
        if !isEnabled { return Color(nsColor: .tertiaryLabelColor) }
        return isDestructive ? Color(nsColor: .systemRed) : Color(nsColor: .labelColor)
    }

    /// The symbol's color: the accent, `systemRed` for a destructive button,
    /// and `tertiaryLabel` while disabled.
    static func symbolColor(isEnabled: Bool, isDestructive: Bool) -> Color {
        if !isEnabled { return Color(nsColor: .tertiaryLabelColor) }
        return isDestructive ? Color(nsColor: .systemRed) : .accentColor
    }

    static func color(_ tint: Tint) -> Color {
        switch tint {
        case .primary: .primary
        case .accent: .accentColor
        }
    }
}

// Not named `Button`, which would shadow SwiftUI's inside the style.
private struct ActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let compact: Bool
    let isSelected: Bool
    let isCapsule: Bool

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isCapsule {
            tile(Capsule(style: .continuous))
        } else {
            tile(RoundedRectangle(cornerRadius: ActionButtonMetrics.cornerRadius(compact: compact), style: .continuous))
        }
    }

    private func tile<TileShape: InsettableShape>(_ shape: TileShape) -> some View {
        let isPressed = configuration.isPressed
        let isDestructive = configuration.role == .destructive
        let look = ActionButtonLook.resolve(
            isPressed: isPressed,
            isHovered: isHovered,
            isSelected: isSelected,
            isEnabled: isEnabled,
            reduceMotion: reduceMotion
        )
        return configuration.label
            .font(.system(size: ActionButtonMetrics.titleSize(compact: compact), weight: look.titleWeight))
            .foregroundStyle(ActionButtonLook.titleColor(isEnabled: isEnabled, isDestructive: isDestructive))
            .environment(\.actionButtonIsDestructive, isDestructive)
            .lineLimit(1)
            .padding(.horizontal, compact ? ActionButtonMetrics.compactHorizontalPadding : ActionButtonMetrics.horizontalPadding)
            .padding(.vertical, ActionButtonMetrics.verticalPadding)
            .frame(minHeight: compact ? ActionButtonMetrics.compactMinHeight : ActionButtonMetrics.minHeight)
            .background(shape.fill(ActionButtonLook.color(look.fill).opacity(look.fillOpacity)))
            .overlay(shape.strokeBorder(ActionButtonLook.color(look.edge).opacity(look.edgeOpacity), lineWidth: look.edgeWidth))
            .shadow(color: Color.accentColor.opacity(look.glowOpacity), radius: ActionButtonMetrics.glowRadius)
            .scaleEffect(look.scale)
            .opacity(look.opacity)
            .contentShape(.interaction, shape)
            .contentShape(.focusEffect, shape)
            // Down with `press`, back with `snappy` (§5.9).
            .animation(isPressed ? Motion.press : Motion.snappy, value: isPressed)
            .animation(Motion.easeOut(ActionButtonMetrics.hoverDuration), value: isHovered)
            .onHover { isHovered = $0 }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private nonisolated struct ActionButtonIsDestructiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set by `ActionButtonStyle` for a `Button(role: .destructive)`, so its
    /// `ActionLabel` draws the symbol in `systemRed` too.
    nonisolated var actionButtonIsDestructive: Bool {
        get { self[ActionButtonIsDestructiveKey.self] }
        set { self[ActionButtonIsDestructiveKey.self] = newValue }
    }
}
