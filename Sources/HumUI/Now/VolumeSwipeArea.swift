import SwiftUI

/// The part of Now where a vertical two-finger swipe sets the volume: the cover.
/// The root view resolves it into `PlayerInteraction.volumeSwipeArea`.
nonisolated struct VolumeSwipeAreaKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Mark this view, Now's cover, as where a vertical swipe sets the volume.
    func volumeSwipeArea() -> some View {
        anchorPreference(key: VolumeSwipeAreaKey.self, value: .bounds) { $0 }
    }
}
