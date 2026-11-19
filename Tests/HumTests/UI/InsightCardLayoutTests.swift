import Foundation
@testable import HumCore
import HumSources
@testable import HumUI
import SwiftUI
import Testing

@Suite("Echo cards")
struct InsightCardLayoutTests {
    /// At S the range and source keep to one line (§5.7).
    @Test func atSmallTheRangeAndSourceTakeOneLineAtRest() {
        #expect(InsightCard.explanationLineLimit(isOpen: false, sizeClass: .small) == 1)
    }

    /// From M they may wrap to a second line rather than cut off the range or
    /// the source (§7).
    @Test(arguments: [PlayerSizeClass.medium, .large])
    func fromMediumTheyMayTakeTwoLines(sizeClass: PlayerSizeClass) {
        #expect(InsightCard.explanationLineLimit(isOpen: false, sizeClass: sizeClass) == 2)
    }

    @Test(arguments: [PlayerSizeClass.small, .medium, .large])
    func theyAreWholeOnceOpened(sizeClass: PlayerSizeClass) {
        #expect(InsightCard.explanationLineLimit(isOpen: true, sizeClass: sizeClass) == nil)
    }
}

/// Every insight the demo's history gives, on Echo's card at the Small and
/// Medium presets (240, 280), shows its range and source whole at rest
/// (DESIGN.md §6.5, §7): they come first and fit the two lines the card gives
/// them, with room for the ellipsis where more follows.
@MainActor
@Suite("Range and source on cards")
struct RangeAndSourceFitTests {
    /// The width the explanation has inside the card's padding.
    static func textWidth(side: CGFloat) -> CGFloat {
        side - PlayerMetrics(side: side).contentInset * 2 - InsightCard.padding * 2
    }

    /// Every song and session insight for the demo's songs, with and without
    /// playlists named.
    static func demoInsights() async throws -> [Insight] {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        var insights: [Insight] = []
        for namesContexts in [true, false] {
            let store = HistoryStore.openOrFallback(url: nil).store
            let catalog = DemoPlaylist.tracks.map(\.track)
            try await store.insert(contentsOf: DemoHistory.generate(
                catalog: catalog, endingAt: now, calendar: calendar, namesContexts: namesContexts
            ))
            for track in catalog {
                let echo = try await store.echo(track: track, inProgress: nil, now: now, calendar: calendar)
                insights += echo.songInsights + echo.sessionInsights
            }
        }
        // A song heard only briefly so far: the longest of them.
        insights.append(InsightEngine.coldStart(earlierListens: 2, source: "Tracked by Hum since Sep 30, 2026."))
        return insights
    }

    /// The range and source: the explanation up to the end of the sentence
    /// that says where the numbers came from.
    static func rangeAndSource(_ explanation: String) -> String? {
        let sources = ["tracked by Hum", "Tracked by Hum", "imported", "Imported", "Heard by Hum", "Hum began tracking"]
        let ends = sources.compactMap { explanation.range(of: $0)?.upperBound }
        guard let end = ends.min(), let stop = explanation[end...].firstIndex(of: ".") else { return nil }
        return String(explanation[...stop])
    }

    func height(_ text: String, width: CGFloat?) throws -> CGFloat {
        let view = Text(text)
            .humText(.caption, color: .secondaryLabel)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: width == nil, vertical: true)
            .environment(\.playerMetrics, PlayerMetrics(side: 280))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return CGFloat(try #require(renderer.cgImage).height)
    }

    @Test func everyExplanationSaysWhereItsNumbersCameFrom() async throws {
        let insights = try await Self.demoInsights()
        #expect(insights.count >= 20)
        for insight in insights {
            #expect(Self.rangeAndSource(insight.explanation) != nil, "\(insight.kind): \(insight.explanation)")
        }
    }

    @Test(arguments: [240.0, 280])
    func theRangeAndSourceFitTwoLines(side: CGFloat) async throws {
        let width = Self.textWidth(side: side)
        let line = try height("Ag", width: nil)
        var seen = Set<String>()
        for insight in try await Self.demoInsights() {
            guard let part = Self.rangeAndSource(insight.explanation), seen.insert(part).inserted else { continue }
            let shown = part.count < insight.explanation.count ? part + " …" : part
            let lines = (try height(shown, width: width) / line).rounded()
            #expect(lines <= 2, "\(side): \(insight.kind) takes \(lines) lines: \(part)")
        }
    }
}
