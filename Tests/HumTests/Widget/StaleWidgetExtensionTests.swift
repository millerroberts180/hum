import Darwin
import Foundation
@testable import HumUI
import Testing

@MainActor
@Suite("Retiring a widget extension from an older build")
struct StaleWidgetExtensionTests {
    typealias Process = StaleWidgetExtension.Process

    static let executable = "/Applications/Hum.app/Contents/PlugIns/HumWidgets.appex/Contents/MacOS/HumWidgets"
    static let user: uid_t = 501
    let written = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func process(_ pid: pid_t, startedBefore seconds: TimeInterval, uid: uid_t = user, executable: String = executable) -> Process {
        Process(pid: pid, uid: uid, executable: executable, started: written.addingTimeInterval(-seconds))
    }

    /// A stand-in system: a list of processes that `terminate` takes away
    /// (or doesn't, when `quits` is false), and what was asked of it.
    final class FakeSystem {
        var running: [Process]
        var written: Date?
        var quits = true
        /// Once the first process is read again, another takes its number.
        var reusesFirstPID = false
        private(set) var terminated: [pid_t] = []
        private(set) var reloads = 0
        private(set) var sleeps: [Duration] = []

        init(running: [Process], written: Date?) {
            self.running = running
            self.written = written
        }

        @MainActor var system: StaleWidgetExtension.System {
            StaleWidgetExtension.System(
                processes: { [unowned self] executable in running.filter { $0.executable == executable } },
                process: { [unowned self] pid in
                    guard let index = running.firstIndex(where: { $0.pid == pid }) else { return nil }
                    if reusesFirstPID, index == 0 {
                        running[0].started = running[0].started.addingTimeInterval(3600)
                        running[0].executable = "/usr/bin/true"
                    }
                    return running[index]
                },
                written: { [unowned self] _ in written },
                terminate: { [unowned self] pid in
                    terminated.append(pid)
                    if quits { running.removeAll { $0.pid == pid } }
                    return true
                },
                userID: StaleWidgetExtensionTests.user
            )
        }

        @MainActor func recovery() -> StaleWidgetExtension {
            StaleWidgetExtension(
                executable: URL(fileURLWithPath: StaleWidgetExtensionTests.executable),
                system: system,
                sleep: { [unowned self] in sleeps.append($0) },
                reload: { [unowned self] in reloads += 1 }
            )
        }
    }

    @Test func onlyThisUsersCopyOfThisExecutableStartedBeforeItWasWrittenIsStale() {
        let processes = [
            process(10, startedBefore: 60),
            process(11, startedBefore: -60),
            process(12, startedBefore: 60, uid: 502),
            process(13, startedBefore: 60, executable: "/Volumes/Backup/Hum.app/Contents/PlugIns/HumWidgets.appex/Contents/MacOS/HumWidgets"),
            process(14, startedBefore: 0),
        ]
        let stale = StaleWidgetExtension.stale(processes, executable: Self.executable, writtenAt: written, userID: Self.user)
        #expect(stale.map(\.pid) == [10])
    }

    @Test func aStaleExtensionIsAskedToQuitThenTheWidgetsReload() async {
        let fake = FakeSystem(running: [process(10, startedBefore: 60), process(11, startedBefore: -60)], written: written)
        let asked = await fake.recovery().retire()
        #expect(asked == [10])
        #expect(fake.terminated == [10])
        #expect(fake.running.map(\.pid) == [11])
        #expect(fake.reloads == 1)
        #expect(fake.sleeps.isEmpty)
    }

    @Test func aCurrentExtensionIsLeftAloneAndNothingReloads() async {
        let fake = FakeSystem(running: [process(11, startedBefore: -60)], written: written)
        #expect(await fake.recovery().retire().isEmpty)
        #expect(fake.terminated.isEmpty)
        #expect(fake.reloads == 0)
    }

    @Test func withoutAnExtensionInTheBundleNothingHappens() async {
        let fake = FakeSystem(running: [process(10, startedBefore: 60)], written: nil)
        #expect(await fake.recovery().retire().isEmpty)
        #expect(fake.terminated.isEmpty)
        #expect(fake.reloads == 0)
    }

    @Test func aNumberTakenByAnotherProcessIsNeverSignalled() async {
        let fake = FakeSystem(running: [process(10, startedBefore: 60)], written: written)
        fake.reusesFirstPID = true
        #expect(await fake.recovery().retire().isEmpty)
        #expect(fake.terminated.isEmpty)
        #expect(fake.reloads == 0)
    }

    @Test func itWaitsForTheOldProcessToGoThenReloadsAnyway() async {
        let fake = FakeSystem(running: [process(10, startedBefore: 60)], written: written)
        fake.quits = false
        #expect(await fake.recovery().retire() == [10])
        #expect(fake.sleeps.count == 20)
        #expect(fake.sleeps.allSatisfy { $0 == .milliseconds(100) })
        #expect(fake.reloads == 1)
    }

    /// The live system finds this test process by its own executable and reads
    /// a start time from before now.
    @Test func theLiveSystemReadsThisProcess() throws {
        let system = StaleWidgetExtension.System.live
        let me = try #require(system.process(getpid()))
        #expect(me.uid == getuid())
        #expect(me.started <= Date())
        #expect(system.processes(me.executable).contains(me))
        let written = try #require(system.written(me.executable))
        #expect(written <= Date())
        #expect(system.written("/nonexistent/HumWidgets") == nil)
    }
}
