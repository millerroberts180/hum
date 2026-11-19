import HumCore
import SwiftUI

/// One insight: a stat in rounded numerals, what it counts, and one line on
/// the range and source behind it (DESIGN.md §5.7). Clicking, Space, or Return
/// expands it in place to show the sentence, the timeline and secondary facts.
struct InsightCard: View {
    var insight: Insight
    @Binding var isExpanded: Bool

    @Environment(\.playerMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isOpen = isExpanded
        EchoCard(canExpand: true, toggle: toggle) {
            VStack(alignment: .leading, spacing: metrics.sizeClass == .small ? Spacing.xxs : Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    if let value = insight.value {
                        Text(value)
                            .humText(.statValue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .layoutPriority(1)
                    }
                    // Two lines, so a song's name in it isn't cut short.
                    Text(Self.shownLabel(insight))
                        .humText(.statLabel, color: .secondaryLabel)
                        .lineLimit(2)
                }
                // Every number states its range and source (§6.5): two lines
                // at rest from M, so neither is cut off, and all of it once
                // open. A sentence, so secondary (§3.5.9).
                Text(insight.explanation)
                    .humText(.caption, color: .secondaryLabel)
                    .lineLimit(Self.explanationLineLimit(isOpen: isOpen, sizeClass: metrics.sizeClass))
                    .fixedSize(horizontal: false, vertical: isOpen)
                if isOpen {
                    expandedContent
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(insight.spokenSummary)
        .accessibilityValue(([insight.explanation] + (isOpen ? insight.details : [])).joined(separator: ". "))
        .accessibilityHint(isExpanded ? "Shows less." : "Shows more about this.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle() }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let sentence = insight.sentence {
                Text(sentence)
                    .humText(.rowSubtitle, color: .label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let timeline = insight.timeline {
                MiniTimeline(data: timeline)
            }
            if !insight.details.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(insight.details, id: \.self) { detail in
                        Text(detail)
                            .humText(.caption)
                    }
                }
            }
        }
        .padding(.top, Spacing.xs)
    }

    private func toggle() {
        withAnimation(Motion.spatial(Motion.smooth, reduceMotion: reduceMotion)) {
            isExpanded.toggle()
        }
    }

    /// At every size (DESIGN.md §5.7). Where two cards don't fit, Echo shows
    /// one.
    nonisolated static let padding = Spacing.l

    /// What the stat counts, as shown: a fragment after the value ("plays ·
    /// 1 hr 11 min"), or, with no value before it, a phrase that starts with
    /// a capital ("First heard Sunday").
    nonisolated static func shownLabel(_ insight: Insight) -> String {
        guard insight.value == nil, let first = insight.label.first else { return insight.label }
        return first.uppercased() + insight.label.dropFirst()
    }

    /// How many lines the range and source may take: at rest one at S (§5.7)
    /// and two from M, rather than cut off the range or the source (§7); all
    /// of them once open.
    nonisolated static func explanationLineLimit(isOpen: Bool, sizeClass: PlayerSizeClass) -> Int? {
        guard !isOpen else { return nil }
        return sizeClass == .small ? 1 : 2
    }
}

/// What Echo's cards share: their fill, and, where they expand, the card
/// button (`PlayerButtonStyle(.card)`), which presses, takes keyboard focus
/// and answers Space and Return as the other cards do (DESIGN.md §5.9).
struct EchoCard<Content: View>: View {
    var canExpand: Bool
    var toggle: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        if canExpand {
            Button(action: toggle) {
                EchoCardFace { content }
            }
            .buttonStyle(PlayerButtonStyle(.card))
        } else {
            EchoCardFace { content }
        }
    }
}

/// A card's content on its own fill (`echoCardFill`) with `Radius.card`, with
/// the focus ring on the card's shape while its button has focus.
private struct EchoCardFace<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        content
            .padding(InsightCard.padding)
            .echoCardFill(in: shape)
            .environment(\.humColorContext, .material)
            .cardFocusRing(shape)
            .contentShape(.rect)
    }
}

#if DEBUG
struct InsightCard_Previews: PreviewProvider {
    static var previews: some View {
        PreviewGallery(isSquare: false) {
            VStack(spacing: Spacing.s) {
                InsightCard(insight: .previewSong, isExpanded: .constant(false))
                InsightCard(insight: .previewSong, isExpanded: .constant(true))
            }
            .padding(Spacing.m)
        }
    }
}
#endif
