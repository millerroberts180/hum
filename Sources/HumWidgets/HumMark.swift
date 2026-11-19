import SwiftUI

/// Hum's Vibrato mark, its small-size cut: a level line that ripples twice and
/// settles. The geometry is `vibratoPath(small: true)` in scripts/make-icon.swift
/// (and design/logo/hum-symbol-small.svg), on the same 256-pt grid, y down.
struct HumMark: Shape {
    /// The grid the mark is drawn on.
    static let grid: CGFloat = 256
    /// The small cut's stroke on that grid.
    static let stroke: CGFloat = 32
    /// What the stroked mark covers on the grid, round caps included.
    static let bounds = CGRect(x: 24, y: 80, width: 208, height: 96)

    /// The mark's centerline on the grid.
    static var gridPath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 40, y: 128))
        path.addLine(to: CGPoint(x: 58, y: 128))
        path.addCurve(to: CGPoint(x: 86, y: 96), control1: CGPoint(x: 72, y: 128), control2: CGPoint(x: 72, y: 96))
        path.addCurve(to: CGPoint(x: 114, y: 160), control1: CGPoint(x: 96, y: 96), control2: CGPoint(x: 104, y: 160))
        path.addCurve(to: CGPoint(x: 142, y: 96), control1: CGPoint(x: 124, y: 160), control2: CGPoint(x: 132, y: 96))
        path.addCurve(to: CGPoint(x: 170, y: 160), control1: CGPoint(x: 152, y: 96), control2: CGPoint(x: 160, y: 160))
        path.addCurve(to: CGPoint(x: 198, y: 128), control1: CGPoint(x: 184, y: 160), control2: CGPoint(x: 184, y: 128))
        path.addLine(to: CGPoint(x: 216, y: 128))
        return path
    }

    func path(in rect: CGRect) -> Path {
        // Fit the stroked mark, caps included, into `rect`, centered.
        let bounds = Self.bounds
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        return Self.gridPath.applying(transform)
    }
}

/// The mark, stroked with round caps and joins at its own weight.
struct HumMarkView: View {
    /// The mark's width; its height follows.
    var width: CGFloat

    var body: some View {
        let scale = width / HumMark.bounds.width
        HumMark()
            .stroke(style: StrokeStyle(lineWidth: HumMark.stroke * scale, lineCap: .round, lineJoin: .round))
            .frame(width: width, height: HumMark.bounds.height * scale)
            .accessibilityHidden(true)
    }
}
