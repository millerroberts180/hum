import AppKit
import HumCore
import SwiftUI

/// Puts the current accent in the environment, and moves it to a new cover's
/// color through OKLCH over `Motion.colorDuration` (faster under Reduce Motion).
/// The accent mode comes from the look in the environment, so each style and
/// appearance can have its own, and the Settings preview can show one the
/// player isn't using.
///
/// An interrupted change starts from the color on screen, never from the old
/// target, so a fast skip never flashes.
struct AccentTransition: ViewModifier {
    @Environment(NowPlayingStore.self) private var store
    @Environment(\.playerLook) private var look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var from = AccentColors.fallback
    @State private var to = AccentColors.fallback
    @State private var start: Date?
    @State private var systemColorsVersion = 0

    func body(content: Content) -> some View {
        let target = targetColors
        TimelineView(.animation(paused: start == nil)) { context in
            content.environment(\.humAccent, displayed(at: context.date))
        }
        .onChange(of: target, initial: true) { old, new in
            if old == new {
                from = new
                to = new
                return
            }
            from = displayed(at: .now)
            to = new
            start = .now
        }
        .task(id: start) {
            guard start != nil else { return }
            try? await Task.sleep(for: .seconds(duration))
            if !Task.isCancelled { start = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)) { _ in
            systemColorsVersion += 1
        }
    }

    private var duration: Double {
        reduceMotion ? Motion.reducedColorDuration : Motion.colorDuration
    }

    private var targetColors: AccentColors {
        _ = systemColorsVersion
        let system = PaletteColor.systemAccent
        let base: PaletteColor = switch look.look.accent {
        case .system: system
        case .album: store.artwork?.palette.accent ?? system
        case .custom: look.look.customAccent
        }
        return AccentColors(base: base, system: system, lightBackground: .lightWindowBackground)
    }

    private func displayed(at date: Date) -> AccentColors {
        guard let start else { return to }
        let progress = min(1, max(0, date.timeIntervalSince(start) / duration))
        return from.interpolated(to: to, fraction: UnitCurve.easeInOut.value(at: progress))
    }
}
