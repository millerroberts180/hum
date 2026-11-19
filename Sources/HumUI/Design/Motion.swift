import SwiftUI

/// Every animation curve, duration, and spring in Hum.
///
/// Springs for anything interactive; short ease-outs only for opacity reveals.
/// Under Reduce Motion every spatial or scale animation becomes `crossfade`.
enum Motion {
    /// Strong ease-out: fast start, gentle landing. The curve for things arriving
    /// or leaving.
    static func easeOut(_ duration: Double) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    /// The same ease-out for AppKit animations.
    static var easeOutCurve: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    }

    static func spring(_ parameters: SpringParameters) -> Animation {
        .spring(response: parameters.response, dampingFraction: parameters.dampingRatio)
    }

    // MARK: Reduce Motion

    /// `animation` for something that moves or scales, or `crossfade` under
    /// Reduce Motion (DESIGN.md §3.7, §9). Every spatial or scale animation goes
    /// through here.
    static func spatial(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? crossfade : animation
    }

    /// Palette colors moving to a new cover's (`Motion.color`), shortened under
    /// Reduce Motion: color isn't spatial, so it still changes, only faster.
    static func color(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? reducedColorDuration : colorDuration)
    }

    // MARK: Press

    /// Pressed visuals, on mouse-down.
    static let press = easeOut(0.10)
    /// A pressed look holds at least this long, so even a quick click shows.
    static let minimumPress: Duration = .milliseconds(80)
    /// How far the pointer may drift outside a hit target before a press cancels.
    static let pressHysteresis: CGFloat = 10

    // MARK: Springs

    /// Hover backings, toggles, chips; also the release after a press.
    static let snappySpring = SpringParameters(response: 0.25, dampingRatio: 1)
    static let snappy = spring(snappySpring)
    /// Layout changes, popovers opening, an optimistic state reverting.
    static let smoothSpring = SpringParameters(response: 0.35, dampingRatio: 1)
    static let smooth = spring(smoothSpring)
    /// Switching player style: the old layout giving way and the window taking
    /// the new shape, together. `smooth`, unless a debug build was launched with
    /// `--slow-motion`.
    static var styleSwitchSpring: SpringParameters {
        #if DEBUG
        SpringParameters(response: smoothSpring.response * slowMotion, dampingRatio: smoothSpring.dampingRatio)
        #else
        smoothSpring
        #endif
    }
    static var styleSwitch: Animation { spring(styleSwitchSpring) }
    #if DEBUG
    /// `--slow-motion N`: how many times slower style switches run.
    static var slowMotion: Double = 1
    #endif
    /// Surfaces appearing: popovers, the HUD, the window.
    static let materializeSpring = SpringParameters(response: 0.30, dampingRatio: 1)
    static let materialize = spring(materializeSpring)
    static let materializeScale: CGFloat = 0.96
    static let materializeBlur: CGFloat = 6
    /// A thrown window settling on its snap target.
    static let throwSpring = SpringParameters(response: 0.40, dampingRatio: 1)
    /// Deceleration used to project where a throw or flick would come to rest.
    static let decelerationRate = 0.998
    /// Surface change from a click or key.
    static let pageDirect = SpringParameters(response: 0.32, dampingRatio: 1)
    /// Surface change after a swipe. The only spring allowed to overshoot, because
    /// a flick preceded it.
    static let pageMomentum = SpringParameters(response: 0.40, dampingRatio: 0.85)

    // MARK: Fades

    /// Hover controls appearing, with `revealTravel` of upward travel.
    static let reveal = easeOut(revealDuration)
    static let revealDuration = 0.18
    static let revealTravel: CGFloat = 8
    /// Hover controls leaving, as soon as the pointer does. A pointer coming
    /// back mid-fade turns it around.
    static let conceal = easeOut(concealDuration)
    static let concealDuration = 0.18
    /// How long a HUD stays after the last change before it conceals.
    static let hudHold: Duration = .milliseconds(1200)
    /// Reduce Motion's replacement for every spatial animation, and plain fades.
    static let crossfade = easeOut(crossfadeDuration)
    static let crossfadeDuration = 0.20
    /// Before a status spinner appears at all.
    static let spinnerDelay: Duration = .milliseconds(400)

    // MARK: Track change

    /// The new cover fading in over the old one, settling from `trackChangeScale`.
    static let trackChangeArtwork = easeOut(0.30)
    static let trackChangeScale: CGFloat = 1.02
    /// Title and artist sliding `trackChangeTravel` in from the side the track
    /// came from, and fading.
    static let trackChangeText = easeOut(0.22)
    static let trackChangeTravel: CGFloat = 6

    // MARK: Color

    /// Palette-driven colors moving to a new cover's, in OKLCH.
    static let colorDuration = 0.45
    /// Color still changes under Reduce Motion (it isn't spatial), only faster.
    static let reducedColorDuration = 0.2

    // MARK: Marquee

    static let marqueeDelay: Duration = .seconds(1)
    /// Points per second.
    static let marqueeSpeed: CGFloat = 30
    static let marqueeEndPause: Duration = .milliseconds(1500)
}

/// Apple's designer-facing spring description: how quickly it gets there, and how
/// much it overshoots (1 = none).
nonisolated struct SpringParameters: Equatable, Sendable {
    var response: Double
    var dampingRatio: Double
}

extension View {
    /// `.symbolEffect(.bounce)` each time `value` changes, as a skip or Save
    /// commits, and nothing under Reduce Motion (DESIGN.md §3.7).
    func commitBounce<Value: Equatable>(_ effect: BounceSymbolEffect = .bounce, value: Value) -> some View {
        modifier(CommitBounce(effect: effect, value: value))
    }
}

private struct CommitBounce<Value: Equatable>: ViewModifier {
    var effect: BounceSymbolEffect
    var value: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // A value that never changes never triggers the effect.
        content.symbolEffect(effect, value: reduceMotion ? nil : Optional(value))
    }
}
