import SwiftUI

/// The sizes of a list row (DESIGN.md §5.5, §3.8), which other layouts measure
/// against, such as Minimal's smallest cover.
nonisolated enum RowMetrics {
    static let smallHeight: CGFloat = 40
    static let mediumHeight: CGFloat = 44
    static let largeHeight: CGFloat = 52

    static let smallArt: CGFloat = 28
    static let mediumArt: CGFloat = 32
    static let largeArt: CGFloat = 40

    static func height(_ sizeClass: PlayerSizeClass) -> CGFloat {
        switch sizeClass {
        case .small: smallHeight
        case .medium: mediumHeight
        case .large: largeHeight
        }
    }

    static func artSide(_ sizeClass: PlayerSizeClass) -> CGFloat {
        switch sizeClass {
        case .small: smallArt
        case .medium: mediumArt
        case .large: largeArt
        }
    }
}
