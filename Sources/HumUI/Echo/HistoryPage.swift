import HumCore
import SwiftUI

/// A History window page: a title, the range and source its numbers cover, an
/// optional trailing control, and the content, scrolling as one.
struct HistoryPage<Accessory: View, Content: View>: View {
    var title: String
    /// Where the page's numbers come from, such as "Nov 2 – today · tracked by
    /// Hum from Spotify".
    var caption: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HistoryPageHeader(title: title, caption: caption) { accessory }
                content
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .historyScrollEdge()
    }
}

extension View {
    /// History mixes sources, so its covers may be Spotify's, which never pass
    /// under a material (DESIGN.md §3.6.1, §6): the content stops at the
    /// toolbar's lower edge, with a hairline once it has scrolled. That's the
    /// hard scroll edge on macOS 26; before it, the content is clipped to the
    /// page, below the toolbar, which draws its own hairline.
    @ViewBuilder
    func historyScrollEdge() -> some View {
        if #available(macOS 26, *) {
            scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            clipped()
        }
    }
}

extension HistoryPage where Accessory == EmptyView {
    init(title: String, caption: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, caption: caption, accessory: { EmptyView() }, content: content)
    }
}

struct HistoryPageHeader<Accessory: View>: View {
    var title: String
    var caption: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(HumColor.label)
                    .accessibilityAddTraits(.isHeader)
                // Wraps without `fixedSize`: the split view measures columns at
                // zero width, where a fixed-height caption grows a letter per line.
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(HumColor.secondaryLabel)
            }
            Spacer(minLength: 0)
            accessory
        }
    }
}

/// A heading inside a page.
struct HistorySubheading: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .humText(.sectionHeader)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Nothing to show yet: the system's empty state, with a symbol, one line saying
/// so, and one line on what will fill it (DESIGN.md §5.5).
struct HistoryEmptyState: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }
}

/// A song, artist, or album row: cover, two lines, and trailing text.
struct HistoryItemRow<Trailing: View>: View {
    var artworkKey: String?
    var title: String
    var subtitle: String
    var artworkSide: CGFloat = 32
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.m) {
            if let artworkKey {
                HistoryArtwork(key: artworkKey, side: artworkSide)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .humText(.rowTitle)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .humText(.rowSubtitle)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.s)
            trailing
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

/// A number set in the stat face, for trailing columns.
struct HistoryNumber: View {
    var text: String
    var color: HumColor = .secondaryLabel

    init(_ text: String, color: HumColor = .secondaryLabel) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(.callout, design: .rounded).weight(.medium).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
