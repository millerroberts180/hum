import Foundation
@testable import Hum
import HumCore
import HumSources
import Testing

@Suite("Widget links")
struct URLActionsTests {
    private static let everything: SourceCapabilities = [.transport, .shuffle, .repeatAll, .repeatOne]

    private func command(
        _ action: HumURLAction,
        _ capabilities: SourceCapabilities = everything,
        shuffle: Bool = false,
        repeatMode: RepeatMode = .off
    ) -> PlaybackCommand? {
        URLActions.command(for: action, capabilities: capabilities, shuffle: shuffle, repeatMode: repeatMode)
    }

    @Test func theTransportGoesStraightToTheSource() {
        #expect(command(.playPause) == .togglePlayPause)
        #expect(command(.next) == .next)
        #expect(command(.previous) == .previous)
    }

    @Test func shuffleTurnsTheOtherWay() {
        #expect(command(.shuffle, shuffle: false) == .setShuffle(true))
        #expect(command(.shuffle, shuffle: true) == .setShuffle(false))
    }

    @Test func repeatStepsOffAllOneAndRoundAgain() {
        #expect(command(.repeat, repeatMode: .off) == .setRepeat(.all))
        #expect(command(.repeat, repeatMode: .all) == .setRepeat(.one))
        #expect(command(.repeat, repeatMode: .one) == .setRepeat(.off))
    }

    @Test func repeatSkipsAModeTheSourceDoesNotHave() {
        let allOnly: SourceCapabilities = [.transport, .repeatAll]
        #expect(command(.repeat, allOnly, repeatMode: .off) == .setRepeat(.all))
        #expect(command(.repeat, allOnly, repeatMode: .all) == .setRepeat(.off))
        let oneOnly: SourceCapabilities = [.transport, .repeatOne]
        #expect(command(.repeat, oneOnly, repeatMode: .off) == .setRepeat(.one))
        #expect(command(.repeat, oneOnly, repeatMode: .one) == .setRepeat(.off))
    }

    /// A widget's repeat steps through One for Music, which repeats the song
    /// itself, and for Spotify, where Hum does (§13.34).
    @Test(arguments: [MusicApp.capabilities, SpotifyApp.capabilities])
    func repeatStepsThroughOneForMusicAndSpotify(_ capabilities: SourceCapabilities) {
        #expect(command(.repeat, capabilities, repeatMode: .off) == .setRepeat(.all))
        #expect(command(.repeat, capabilities, repeatMode: .all) == .setRepeat(.one))
        #expect(command(.repeat, capabilities, repeatMode: .one) == .setRepeat(.off))
        #expect(command(.shuffle, capabilities, shuffle: true) == .setShuffle(false))
    }

    @Test func whatTheSourceCantDoDoesNothing() {
        #expect(command(.playPause, []) == nil)
        #expect(command(.next, [.playPause]) == nil)
        #expect(command(.previous, [.playPause, .skipNext]) == nil)
        #expect(command(.shuffle, .transport) == nil)
        #expect(command(.repeat, .transport) == nil)
    }

    /// Show opens the player (or its popover in Menu Bar); it sends nothing
    /// to the source.
    @Test func showIsNotACommand() {
        #expect(command(.show) == nil)
    }

    @Test(arguments: HumURLAction.allCases)
    func eachLinkTheWidgetsUseNamesItsAction(_ action: HumURLAction) throws {
        let url = try #require(URL(string: "hum://\(action.rawValue)"))
        #expect(HumURLAction(url: url) == action)
    }
}
