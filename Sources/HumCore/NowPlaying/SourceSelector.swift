import Foundation

/// Chooses which source the player follows.
///
/// A pure function so the rules are easy to test and to explain:
/// 1. A source the user picked in the menu always wins while it's installed.
/// 2. Otherwise, whatever is playing. If several are, the current one stays; failing
///    that, the one that started playing most recently.
/// 3. With nothing playing, the current source stays if it still has a track, so a
///    paused song doesn't vanish because another app launched.
/// 4. Then any running source with a track, preferring the last active one.
/// 5. Then the last active source, if installed.
/// 6. Then the first installed source, in the order sources were registered.
public enum SourceSelector {
    public struct Candidate: Equatable, Sendable {
        public var id: SourceID
        public var state: SourceState
        /// When this source last went from not playing to playing.
        public var startedPlayingAt: Date?

        public init(id: SourceID, state: SourceState, startedPlayingAt: Date? = nil) {
            self.id = id
            self.state = state
            self.startedPlayingAt = startedPlayingAt
        }
    }

    public static func select(
        from candidates: [Candidate],
        current: SourceID?,
        preferred: SourceID?,
        lastActive: SourceID?
    ) -> SourceID? {
        let installed = candidates.filter { $0.state.availability.isInstalled }
        if let preferred, installed.contains(where: { $0.id == preferred }) {
            return preferred
        }

        let playing = installed.filter { $0.state.isPlaying }
        if let current, playing.contains(where: { $0.id == current }) {
            return current
        }
        if let latest = playing.max(by: { ($0.startedPlayingAt ?? .distantPast) < ($1.startedPlayingAt ?? .distantPast) }) {
            return latest.id
        }

        if let current, let candidate = installed.first(where: { $0.id == current }),
           candidate.state.availability.isRunning, candidate.state.hasTrack {
            return current
        }

        let withTrack = installed.filter { $0.state.availability.isRunning && $0.state.hasTrack }
        if let lastActive, withTrack.contains(where: { $0.id == lastActive }) {
            return lastActive
        }
        if let first = withTrack.first {
            return first.id
        }

        if let lastActive, installed.contains(where: { $0.id == lastActive }) {
            return lastActive
        }
        return installed.first?.id
    }
}
