import HumCore
@testable import HumUI
import Testing

@Suite("Hover controls by size")
struct HoverRoomTests {
    /// The size note beside each switch in Settings says where the control can
    /// actually appear.
    @Test func eachSettingsNoteMatchesWhereTheControlFits() {
        let expected: [String: [PlayerSizeClass]] = [
            "Every size": [.small, .medium, .large],
            "Medium and large players": [.medium, .large],
            "Large players": [.large],
        ]
        for control in HoverControls.ordered {
            let fits = [PlayerSizeClass.small, .medium, .large].filter { PlayerLook.room(at: $0).contains(control) }
            #expect(expected[control.sizeClasses] == fits, "\(control.title)")
        }
    }

    @Test func aLargePlayerHasRoomForEverything() {
        #expect(PlayerLook.room(at: .large) == .all)
    }
}
