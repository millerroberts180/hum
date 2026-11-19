import CoreGraphics

/// The spacing scale, on a 4-pt grid. Every gap in the player comes from here.
nonisolated enum Spacing {
    /// Hairline insets and badge padding.
    static let xxs: CGFloat = 2
    /// Icon-to-label gap inside a control.
    static let xs: CGFloat = 4
    /// Between related controls.
    static let s: CGFloat = 8
    /// Small card padding; section gap in compact layouts.
    static let m: CGFloat = 12
    /// Default card padding; window content inset.
    static let l: CGFloat = 16
    /// Between sections.
    static let xl: CGFloat = 24
    /// Section breaks in expanded views.
    static let xxl: CGFloat = 32
}
