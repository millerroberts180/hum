import HumCore
import SwiftUI

/// Echo: at most two cards, one about the song playing and one about this
/// session, chosen by relevance, on the same backdrop as Status:
/// `artBackdrop` under `windowWash` (DESIGN.md §6.5). Echo never names the
/// music app (§10).
struct EchoSurface: View {
    @Environment(ListeningHistory.self) private var history: ListeningHistory?
    @Environment(HistoryWindowPresenter.self) private var historyWindow: HistoryWindowPresenter?
    @Environment(NowPlayingStore.self) private var store
    @Environment(\.playerMetrics) private var metrics
    @Environment(\.playerActions) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: Insight.Subject?

    /// Room for the page indicator, which sits just inside the top inset.
    static let indicatorClearance = PageIndicator.contentClearance

    var body: some View {
        SurfaceBackdrop(artwork: store.artwork) {
            if let history {
                content(history)
            } else {
                SurfacePlaceholder(surface: .echo, message: "Listening history isn’t available.")
            }
        }
        // "Added to Favorites" for a song saved from a card's menu (§5.8).
        .overlay { LibraryNoticeLayer() }
        .contextMenu { menu }
        .onAppear(perform: applyDebugExpansion)
    }

    private func content(_ history: ListeningHistory) -> some View {
        let inset = metrics.contentInset
        let song = songInsight(history)
        let session = sessionInsight(history)
        let spacing = metrics.sizeClass == .small ? Spacing.xs : Spacing.s
        return VStack(alignment: .leading, spacing: spacing) {
            if !history.isCollecting {
                PausedNote { history.setCollecting(true) }
            }
            // Both cards where they fit at their full padding (§5.7),
            // otherwise the one that matters most.
            ViewThatFits(in: .vertical) {
                if let song {
                    VStack(alignment: .leading, spacing: spacing) {
                        songCard(song)
                        sessionCard(session)
                    }
                }
                if let song, onlyCard(hasSong: true) == .song {
                    songCard(song)
                } else {
                    sessionCard(session)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            if metrics.sizeClass != .small, historyWindow != nil {
                seeAll
            }
        }
        .padding(.horizontal, inset)
        // Clear of the page indicator along the top edge, as on Status.
        .padding(.top, inset + Self.indicatorClearance)
        .padding(.bottom, inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.spatial(Motion.smooth, reduceMotion: reduceMotion), value: song?.kind)
        .animation(Motion.spatial(Motion.smooth, reduceMotion: reduceMotion), value: history.isCollecting)
    }

    private var seeAll: some View {
        HStack {
            Spacer()
            Button {
                historyWindow?.show()
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Text("See All")
                    Image(systemName: "chevron.forward")
                        .imageScale(.small)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Open Listening History")
            .accessibilityLabel("See all listening history")
        }
    }

    @ViewBuilder
    private var menu: some View {
        if let historyWindow {
            Button("Open Listening History…") { historyWindow.show() }
        }
        if let history {
            Button(history.isCollecting ? "Pause Listening History" : "Resume Listening History") {
                history.setCollecting(!history.isCollecting)
            }
        }
        Divider()
        Button("History Settings…") { actions.openSettingsPane(.echoPrivacy) }
        // The player section (§4.4).
        PlayerMenuItems()
    }

    private func songCard(_ insight: Insight) -> some View {
        InsightCard(insight: insight, isExpanded: expansion(.song))
            .id(insight.kind)
            .transition(.opacity)
    }

    private func sessionCard(_ insight: Insight?) -> some View {
        SessionCard(insight: insight, isExpanded: expansion(.session))
            .transition(.opacity)
    }

    /// The card shown when two don't fit: the expanded one, else the song's.
    private func onlyCard(hasSong: Bool) -> Insight.Subject {
        hasSong ? (expanded ?? .song) : .session
    }

    /// The song card, only once it's about the song that's playing.
    private func songInsight(_ history: ListeningHistory) -> Insight? {
        guard let track = store.track,
              history.echo.songKey == SongKey.make(artist: track.artist, title: track.title)
        else { return nil }
        return history.echo.songInsights.first
    }

    /// The most relevant thing to say about the session beyond its ribbon.
    private func sessionInsight(_ history: ListeningHistory) -> Insight? {
        history.echo.sessionInsights.first { $0.kind != .sessionSummary }
    }

    private func expansion(_ subject: Insight.Subject) -> Binding<Bool> {
        Binding(
            get: { expanded == subject },
            set: { expanded = $0 ? subject : nil }
        )
    }

    /// Screenshots of the expanded card: `HUM_DEBUG_EXPAND_INSIGHT=song|session`.
    private func applyDebugExpansion() {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["HUM_DEBUG_EXPAND_INSIGHT"] {
        case "song": expanded = .song
        case "session": expanded = .session
        default: break
        }
        #endif
    }
}

/// The session card: the ribbon, plus the one session insight most worth
/// saying. Expands like an `InsightCard`.
struct SessionCard: View {
    var insight: Insight?
    @Binding var isExpanded: Bool

    @Environment(\.playerMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isOpen = isExpanded
        EchoCard(canExpand: canExpand, toggle: toggle) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SessionRibbon(showsChapter: metrics.sizeClass != .small)
                if let insight, metrics.sizeClass != .small {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        // One stat value and its label (§5.7). The sentence would
                        // only repeat it here; the details say more.
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                            if let value = insight.value {
                                Text(value)
                                    .humText(.cardTitle)
                                    .monospacedDigit()
                            }
                            Text(insight.value == nil ? (insight.sentence ?? InsightCard.shownLabel(insight)) : insight.label)
                                .humText(.statLabel, color: .secondaryLabel)
                                .lineLimit(isOpen ? 3 : 1)
                        }
                        // Its range and source, as every number has (§6.5):
                        // two lines at rest rather than cut either off (§7).
                        Text(insight.explanation)
                            .humText(.caption, color: .secondaryLabel)
                            .lineLimit(isOpen ? 4 : 2)
                            .fixedSize(horizontal: false, vertical: isOpen)
                        if isOpen {
                            ForEach(insight.details, id: \.self) { detail in
                                Text(detail)
                                    .humText(.caption)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(canExpand ? (isExpanded ? "Shows less." : "Shows more about this session.") : "")
        .accessibilityAddTraits(canExpand ? .isButton : [])
        .accessibilityAction {
            toggle()
        }
    }

    private var canExpand: Bool { insight != nil }

    private func toggle() {
        guard canExpand else { return }
        withAnimation(Motion.spatial(Motion.smooth, reduceMotion: reduceMotion)) {
            isExpanded.toggle()
        }
    }
}

/// A quiet note that history collection is paused, with a way back. No warning
/// colors: pausing is a choice, not a problem.
struct PausedNote: View {
    var resume: () -> Void

    @Environment(\.playerMetrics) private var metrics

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "pause.circle")
                .foregroundStyle(HumColor.secondaryLabel)
                .accessibilityHidden(true)
            Text(metrics.sizeClass == .small ? "Paused" : "History is paused")
                .font(.caption.weight(.medium))
                .foregroundStyle(HumColor.secondaryLabel)
                .lineLimit(1)
            Spacer(minLength: Spacing.xs)
            Button("Resume", action: resume)
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .foregroundStyle(HumColor.label)
                .accessibilityHint("Starts saving what you listen to again.")
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .echoCardFill(in: Capsule())
        .environment(\.humColorContext, .material)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Listening history is paused")
    }
}

#if DEBUG
struct EchoSurface_Previews: PreviewProvider {
    static var previews: some View {
        PreviewGallery {
            EchoSurface()
                .environment(PreviewHistory.shared)
        }
    }
}
#endif
