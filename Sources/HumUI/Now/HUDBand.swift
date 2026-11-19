import SwiftUI

/// Where a HUD goes on Now, so it never hides what it confirms (DESIGN.md
/// §5.8): over the cover above the controls rather than on the title row.
/// The band places the HUD, which may reach past it while staying inside the
/// player. Without a band, a HUD centers on the player.
///
/// Title, Text and Strip are too short for the capsule: they mark themselves
/// with `hudInline()`, the floating HUD stays hidden, and `BarHUD` puts its
/// glyph and label in place of the bar's content instead.
nonisolated struct HUDBand {
    var bounds: Anchor<CGRect>
    var placement: HUDPlacement
    /// The bar shows the HUD in its own content (`BarHUD`), so the floating
    /// one isn't drawn.
    var isInline = false
}

/// How a HUD lines up with the band it isn't confined to.
nonisolated enum HUDPlacement: Equatable, Sendable {
    case center
    /// Its trailing edge on the band's: over the strip's trailing controls.
    case trailing

    /// The least room left between a HUD and the player's edge.
    static let margin = Spacing.s

    /// The HUD's center, for a HUD `size` big placed by `band` in a player
    /// `bounds` big, kept `margin` inside the player where it fits.
    func center(of size: CGSize, in band: CGRect, within bounds: CGSize) -> CGPoint {
        let x = self == .trailing ? band.maxX - size.width / 2 : band.midX
        return CGPoint(
            x: Self.clamp(x, half: size.width / 2, length: bounds.width),
            y: Self.clamp(band.midY, half: size.height / 2, length: bounds.height)
        )
    }

    private static func clamp(_ value: CGFloat, half: CGFloat, length: CGFloat) -> CGFloat {
        let low = half + margin
        let high = length - half - margin
        // Too big to keep the margin: centered in the player instead.
        guard low <= high else { return length / 2 }
        return min(high, max(low, value))
    }
}

/// The band Now marked. The first one wins.
nonisolated struct HUDBandKey: PreferenceKey {
    static let defaultValue: HUDBand? = nil

    static func reduce(value: inout HUDBand?, nextValue: () -> HUDBand?) {
        value = value ?? nextValue()
    }
}

/// The size of the HUD capsule on show, so its layer can place it.
nonisolated struct HUDSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

extension View {
    /// Mark this view's bounds as where a HUD may be drawn on Now.
    func hudBand(placement: HUDPlacement = .center) -> some View {
        anchorPreference(key: HUDBandKey.self, value: .bounds) {
            HUDBand(bounds: $0, placement: placement)
        }
    }

    /// Mark this bar as showing the HUD in its own content (`BarHUD`), so the
    /// floating capsule isn't drawn over it. Only while `isActive`: on another
    /// surface the HUD floats as usual.
    func hudInline(_ isActive: Bool = true) -> some View {
        anchorPreference(key: HUDBandKey.self, value: .bounds) {
            isActive ? HUDBand(bounds: $0, placement: .center, isInline: true) : nil
        }
    }

    /// Draw `hud` in the band Now marked, or centered on this view without one.
    /// In a bar that shows the HUD inline it's still there, so it keeps its
    /// timing and its announcements, but unseen.
    func hudBandOverlay(@ViewBuilder _ hud: @escaping () -> some View) -> some View {
        modifier(HUDBandOverlay(hud: hud))
    }
}

private struct HUDBandOverlay<HUD: View>: ViewModifier {
    var hud: () -> HUD

    @State private var hudSize: CGSize = .zero

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(HUDBandKey.self) { band in
            GeometryReader { proxy in
                let rect = band.map { proxy[$0.bounds] } ?? CGRect(origin: .zero, size: proxy.size)
                // The HUD keeps the player's width to lay out in, and moves
                // with its layer: the capsule centers in it.
                let center = (band?.placement ?? .center).center(of: hudSize, in: rect, within: proxy.size)
                let isInline = band?.isInline ?? false
                hud()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .position(center)
                    .onPreferenceChange(HUDSizeKey.self) { hudSize = $0 }
                    .opacity(isInline ? 0 : 1)
                    .accessibilityHidden(isInline)
            }
        }
    }
}
