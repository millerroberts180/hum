import HumCore
import Observation

/// The player's size and pin, for Settings and the player's menu: the size the
/// current style rests at, where the player is pinned, and ways to pick
/// another. The window controller keeps it current.
@Observable
public final class PlayerSizing {
    /// The size the window comes back to for the current style, not counting a
    /// temporary expansion for Echo or Status. `nil` until the player has been
    /// placed.
    public internal(set) var size: PlayerSize?
    @ObservationIgnored var resize: ((PlayerSizePreset) -> Void)?
    /// Where the player is pinned on its display (DESIGN.md §4.5), or `nil` when
    /// it was dropped somewhere with snapping off.
    public internal(set) var pin: PinPosition?
    @ObservationIgnored var repin: ((PinPosition) -> Void)?
    @ObservationIgnored var reveal: (() -> Void)?

    public init() {}

    /// Spring the player to `preset`, holding the corner against the screen
    /// edge still. A hidden player opens at it next time.
    public func apply(_ preset: PlayerSizePreset) {
        resize?(preset)
    }

    /// Move the player to `position` with `Motion.throw` and pin it there. A
    /// hidden player opens there next time.
    public func pin(to position: PinPosition) {
        repin?(position)
    }

    /// Show the player's hover controls for a moment, as if pointed at, so a
    /// change in Settings can be seen. Nothing while the player is hidden or
    /// in Menu Bar.
    public func revealControls() {
        reveal?()
    }
}
