import AppKit
@testable import HumUI
import SwiftUI
import Testing

/// Family 9's states (DESIGN.md §5.9), checked without a window.
@MainActor
@Suite("Action buttons")
struct ActionButtonStyleTests {
    typealias Look = ActionButtonLook

    static func look(
        pressed: Bool = false,
        hovered: Bool = false,
        selected: Bool = false,
        enabled: Bool = true,
        reduceMotion: Bool = false
    ) -> Look {
        Look.resolve(isPressed: pressed, isHovered: hovered, isSelected: selected, isEnabled: enabled, reduceMotion: reduceMotion)
    }

    @Test func atRestItIsASoftTileWithAHairlineEdge() {
        let rest = Self.look()
        #expect(rest == Look.rest)
        #expect(rest.fill == .primary && rest.fillOpacity == 0.05)
        #expect(rest.edge == .primary && rest.edgeOpacity == 0.10 && rest.edgeWidth == 1)
        #expect(rest.glowOpacity == 0)
        #expect(rest.scale == 1)
        #expect(rest.titleWeight == .medium)
        #expect(rest.opacity == 1)
    }

    @Test func hoverDeepensTheFillAndLightsTheEdge() {
        let hover = Self.look(hovered: true)
        #expect(hover.fill == .primary && hover.fillOpacity == 0.10)
        #expect(hover.edge == .accent && hover.edgeOpacity == 0.45 && hover.edgeWidth == 1)
        #expect(hover.scale == 1, "hover never scales")
        #expect(hover.titleWeight == .medium)
    }

    @Test func pressingFillsWithTheAccentGlowsAndScales() {
        let pressed = Self.look(pressed: true, hovered: true)
        #expect(pressed.fill == .accent && pressed.fillOpacity == 0.20)
        #expect(pressed.edge == .accent && pressed.edgeOpacity == 1 && pressed.edgeWidth == 1.5)
        #expect(pressed.glowOpacity == 0.45)
        #expect(pressed.scale == 0.97)
    }

    @Test func reduceMotionPressesWithoutScaling() {
        let pressed = Self.look(pressed: true, reduceMotion: true)
        #expect(pressed.scale == 1)
        #expect(pressed.fill == .accent, "the rest of the press still shows")
        #expect(pressed.glowOpacity == 0.45)
    }

    /// The shown side of a two-way switch, such as the preview's Light and Dark.
    @Test func selectedWearsTheAccentEdgeAndASemiboldTitle() {
        let selected = Self.look(selected: true)
        #expect(selected.fill == .primary && selected.fillOpacity == 0.10)
        #expect(selected.edge == .accent && selected.edgeOpacity == 1 && selected.edgeWidth == 1.5)
        #expect(selected.titleWeight == .semibold)
        #expect(selected.glowOpacity == 0)
        #expect(Self.look(hovered: true, selected: true) == selected, "hover doesn't dim the chosen edge")
        let pressed = Self.look(pressed: true, selected: true)
        #expect(pressed.fill == .accent && pressed.scale == 0.97)
        #expect(pressed.titleWeight == .semibold)
    }

    @Test func disabledIsFainterAndIgnoresHoverAndPress() {
        let disabled = Self.look(enabled: false)
        #expect(disabled.opacity == 0.6)
        #expect(Self.look(pressed: true, hovered: true, enabled: false) == disabled)
        #expect(disabled.fillOpacity == Look.rest.fillOpacity)
        #expect(disabled.scale == 1)
    }

    @Test func titleAndSymbolColors() {
        let label = Color(nsColor: .labelColor)
        let red = Color(nsColor: .systemRed)
        let tertiary = Color(nsColor: .tertiaryLabelColor)
        #expect(Look.titleColor(isEnabled: true, isDestructive: false) == label)
        #expect(Look.titleColor(isEnabled: true, isDestructive: true) == red)
        #expect(Look.titleColor(isEnabled: false, isDestructive: false) == tertiary)
        #expect(Look.titleColor(isEnabled: false, isDestructive: true) == tertiary)
        #expect(Look.symbolColor(isEnabled: true, isDestructive: false) == .accentColor)
        #expect(Look.symbolColor(isEnabled: true, isDestructive: true) == red)
        #expect(Look.symbolColor(isEnabled: false, isDestructive: false) == tertiary)
    }

    @Test func compactIsSmallerWithTighterCorners() {
        #expect(ActionButtonMetrics.cornerRadius(compact: false) == 9)
        #expect(ActionButtonMetrics.cornerRadius(compact: true) == 7)
        #expect(ActionButtonMetrics.titleSize(compact: false) == 12)
        #expect(ActionButtonMetrics.titleSize(compact: true) == 11)
        #expect(ActionButtonMetrics.symbolSize == 11)
        // The default macOS control size (§3.8), and 24 in list rows.
        #expect(ActionButtonMetrics.minHeight == 28)
        #expect(ActionButtonMetrics.compactMinHeight == 24)
    }

    @Test func theStyleDefaultsToARestingRoundedTile() {
        let style = ActionButtonStyle()
        #expect(!style.compact)
        #expect(!style.isSelected)
        #expect(style.shape == .rounded)
        #expect(ActionButtonStyle(shape: .capsule).shape == .capsule)
    }
}
