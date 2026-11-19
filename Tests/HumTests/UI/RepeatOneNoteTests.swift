import HumCore
@testable import HumSources
@testable import HumUI
import SwiftUI
import Testing

/// The repeat button's one-time note: Hum repeats the song itself for an app
/// whose own repeat button can't show One (DESIGN.md §5.2, §13.35).
@Suite("Repeat one's note")
struct RepeatOneNoteTests {
    @Test func itComesTheFirstTimeOneIsPickedForSpotify() {
        #expect(RepeatOneNote.shows(choosing: .one, capabilities: SpotifyApp.capabilities, alreadyShown: false))
    }

    @Test func itComesOnlyOnce() {
        #expect(!RepeatOneNote.shows(choosing: .one, capabilities: SpotifyApp.capabilities, alreadyShown: true))
    }

    @Test(arguments: [RepeatMode.off, .all])
    func otherModesDontBringIt(_ mode: RepeatMode) {
        #expect(!RepeatOneNote.shows(choosing: mode, capabilities: SpotifyApp.capabilities, alreadyShown: false))
    }

    /// Music shows its own repeat one, so there's nothing to explain.
    @Test func musicNeverGetsIt() {
        #expect(!RepeatOneNote.shows(choosing: .one, capabilities: MusicApp.capabilities, alreadyShown: false))
    }

    /// The player never names the app (§10).
    @Test func itDoesntNameTheApp() {
        for text in [RepeatOneNote.title, RepeatOneNote.message] {
            #expect(!text.localizedCaseInsensitiveContains("spotify"))
            #expect(!text.contains("Music "))
        }
    }

    /// The sentence wraps rather than truncating: three lines under the title.
    @MainActor @Test func theWholeSentenceShows() throws {
        let height = try #require(ImageRenderer(content: RepeatOneNoteView()).cgImage).height
        // Padding, the headline, and three lines of callout.
        #expect(height >= 85)
    }
}
