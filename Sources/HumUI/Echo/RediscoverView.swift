import HumCore
import SwiftUI

/// Rediscover: songs played often that have gone quiet for a while. Each row
/// plays its song where its source can, and offers nothing where it can't.
struct RediscoverView: View {
    @Environment(ListeningHistory.self) private var history
    @Environment(LibraryStore.self) private var library: LibraryStore?
    @State private var entries: [TopEntry] = []
    @State private var sources = HistoryProvenance()
    @State private var isLoaded = false

    static let quietDays = 60
    static let minimumPlays = 3

    var body: some View {
        HistoryPage(title: "Rediscover", caption: caption) {
            if isLoaded, entries.isEmpty {
                HistoryEmptyState(
                    symbol: "arrow.counterclockwise",
                    title: "Nothing to Rediscover Yet",
                    message: "Songs you’ve played \(Self.minimumPlays) or more times and then left alone for \(Self.quietDays) days will show up here."
                )
            } else {
                let format = HistoryFormat(calendar: history.calendar)
                let now = Date()
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        HistoryItemRow(artworkKey: entry.artworkKey, title: entry.title, subtitle: entry.subtitle, artworkSide: 40) {
                            HStack(spacing: Spacing.m) {
                                VStack(alignment: .trailing, spacing: 1) {
                                    HistoryNumber(HistoryFormat.count(entry.plays, "play"), color: .label)
                                    if let last = entry.lastPlayed {
                                        Text("Last played " + format.day(last, now: now) + " · " + Self.ago(last, now: now, calendar: history.calendar))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(HumColor.tertiaryLabel)
                                    }
                                }
                                if let library {
                                    RediscoverPlayButton(entry: entry, library: library)
                                }
                            }
                        }
                        .contentShape(.rect)
                        .contextMenu { HistoryEntryMenu(entry: entry, library: library) }
                        if entry.id != entries.last?.id {
                            Divider().padding(.leading, 40 + Spacing.m)
                        }
                    }
                }
            }
        }
        .task(id: history.revision) { await load() }
    }

    private var caption: String {
        guard isLoaded else { return " " }
        return "Played \(Self.minimumPlays)+ times, quiet for \(Self.quietDays)+ days · " + HistoryFormat.source(sources)
    }

    /// "3 months ago", "9 weeks ago".
    static func ago(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        if days >= 60 {
            return HistoryFormat.count(days / 30, "month") + " ago"
        }
        return HistoryFormat.count(max(1, days / 7), "week") + " ago"
    }

    private func load() async {
        let calendar = history.calendar
        guard let quietSince = calendar.date(byAdding: .day, value: -Self.quietDays, to: Date()) else { return }
        do {
            let entries = try await history.store.rediscover(quietSince: quietSince, minimumPlays: Self.minimumPlays)
            let sources = try await history.store.provenance(to: quietSince)
            guard !Task.isCancelled else { return }
            self.entries = entries
            self.sources = sources
            isLoaded = true
        } catch {
            HumLog.history.error("Rediscover page couldn't load: \(String(describing: error), privacy: .public)")
            isLoaded = true
        }
    }
}

/// Plays a Rediscover song from the source it was heard on (`RediscoverPlay`).
/// Nothing shows when that source can't play it now.
private struct RediscoverPlayButton: View {
    var entry: TopEntry
    var library: LibraryStore

    @Environment(NowPlayingStore.self) private var nowPlaying

    var body: some View {
        if let track = RediscoverPlay.track(
            for: entry,
            activeSource: library.sourceID,
            canPlayItems: library.capabilities.canPlayItems
        ), library.playBlocker(for: .track(track, in: nil)) == nil {
            button(track)
        }
    }

    private func button(_ track: LibraryTrack) -> some View {
        let isCurrent = nowPlaying.isPlaying && nowPlaying.track?.id == entry.sampleTrackID
        return Button {
            library.play(.track(track, in: nil))
        } label: {
            Label(isCurrent ? "Playing" : "Play", systemImage: isCurrent ? "speaker.wave.2.fill" : "play.fill")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(isCurrent ? HumColor.accent : HumColor.secondaryLabel)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
        .help("Play this song")
        .accessibilityHint("Play this song")
    }
}
