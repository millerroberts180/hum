#if DEBUG
import HumCore
import SwiftUI

/// Made-up listening for Echo's previews: about six months of the preview song,
/// with a session that's still warm (DESIGN.md §12.4).
@MainActor
enum PreviewHistory {
    static let shared: ListeningHistory = {
        let nowPlaying = NowPlayingStore(sources: [PreviewSource(isPlaying: true)], preferredSourceID: .demo)
        nowPlaying.start()
        let history = ListeningHistory(
            store: HistoryStore.openOrFallback(url: nil).store,
            nowPlaying: nowPlaying,
            settings: SettingsStore(fileURL: nil),
            artworkCache: ArtworkCache(directory: nil)
        )
        let listens = DemoHistory.generate(catalog: [PreviewSource.track], endingAt: Date(), calendar: .autoupdatingCurrent)
        let cover = PreviewSource.coverData
        history.replaceAll(with: listens) { _ in cover }
        history.start()
        return history
    }()
}

extension Insight {
    /// A song insight with every part filled in.
    static let previewSong = Insight(
        kind: .togetherTime,
        title: "Time together",
        value: "173",
        label: "plays of Paper Lanterns · 10 hr 23 min",
        sentence: "Usually played late at night",
        explanation: "Counted from May 9 to today, tracked by Hum.",
        details: ["First heard May 9", "Last played yesterday"],
        timeline: .preview,
        relevance: 1
    )

    /// A session insight, as the session card shows it.
    static let previewSession = Insight(
        kind: .sessionSources,
        title: "Where it came from",
        value: "3 of 4",
        label: "listens from Late Shift",
        sentence: "Mostly from Late Shift",
        explanation: "3 of 4 listens from Late Shift since 2:00 PM, tracked by Hum.",
        details: ["Late Shift: 3 listens", "1 other listen didn’t say where it came from"],
        relevance: 0.8
    )
}

extension MiniTimelineData {
    /// Plays spread over six months, bunched toward now.
    static let preview = MiniTimelineData(
        start: Date().addingTimeInterval(-180 * 86_400),
        end: Date(),
        marks: [0.04, 0.12, 0.3, 0.31, 0.55, 0.7, 0.72, 0.9, 0.97, 0.99],
        startLabel: "May 9",
        endLabel: "Today"
    )
}
#endif
