import Darwin
import Foundation
import HumCore
import WidgetKit

/// Retires a widget extension left running from an older copy of Hum
/// (DESIGN.md §7.3).
///
/// When Hum.app is replaced in place, by an update or a new build, the widget
/// extension macOS started from the old copy can keep running. macOS goes on
/// using that process and turns down everything it draws, because its bundle
/// version no longer matches the installed one, so the widgets freeze on the
/// old song and the old look and Hum's reloads go nowhere.
///
/// As Hum starts it looks for that process: one of this user's, running this
/// copy's extension executable, that started before the executable was last
/// written. It asks each one to quit, waits for it to go, then asks WidgetKit
/// to reload, and macOS starts the extension again from the new copy. An
/// extension started since, or one run from another copy of Hum, is left alone.
@MainActor
public struct StaleWidgetExtension {
    /// A running process, as far as this needs to know it.
    public struct Process: Equatable, Sendable {
        public var pid: pid_t
        public var uid: uid_t
        /// The path of the executable it runs.
        public var executable: String
        public var started: Date

        public init(pid: pid_t, uid: uid_t, executable: String, started: Date) {
            self.pid = pid
            self.uid = uid
            self.executable = executable
            self.started = started
        }
    }

    /// What it reads from and does to the system.
    public struct System {
        /// The processes running this executable.
        var processes: (_ executable: String) -> [Process]
        /// One process, read again, or `nil` once it's gone.
        var process: (_ pid: pid_t) -> Process?
        /// When the file was last written: the later of its modification and
        /// status-change times, since an update can keep the build's
        /// modification times.
        var written: (_ path: String) -> Date?
        /// Ask a process to quit; whether the signal was sent.
        var terminate: (_ pid: pid_t) -> Bool
        var userID: uid_t
    }

    /// How long it waits for the old processes to go before reloading anyway.
    static let exitTimeout: Duration = .seconds(2)
    static let exitPoll: Duration = .milliseconds(100)

    private let executable: String
    private let system: System
    private let sleep: @MainActor (Duration) async -> Void
    private let reload: @MainActor () -> Void

    /// The extension inside this copy of Hum.
    public init() {
        self.init(
            executable: Bundle.main.bundleURL
                .appendingPathComponent("Contents/PlugIns/HumWidgets.appex/Contents/MacOS/HumWidgets")
        )
    }

    init(
        executable: URL,
        system: System = .live,
        sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        reload: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.executable = executable.resolvingSymlinksInPath().path
        self.system = system
        self.sleep = sleep
        self.reload = reload
    }

    /// The processes running an older build of the extension: this user's,
    /// running `executable`, started before it was written.
    static func stale(_ processes: [Process], executable: String, writtenAt: Date, userID: uid_t) -> [Process] {
        processes.filter { $0.uid == userID && $0.executable == executable && $0.started < writtenAt }
    }

    /// Ask any stale extension to quit, then reload the widgets.
    ///
    /// - Returns: The processes it asked to quit.
    @discardableResult
    public func retire() async -> [pid_t] {
        guard let writtenAt = system.written(executable) else { return [] }
        let stale = Self.stale(system.processes(executable), executable: executable, writtenAt: writtenAt, userID: system.userID)
        // Read each one again just before the signal, so a process that quit
        // and left its number to another is never touched.
        let asked = stale.filter { system.process($0.pid) == $0 && system.terminate($0.pid) }
        guard !asked.isEmpty else { return [] }
        HumLog.app.notice("Asked \(asked.count, privacy: .public) widget extension(s) from an older build to quit")

        var waited: Duration = .zero
        while asked.contains(where: { system.process($0.pid) == $0 }), waited < Self.exitTimeout {
            await sleep(Self.exitPoll)
            waited += Self.exitPoll
        }
        reload()
        return asked.map(\.pid)
    }
}

extension StaleWidgetExtension.System {
    /// The real system: libproc for processes, `stat` for files, `kill`.
    static var live: Self {
        Self(
            processes: { executable in
                let count = proc_listallpids(nil, 0)
                guard count > 0 else { return [] }
                // Room for processes that start while it reads.
                var pids = [pid_t](repeating: 0, count: Int(count) + 32)
                let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
                return pids.prefix(Int(max(0, found))).compactMap { pid in
                    guard pid > 0, let process = liveProcess(pid), process.executable == executable else { return nil }
                    return process
                }
            },
            process: liveProcess,
            written: { path in
                var info = stat()
                guard stat(path, &info) == 0 else { return nil }
                return max(date(info.st_mtimespec), date(info.st_ctimespec))
            },
            terminate: { kill($0, SIGTERM) == 0 },
            userID: getuid()
        )
    }

    private static func liveProcess(_ pid: pid_t) -> StaleWidgetExtension.Process? {
        var path = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &path, UInt32(path.count))
        guard length > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return StaleWidgetExtension.Process(
            pid: pid,
            uid: info.pbi_uid,
            executable: String(decoding: path.prefix(Int(length)), as: UTF8.self),
            started: Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
        )
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }
}
