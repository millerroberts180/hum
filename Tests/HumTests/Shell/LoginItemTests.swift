@testable import HumUI
import ServiceManagement
import Testing

@MainActor
@Suite("Open at Login")
struct LoginItemTests {
    struct Refused: Error {}

    /// Stands in for the system's list of login items, so no test registers
    /// a real one.
    final class FakeLoginItems: LoginItemService {
        var status: SMAppService.Status
        /// What the system reports once Hum has registered.
        var statusAfterRegister: SMAppService.Status = .enabled
        var refuses = false
        var calls: [String] = []

        init(_ status: SMAppService.Status = .notRegistered) {
            self.status = status
        }

        func register() throws {
            calls.append("register")
            if refuses { throw Refused() }
            status = statusAfterRegister
        }

        func unregister() throws {
            calls.append("unregister")
            if refuses { throw Refused() }
            status = .notRegistered
        }
    }

    @Test(arguments: [
        (SMAppService.Status.notRegistered, false, false),
        (.enabled, true, false),
        (.requiresApproval, true, true),
        (.notFound, false, false),
    ])
    func theSwitchFollowsTheSystemsStatus(_ status: SMAppService.Status, isOn: Bool, needsApproval: Bool) {
        let item = LoginItem(service: FakeLoginItems(status))
        #expect(item.status == status)
        #expect(item.isOn == isOn)
        #expect(item.needsApproval == needsApproval)
    }

    @Test func turningItOnRegistersAndReadsTheStatusBack() {
        let service = FakeLoginItems()
        service.statusAfterRegister = .requiresApproval
        let item = LoginItem(service: service)
        item.set(true)
        #expect(service.calls == ["register"])
        #expect(item.isOn)
        #expect(item.needsApproval)
        #expect(item.failure == nil)
    }

    @Test func turningItOffUnregisters() {
        let service = FakeLoginItems(.enabled)
        let item = LoginItem(service: service)
        item.set(false)
        #expect(service.calls == ["unregister"])
        #expect(!item.isOn)
        #expect(item.failure == nil)
    }

    @Test func aRefusedRegistrationSaysSoAndStaysOff() {
        let service = FakeLoginItems()
        service.refuses = true
        let item = LoginItem(service: service)
        item.set(true)
        #expect(item.failure == "Hum couldn’t add itself to your login items.")
        #expect(!item.isOn)
    }

    @Test func aRefusedRemovalSaysSoAndStaysOn() {
        let service = FakeLoginItems(.enabled)
        service.refuses = true
        let item = LoginItem(service: service)
        item.set(false)
        #expect(item.failure == "Hum couldn’t remove itself from your login items.")
        #expect(item.isOn)
    }

    @Test func theNextTryClearsTheFailure() {
        let service = FakeLoginItems()
        service.refuses = true
        let item = LoginItem(service: service)
        item.set(true)
        service.refuses = false
        item.set(true)
        #expect(item.failure == nil)
        #expect(item.isOn)
    }

    @Test func refreshPicksUpAChangeMadeInSystemSettings() {
        let service = FakeLoginItems(.enabled)
        let item = LoginItem(service: service)
        service.status = .notRegistered
        #expect(item.isOn)
        item.refresh()
        #expect(!item.isOn)
        #expect(service.calls.isEmpty)
    }
}
