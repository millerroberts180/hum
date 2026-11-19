import HumCore
import Testing

/// The demo can say it plays from Spotify (`--demo-attribution Spotify`), and
/// then does what Spotify can and can't.
@Suite("Demo attribution")
struct DemoAttributionTests {
    @Test func onlySpotifyNamesSpotifyInAnyCase() {
        #expect(DemoAttribution.namesSpotify("Spotify"))
        #expect(DemoAttribution.namesSpotify("spotify"))
        #expect(DemoAttribution.namesSpotify("SPOTIFY"))
        #expect(DemoAttribution.namesSpotify(" Spotify "))
        #expect(!DemoAttribution.namesSpotify("Tidal"))
        #expect(!DemoAttribution.namesSpotify("Spotify Premium"))
        #expect(!DemoAttribution.namesSpotify(""))
        #expect(!DemoAttribution.namesSpotify(nil))
    }
}
