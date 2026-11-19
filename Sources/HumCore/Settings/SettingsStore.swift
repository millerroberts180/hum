import Foundation
import Observation

/// Loads, holds, and saves `HumSettings`.
///
/// Each section is its own observable property, so a view that reads `appearance`
/// doesn't re-render when the window moves. Window memory is not observed at all:
/// it changes on every drag and nothing renders from it.
///
/// Changes are saved after a short pause, atomically; call `flush()` before quitting.
@MainActor
@Observable
public final class SettingsStore {
    public var behavior: BehaviorSettings {
        didSet { if behavior != oldValue { scheduleSave() } }
    }
    public var appearance: AppearanceSettings {
        didSet { if appearance != oldValue { scheduleSave() } }
    }
    public var shortcuts: ShortcutSettings {
        didSet { if shortcuts != oldValue { scheduleSave() } }
    }
    public var playback: PlaybackSettings {
        didSet { if playback != oldValue { scheduleSave() } }
    }
    public var history: HistorySettings {
        didSet { if history != oldValue { scheduleSave() } }
    }
    @ObservationIgnored public var window: WindowMemory {
        didSet { if window != oldValue { scheduleSave() } }
    }

    /// `nil` for a store that never touches disk (tests, previews).
    @ObservationIgnored public let fileURL: URL?
    /// Set when the file on disk couldn't be read and was moved aside.
    @ObservationIgnored public private(set) var quarantinedFile: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void

    /// - Parameter sleep: How a save waits out `saveDelay`; tests pass their own.
    public init(
        fileURL: URL?,
        saveDelay: Duration = .milliseconds(400),
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.fileURL = fileURL
        self.saveDelay = saveDelay
        self.sleep = sleep
        var loaded = HumSettings()
        var quarantined: URL?
        if let fileURL {
            do {
                if let settings = try JSONFileStore.load(HumSettings.self, from: fileURL) {
                    loaded = settings
                }
            } catch {
                quarantined = JSONFileStore.quarantine(fileURL)
            }
        }
        behavior = loaded.behavior
        appearance = loaded.appearance
        shortcuts = loaded.shortcuts
        playback = loaded.playback
        history = loaded.history
        window = loaded.window
        quarantinedFile = quarantined
    }

    /// An in-memory store with the given contents.
    public convenience init(settings: HumSettings) {
        self.init(fileURL: nil)
        self.settings = settings
    }

    /// The whole document. Setting it replaces every section.
    public var settings: HumSettings {
        get {
            var result = HumSettings()
            result.behavior = behavior
            result.appearance = appearance
            result.shortcuts = shortcuts
            result.playback = playback
            result.history = history
            result.window = window
            return result
        }
        set {
            behavior = newValue.behavior
            appearance = newValue.appearance
            shortcuts = newValue.shortcuts
            playback = newValue.playback
            history = newValue.history
            window = newValue.window
        }
    }

    /// Whether a save is waiting to run.
    public var hasPendingSave: Bool { saveTask != nil }

    /// Write now, cancelling any pending delayed save.
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard let fileURL else { return }
        try? JSONFileStore.save(settings, to: fileURL)
    }

    private func scheduleSave() {
        guard fileURL != nil else { return }
        saveTask?.cancel()
        let delay = saveDelay
        let sleep = sleep
        saveTask = Task { [weak self] in
            try? await sleep(delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}
