import Foundation

/// A damped spring toward zero, solved in closed form.
///
/// The value is the displacement from the target, so animating a page from 1.3 to 2
/// starts at -0.7. Solving analytically (rather than integrating frame by frame) means
/// a dropped frame never changes where the motion goes, and the state at any moment
/// can be read back exactly when a new gesture interrupts it.
nonisolated struct SpringSolver: Equatable, Sendable {
    var parameters: SpringParameters
    /// Displacement at time zero.
    var initialDisplacement: Double
    /// Velocity at time zero, in units per second.
    var initialVelocity: Double

    /// Displacement and velocity this small count as at rest.
    static let restDisplacement = 0.0005
    static let restVelocity = 0.005

    private var angularFrequency: Double { 2 * .pi / max(parameters.response, 0.01) }
    private var damping: Double { max(parameters.dampingRatio, 0) }

    /// Displacement and velocity after `time` seconds.
    func state(at time: Double) -> (displacement: Double, velocity: Double) {
        let t = max(0, time)
        let omega = angularFrequency
        let zeta = damping
        let x0 = initialDisplacement
        let v0 = initialVelocity

        if zeta < 1 {
            let dampedFrequency = omega * (1 - zeta * zeta).squareRoot()
            let decay = exp(-zeta * omega * t)
            let a = x0
            let b = (v0 + zeta * omega * x0) / dampedFrequency
            let cosine = cos(dampedFrequency * t)
            let sine = sin(dampedFrequency * t)
            let displacement = decay * (a * cosine + b * sine)
            let velocity = decay * ((b * dampedFrequency - zeta * omega * a) * cosine
                - (a * dampedFrequency + zeta * omega * b) * sine)
            return (displacement, velocity)
        } else if zeta == 1 {
            let decay = exp(-omega * t)
            let b = v0 + omega * x0
            return (decay * (x0 + b * t), decay * (v0 - omega * b * t))
        } else {
            let root = (zeta * zeta - 1).squareRoot()
            let r1 = -omega * (zeta - root)
            let r2 = -omega * (zeta + root)
            let c2 = (v0 - r1 * x0) / (r2 - r1)
            let c1 = x0 - c2
            let e1 = exp(r1 * t)
            let e2 = exp(r2 * t)
            return (c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2)
        }
    }

    func isAtRest(at time: Double) -> Bool {
        let (displacement, velocity) = state(at: time)
        return abs(displacement) < Self.restDisplacement && abs(velocity) < Self.restVelocity
    }
}
