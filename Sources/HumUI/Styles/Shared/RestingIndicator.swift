import HumCore
import SwiftUI

/// Playback position while the controls are hidden: nothing (the default), the
/// 2-pt hairline along the bottom, or a 2-pt ring just inside the panel edge
/// (DESIGN.md §5.2).
///
/// Colors come from the color context, so the same indicator works over the
/// cover (white, with a soft shadow) and on material or a tint. It updates only
/// as often as it can visibly move, and not at all while paused, hidden, or off
/// screen.
struct RestingIndicator: View {
    var kind: ProgressIndicator
    var isHidden: Bool

    @Environment(NowPlayingStore.self) private var store
    @Environment(PlayerInteraction.self) private var interaction
    @Environment(\.surfaceIsActive) private var surfaceIsActive
    @Environment(\.playerMetrics) private var metrics
    @Environment(\.humColorContext) private var context

    /// How far the hairline sits above the bottom edge.
    static let lineInset = Spacing.s
    /// How far the ring's centerline sits inside the panel edge.
    static let ringInset = Spacing.xxs

    var body: some View {
        if kind != .none {
            TimelineView(.animation(minimumInterval: interval, paused: isPaused)) { timeline in
                let fraction = min(1, max(0, store.progress(at: timeline.date) ?? 0))
                switch kind {
                case .none: EmptyView()
                case .line: line(fraction)
                case .ring: ring(fraction)
                }
            }
            .humShadow(context == .artwork ? .glyphOnArt : .none)
            .opacity(isHidden ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func line(_ fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(HumColor.trackFill)
                Capsule()
                    .fill(HumColor.label)
                    .frame(width: max(SliderMetrics.hairline, proxy.size.width * fraction))
            }
        }
        .frame(height: SliderMetrics.hairline)
        .padding(.horizontal, metrics.cornerRadius)
        .padding(.bottom, Self.lineInset)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func ring(_ fraction: Double) -> some View {
        let shape = PanelRing(cornerRadius: max(0, metrics.cornerRadius - Self.ringInset))
        return ZStack {
            shape.stroke(HumColor.trackFill, lineWidth: SliderMetrics.hairline)
            shape
                .trim(from: 0, to: fraction)
                .stroke(HumColor.label, style: StrokeStyle(lineWidth: SliderMetrics.hairline, lineCap: .round))
        }
        .padding(Self.ringInset)
    }

    private var isPaused: Bool {
        isHidden || !store.isPlaying || !surfaceIsActive || !interaction.isWindowVisible
    }

    /// Seconds per point of travel, so each update moves it about a point.
    private var interval: Double {
        guard let duration = store.clock.duration, duration > 0 else { return 1 }
        let travel = kind == .ring ? metrics.side * 4 : metrics.side - metrics.cornerRadius * 2
        return min(1, max(0.25, duration / max(travel, 1)))
    }
}

/// A rounded rectangle traced clockwise from the middle of its top edge, so a
/// trimmed stroke grows like a clock hand from twelve o'clock.
nonisolated struct PanelRing: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.midX, y: rect.minY), radius: radius)
        path.closeSubpath()
        return path
    }
}
