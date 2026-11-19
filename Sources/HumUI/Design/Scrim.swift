import HumCore
import SwiftUI

/// The gradient behind controls over artwork: black from 0% at the top of its
/// band to 55%.
///
/// The band covers the lower 45% of the cover, or more when the controls are
/// taller, and holds at the peak behind the controls, so every line of text sits
/// on the full darkening however bright the art. Above the band a feather of
/// about a sixth of the cover carries the rise further up, on a curve that
/// leaves the art with no slope at either end, so there is no line where the
/// darkening starts or where it levels off. Increase Contrast deepens it to
/// 75%; Reduce Transparency makes it a solid 70% band.
struct Scrim: View {
    /// The height of the controls the scrim sits behind.
    var contentHeight: CGFloat

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    nonisolated static let coverage = 0.45
    nonisolated static let peak = 0.55
    nonisolated static let increasedContrastPeak = 0.75
    nonisolated static let reducedTransparencyOpacity = 0.7
    /// The feather above the band, as a share of the cover.
    nonisolated static let featherShare = 0.16

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.height
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if reduceTransparency {
                    Rectangle()
                        .fill(.black.opacity(Self.reducedTransparencyOpacity))
                        .frame(height: Self.bandHeight(side: side, contentHeight: contentHeight))
                } else {
                    let height = Self.featheredHeight(side: side, contentHeight: contentHeight)
                    LinearGradient(
                        stops: Self.stops(
                            peak: contrast == .increased ? Self.increasedContrastPeak : Self.peak,
                            ramp: Self.ramp(height: height, contentHeight: contentHeight)
                        ),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: height)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 45% of the cover, or the controls plus `Spacing.xxl` of ramp above them.
    nonisolated static func bandHeight(side: CGFloat, contentHeight: CGFloat) -> CGFloat {
        min(side, max(side * coverage, contentHeight + Spacing.xxl))
    }

    /// The band plus the feather above it, never taller than the cover.
    nonisolated static func featheredHeight(side: CGFloat, contentHeight: CGFloat) -> CGFloat {
        let feather = max(Spacing.xxl, side * featherShare)
        return min(side, bandHeight(side: side, contentHeight: contentHeight) + feather)
    }

    /// The share of a scrim `height` tall that rises, above controls
    /// `contentHeight` tall that sit on the peak.
    nonisolated static func ramp(height: CGFloat, contentHeight: CGFloat) -> Double {
        height > 0 ? Double(max(0, height - contentHeight) / height) : 1
    }

    /// Opacity at `location` (0 at the top of the band, 1 at the bottom): a rise
    /// over the first `ramp` of the band that starts and ends flat, then the peak.
    nonisolated static func opacity(at location: Double, peak: Double, ramp: Double) -> Double {
        guard ramp > 0 else { return peak }
        let t = min(1, max(0, location / ramp))
        return peak * t * t * t * (t * (t * 6 - 15) + 10)
    }

    /// How far the darkening has risen at `location`, from 0 to 1.
    nonisolated static func rise(at location: Double, ramp: Double) -> Double {
        opacity(at: location, peak: 1, ramp: ramp)
    }

    nonisolated static func stops(peak: Double, ramp: Double) -> [Gradient.Stop] {
        let count = 16
        let rise = (0...count).map { step in
            let location = ramp * Double(step) / Double(count)
            return Gradient.Stop(color: .black.opacity(opacity(at: location, peak: peak, ramp: ramp)), location: location)
        }
        return ramp < 1 ? rise + [Gradient.Stop(color: .black.opacity(peak), location: 1)] : rise
    }
}
