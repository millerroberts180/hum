import Foundation
import HumCore
import os

/// Runs AppleScript in process on one dedicated serial queue.
///
/// The actor's executor *is* that queue, so every `NSAppleScript` is created,
/// compiled, and executed there and nowhere else. Sending an Apple Event blocks
/// until the target replies (bounded by each script's `with timeout`), which is
/// fine on this queue and would not be on the main thread or the shared pool.
public actor AppleScriptRunner {
    public static let shared = AppleScriptRunner()

    private let queue = DispatchSerialQueue(label: "com.millerroberts.hum.apple-events", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    public init() {}

    /// Compile (once, if `cache` is set) and run `source`.
    ///
    /// Cache scripts that run repeatedly with the same text, such as the state
    /// query. Commands with arguments change text on every call and shouldn't be
    /// cached.
    public func run(_ source: String, cache: Bool = false) throws(PlaybackError) -> ScriptValue {
        let script: NSAppleScript
        if let existing = compiled[source] {
            script = existing
        } else {
            guard let created = NSAppleScript(source: source) else {
                throw .scriptFailed(code: 0, message: "The script couldn’t be created.")
            }
            var compileError: NSDictionary?
            guard created.compileAndReturnError(&compileError) else {
                throw Self.error(from: compileError)
            }
            if cache {
                compiled[source] = created
            }
            script = created
        }

        var executeError: NSDictionary?
        let result = script.executeAndReturnError(&executeError)
        if let executeError {
            throw Self.error(from: executeError)
        }
        return ScriptValue(result)
    }

    static func error(from info: NSDictionary?) -> PlaybackError {
        let code = (info?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        let message = info?[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error."
        let error = PlaybackError(appleEventCode: code, message: message)
        log(error, code: code, message: message)
        return error
    }

    /// The message can quote a track or playlist name, so it stays private.
    private static func log(_ error: PlaybackError, code: Int, message: String) {
        switch error {
        case .notRunning:
            HumLog.sources.debug("Apple Event: the app isn't running (\(code, privacy: .public))")
        case .permissionDenied, .permissionNotDetermined:
            HumLog.sources.info("Apple Event: no Automation permission (\(code, privacy: .public))")
        default:
            HumLog.sources.error("Apple Event failed (\(code, privacy: .public)): \(message, privacy: .private)")
        }
    }
}

extension PlaybackError {
    /// Maps an Apple Event / OSA error number to a `PlaybackError`.
    init(appleEventCode code: Int, message: String) {
        switch code {
        case -1743: self = .permissionDenied
        case -1744: self = .permissionNotDetermined
        case -1712: self = .timedOut
        case -600, -609, -903: self = .notRunning
        default: self = .scriptFailed(code: code, message: message)
        }
    }
}
