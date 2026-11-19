import HumCore
import SwiftUI

/// A flat fill that moves to a new cover's color through OKLCH (DESIGN.md
/// §3.5.5) over `Motion.colorDuration`, faster under Reduce Motion, as the
/// accent does (`AccentTransition`). SwiftUI would blend the two in sRGB, which
/// dulls and darkens the colors between.
///
/// An interrupted change starts from the color on screen, never from the old
/// target, so a fast skip never flashes.
struct PaletteFill: View {
    private let color: PaletteColor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var from: PaletteColor
    @State private var to: PaletteColor
    @State private var start: Date?

    init(_ color: PaletteColor) {
        self.color = color
        _from = State(initialValue: color)
        _to = State(initialValue: color)
    }

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { context in
            Color(displayed(at: context.date))
        }
        .onChange(of: color) { _, new in
            from = displayed(at: .now)
            to = new
            start = .now
        }
        .task(id: start) {
            guard start != nil else { return }
            try? await Task.sleep(for: .seconds(duration))
            if !Task.isCancelled { start = nil }
        }
        .accessibilityHidden(true)
    }

    private var duration: Double {
        reduceMotion ? Motion.reducedColorDuration : Motion.colorDuration
    }

    private func displayed(at date: Date) -> PaletteColor {
        guard let start else { return to }
        let progress = min(1, max(0, date.timeIntervalSince(start) / duration))
        return from.interpolated(to: to, fraction: UnitCurve.easeInOut.value(at: progress))
    }
}
