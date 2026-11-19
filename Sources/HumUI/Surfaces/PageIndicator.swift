import HumCore
import SwiftUI

/// Three marks, one per surface (Now, History, Status), that track the swipe
/// continuously: the mark for the page in view stretches, and it hands that
/// width to its neighbor as the page moves. Each mark is a button with a whole
/// hit target (§3.8): its slot is that wide, and reaches past the capsule above
/// and below.
///
/// It shows only while the page changes (`PageIndicatorVisibility`, DESIGN.md
/// §6). While it shows, VoiceOver reads it as one adjustable element, "Now,
/// 1 of 3", that swipes up and down through the surfaces (§9); hidden, it's
/// out of VoiceOver's way, and the player's Next Surface and Previous Surface
/// actions move between surfaces.
struct PageIndicator: View {
    @Environment(SurfacePager.self) private var pager
    @Environment(\.playerMetrics) private var metrics

    static let restWidth: CGFloat = 6
    static let selectedExtraWidth: CGFloat = 10
    nonisolated static let markHeight: CGFloat = 6
    /// Above and below each mark, inside the capsule.
    nonisolated static let markPadding: CGFloat = 6
    nonisolated static let height: CGFloat = markHeight + markPadding * 2

    /// The indicator's top edge, from the player's top edge: just inside the
    /// content inset.
    nonisolated static func top(inset: CGFloat) -> CGFloat {
        inset - Spacing.xs
    }

    /// How far below the content inset a surface's content starts so it never
    /// meets the indicator: its whole height, plus `Spacing.xs` of air.
    nonisolated static var contentClearance: CGFloat {
        top(inset: 0) + height + Spacing.xs
    }

    /// Where the indicator sits in a player `width` wide: centered at
    /// `top(inset:)`, one whole hit target per surface.
    static func frame(width: CGFloat, metrics: PlayerMetrics) -> CGRect {
        let hit = ControlSizing.minimumHit(metrics.sizeClass, isTertiary: true)
        let indicatorWidth = hit * CGFloat(Surface.allCases.count)
        return CGRect(
            x: (width - indicatorWidth) / 2,
            y: top(inset: metrics.contentInset),
            width: indicatorWidth,
            height: height
        )
    }

    var body: some View {
        let hit = ControlSizing.minimumHit(metrics.sizeClass, isTertiary: true)
        HStack(spacing: 0) {
            ForEach(Surface.allCases) { surface in
                let emphasis = Self.emphasis(of: surface, at: pager.position)
                Button {
                    pager.go(to: surface, animated: true)
                } label: {
                    // The page in view brightens from `quaternaryLabel` to `label`.
                    Capsule()
                        .fill(HumColor.quaternaryLabel)
                        .overlay { Capsule().fill(HumColor.label).opacity(emphasis) }
                        .frame(width: Self.restWidth + Self.selectedExtraWidth * emphasis, height: Self.markHeight)
                        .frame(width: hit, height: hit)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The target overhangs the capsule rather than making it taller.
                .padding(.vertical, -(hit - Self.height) / 2)
                .help("\(surface.title) (⌘\(surface.index + 1))")
            }
        }
        .frame(height: Self.height)
        // Interactive on macOS 26, since the capsule is itself a control.
        .floatingGlass(in: Capsule(), interactive: true, fallback: .glassCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Surface")
        .accessibilityValue(Self.spokenValue(pager.current))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: pager.forward(animated: true)
            case .decrement: pager.back(animated: true)
            @unknown default: break
            }
        }
    }

    /// "Now, 1 of 3".
    nonisolated static func spokenValue(_ surface: Surface) -> String {
        "\(surface.title), \(surface.index + 1) of \(Surface.allCases.count)"
    }

    /// 1 for the page in view, falling to 0 one page away.
    nonisolated static func emphasis(of surface: Surface, at position: Double) -> Double {
        max(0, 1 - abs(Double(surface.index) - position))
    }
}

#if DEBUG
struct PageIndicator_Previews: PreviewProvider {
    static var previews: some View {
        PreviewGallery(backdrop: .artwork, isSquare: false) {
            PageIndicator().padding(Spacing.m)
        }
    }
}
#endif
