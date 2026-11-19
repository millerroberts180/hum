import Foundation
import HumCore
import Testing

@Suite("Trailing time setting")
struct TrailingTimeSettingTests {
    @Test func itStartsAsTimeRemaining() {
        #expect(BehaviorSettings().trailingTime == .remaining)
    }

    @Test func clickingSwitchesBetweenRemainingAndTotal() {
        #expect(BehaviorSettings.TrailingTime.remaining.toggled == .total)
        #expect(BehaviorSettings.TrailingTime.total.toggled == .remaining)
    }

    @Test func itIsRemembered() throws {
        var behavior = BehaviorSettings()
        behavior.trailingTime = .total
        let data = try JSONEncoder().encode(behavior)
        #expect(try JSONDecoder().decode(BehaviorSettings.self, from: data).trailingTime == .total)
    }

    /// Settings written before the option existed, or by a newer build with a
    /// value this one doesn't know, fall back to the default.
    @Test func missingOrUnknownValuesFallBackToRemaining() throws {
        let missing = try JSONDecoder().decode(BehaviorSettings.self, from: Data("{}".utf8))
        #expect(missing.trailingTime == .remaining)
        let unknown = try JSONDecoder().decode(BehaviorSettings.self, from: Data(#"{"trailingTime":"sideways"}"#.utf8))
        #expect(unknown.trailingTime == .remaining)
    }
}
