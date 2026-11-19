import Foundation
import HumCore
import Testing

@Suite("Widget links to Hum")
struct HumURLActionTests {
    @Test(arguments: HumURLAction.allCases)
    func everyActionRoundTripsThroughItsURL(_ action: HumURLAction) {
        #expect(action.url.absoluteString == "hum://" + action.rawValue)
        #expect(HumURLAction(url: action.url) == action)
    }

    @Test func theActionsAreTheTransportAndShow() {
        #expect(HumURLAction.allCases.map(\.rawValue) == ["play-pause", "next", "previous", "shuffle", "repeat", "show"])
    }

    @Test func theSchemeIsCaseInsensitiveAsURLSchemesAre() throws {
        #expect(HumURLAction(url: try #require(URL(string: "HUM://next"))) == .next)
    }

    @Test(arguments: [
        "https://play-pause",
        "humm://next",
        "hum://stop",
        "hum://Next",
        "hum://playPause",
        "hum://",
        "hum:next",
        "hum://next/",
        "hum://next/again",
        "hum://next?times=2",
        "hum://next#now",
        "hum://me@next",
        "hum://me:secret@next",
        "hum://next:80",
        "file:///next",
    ])
    func anythingElseIsRejected(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(HumURLAction(url: url) == nil)
    }
}
