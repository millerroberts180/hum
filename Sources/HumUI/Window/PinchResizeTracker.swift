import AppKit
import HumCore

/// A pinch on the player stepping it between size classes (DESIGN.md §4.2):
/// spreading the fingers grows it, pinching them shrinks it. Each `threshold`
/// of magnification is one step, so a long pinch can cross two classes.
nonisolated struct PinchResizeTracker: Equatable, Sendable {
    enum Step: Equatable, Sendable {
        case grow
        case shrink
    }

    enum Phase: Equatable, Sendable {
        case began
        case changed
        case ended
    }

    /// Magnification, summed over the gesture, that makes one step.
    static let threshold = 0.15

    private var total = 0.0

    mutating func handle(_ phase: Phase, magnification: Double) -> Step? {
        switch phase {
        case .began:
            total = magnification
        case .changed:
            total += magnification
        case .ended:
            total = 0
            return nil
        }
        guard abs(total) >= Self.threshold else { return nil }
        let step: Step = total > 0 ? .grow : .shrink
        total = 0
        return step
    }
}

extension PinchResizeTracker.Phase {
    init?(_ phase: NSEvent.Phase) {
        if phase.contains(.began) {
            self = .began
        } else if phase.contains(.changed) || phase.contains(.stationary) {
            self = .changed
        } else if phase.contains(.ended) || phase.contains(.cancelled) {
            self = .ended
        } else {
            return nil
        }
    }
}

extension PlayerSizePreset {
    /// The next size up or down, or nil past either end.
    func stepped(_ step: PinchResizeTracker.Step) -> PlayerSizePreset? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return nil }
        let next = step == .grow ? all.index(after: index) : index - 1
        return all.indices.contains(next) ? all[next] : nil
    }
}
