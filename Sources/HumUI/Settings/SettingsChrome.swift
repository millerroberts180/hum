import SwiftUI

/// Sizes for the Settings window's own chrome: the window and the sidebar. The
/// window reads down rather than across, so it stays narrow.
nonisolated enum SettingsMetrics {
    static let windowSize = CGSize(width: 688, height: 580)
    /// Wide enough for every pane's name whole, "History & Privacy" the longest.
    static let sidebarWidth: CGFloat = 188
    static let sidebarTile: CGFloat = 19
    /// Room between the title bar and the first sidebar row.
    static let sidebarTopInset: CGFloat = Spacing.m
}

extension SettingsPane {
    /// One distinct tint per pane, the way System Settings colors its sidebar.
    var tint: Color {
        switch self {
        case .general, .about: .gray
        case .appearance: .blue
        case .player: .indigo
        case .shortcuts: .cyan
        case .sources: .pink
        case .echoPrivacy: .purple
        }
    }
}

/// A pane's tinted glyph tile, for the sidebar.
struct SettingsPaneTile: View {
    var pane: SettingsPane
    var size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        Image(systemName: pane.systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(shape.fill(pane.tint.gradient))
            .overlay(shape.strokeBorder(.white.opacity(0.15)))
            .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
            .accessibilityHidden(true)
    }
}

/// One pane in the sidebar: its small tile, then its name in the sidebar's own
/// font, which follows the system's sidebar size.
struct SettingsSidebarRow: View {
    var pane: SettingsPane

    var body: some View {
        Label {
            Text(pane.title)
                .lineLimit(1)
        } icon: {
            SettingsPaneTile(pane: pane, size: SettingsMetrics.sidebarTile)
        }
        .padding(.vertical, 1)
        .tag(pane)
    }
}

/// A switch with a quieter second line saying what it does.
struct DetailToggle: View {
    var title: String
    var detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            DetailLabel(title: title, detail: detail)
        }
    }
}

/// A control's title with a caption-size explanation under it.
struct DetailLabel: View {
    var title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(HumColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A grouped-form footer that reads as a note: leading-aligned, caption, secondary.
struct FooterNote: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(HumColor.secondaryLabel)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
