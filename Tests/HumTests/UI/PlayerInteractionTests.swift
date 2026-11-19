import Foundation
@testable import HumUI
import Testing

@MainActor
@Suite("Player interaction")
struct PlayerInteractionTests {
    @Test func theVolumeHUDShowsTheClampedLevel() {
        let interaction = PlayerInteraction()
        interaction.showVolumeHUD(level: 1.4)
        #expect(interaction.volumeHUDLevel == 1)
        interaction.showVolumeHUD(level: -0.2)
        #expect(interaction.volumeHUDLevel == 0)
        interaction.hideVolumeHUD()
        #expect(interaction.volumeHUDLevel == nil)
    }

    /// The hold ends only when the test says so, so a busy machine can't make
    /// it run out early or late.
    @Test func theVolumeHUDConcealsOnceTheVolumeHoldsStill() async {
        let sleeper = ManualSleeper()
        let interaction = PlayerInteraction { try await sleeper.sleep($0) }
        interaction.showVolumeHUD(level: 0.4)
        await waitUntil { sleeper.waiting == 1 }
        #expect(sleeper.requested == [Motion.hudHold])

        // Another change restarts the hold: the first is dropped, so its end
        // can't conceal the HUD early, and a whole new hold begins.
        interaction.showVolumeHUD(level: 0.45)
        await waitUntil { sleeper.requested.count == 2 && sleeper.waiting == 1 }
        #expect(sleeper.requested == [Motion.hudHold, Motion.hudHold])
        #expect(sleeper.waiting == 1)
        #expect(interaction.volumeHUDLevel == 0.45)

        sleeper.elapse()
        await waitUntil { interaction.volumeHUDLevel == nil }
        #expect(interaction.volumeHUDLevel == nil)
    }

    /// Leaving conceals at once: nothing is waited out (DESIGN.md §4.1).
    @Test func leavingConcealsAtOnce() async {
        let sleeper = ManualSleeper()
        let interaction = PlayerInteraction { try await sleeper.sleep($0) }
        var changes = 0
        interaction.onEngagementChange = { changes += 1 }
        interaction.pointerEntered()
        #expect(interaction.isPointerInside)
        #expect(interaction.isEngaged)
        #expect(changes == 1)

        interaction.pointerExited()
        #expect(!interaction.isPointerInside)
        #expect(!interaction.isEngaged)
        #expect(interaction.isRevealed == interaction.isVoiceOverRunning)
        #expect(changes == 2)
        await drainMainActor()
        #expect(sleeper.requested.isEmpty)

        // Coming straight back reveals again, and a second exit report for the
        // same leave changes nothing.
        interaction.pointerEntered()
        #expect(interaction.isEngaged)
        interaction.pointerExited()
        interaction.pointerExited()
        #expect(!interaction.isEngaged)
        #expect(changes == 4)
    }

    /// Scrubbing holds the controls after the pointer leaves, until it ends.
    @Test func scrubbingHoldsTheControlsPastALeave() {
        let interaction = PlayerInteraction()
        interaction.pointerEntered()
        interaction.isScrubbing = true
        interaction.pointerExited()
        #expect(interaction.isRevealed)
        #expect(interaction.isEngaged)
        interaction.isScrubbing = false
        #expect(!interaction.isEngaged)
        #expect(interaction.isRevealed == interaction.isVoiceOverRunning)
    }

    /// An open popover is its own window, so pointing at it leaves the player;
    /// the controls stay up and the player stays put until it closes.
    @Test func anOpenPopoverHoldsTheControls() {
        let interaction = PlayerInteraction()
        var changes = 0
        interaction.onEngagementChange = { changes += 1 }
        let token = UUID()
        interaction.setPopoverOpen(true, token: token)
        #expect(interaction.isRevealed)
        #expect(interaction.isEngaged)
        #expect(changes == 1)
        // Another popover closing doesn't release this one's hold.
        interaction.setPopoverOpen(false, token: UUID())
        #expect(interaction.isEngaged)
        #expect(changes == 1)
        interaction.setPopoverOpen(false, token: token)
        #expect(!interaction.isEngaged)
        #expect(interaction.isRevealed == interaction.isVoiceOverRunning)
        #expect(changes == 2)
    }
}
