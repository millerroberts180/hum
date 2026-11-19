import Foundation

/// The devices the active source can play on, with an explicit state.
///
/// `value` survives a refresh: while the list is asked for again the phase is
/// `.loading` and the last list stays on screen until the new one replaces it.
public struct DeviceList: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Nothing asked for yet.
        case idle
        case loading
        case loaded
        /// The last load failed, in plain words.
        case failed(String)
        /// The source can't list its devices, and why.
        case unavailable(LibraryUnavailable)
    }

    public var value: [PlaybackDevice]?
    public var phase: Phase
    public var loadedAt: Date?

    public init(value: [PlaybackDevice]? = nil, phase: Phase = .idle, loadedAt: Date? = nil) {
        self.value = value
        self.phase = phase
        self.loadedAt = loadedAt
    }

    /// Loading with nothing to show yet.
    public var isLoadingFirstTime: Bool { phase == .loading && value == nil }

    public var failure: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    public var unavailable: LibraryUnavailable? {
        if case .unavailable(let reason) = phase { return reason }
        return nil
    }

    /// Whether a load should start now, given when the last one finished.
    public func isStale(at date: Date, maxAge: TimeInterval) -> Bool {
        guard phase != .loading else { return false }
        guard let loadedAt, phase == .loaded else { return true }
        return date.timeIntervalSince(loadedAt) >= maxAge
    }
}
