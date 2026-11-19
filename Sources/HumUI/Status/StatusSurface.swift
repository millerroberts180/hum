import AppKit
import HumCore
import SwiftUI
import UniformTypeIdentifiers

/// Status: which music app Hum follows, and whether each one lets Hum control
/// it (DESIGN.md §6.3), on the same backdrop as Echo. The one place on the
/// player that names the music apps. It has no account or sign-in: Hum has
/// none (§1.3).
///
/// The Apps rows refresh when Status appears and when Hum becomes active
/// again, never on a timer. The demo shows the apps installed on this Mac,
/// each with `--demo-automation`'s permission, and never asks macOS.
struct StatusSurface: View {
    @Environment(NowPlayingStore.self) private var store
    @Environment(\.playerMetrics) private var metrics
    @Environment(\.playerActions) private var actions
    /// Which supported apps are on this Mac, as of the last refresh.
    @State private var installed: Set<SourceID> = []
    /// The demo's apps that Allow… was clicked for, which it then shows as
    /// allowed without asking macOS.
    @State private var demoAllowed: Set<SourceID> = []

    var body: some View {
        SurfaceBackdrop(artwork: store.artwork) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    StatusConnectionCard(connection: connection)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Apps")
                            .humText(.sectionHeader)
                            .accessibilityAddTraits(.isHeader)
                        AppAccessCard(rows: rows, perform: perform)
                    }
                    Button {
                        actions.openSettingsPane(.sources)
                    } label: {
                        ActionLabel("Settings…", symbol: "gearshape")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .help("Open Settings › Sources")
                }
                .padding(.horizontal, metrics.contentInset)
                // Clear of the page indicator along the top edge, as on Echo.
                .padding(.top, metrics.contentInset + PageIndicator.contentClearance)
                .padding(.bottom, metrics.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
        // Status has no items of its own, only the player section (§4.4).
        .contextMenu { PlayerMenuItems(startsWithSeparator: false) }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private var sectionSpacing: CGFloat {
        metrics.sizeClass == .small ? Spacing.m : Spacing.l
    }

    private var isDemo: Bool { store.source(for: .demo) != nil }

    private var connection: StatusConnection {
        StatusConnection.make(
            sourceID: store.activeSourceID,
            displayName: store.activeSource?.displayName,
            state: store.activeState,
            isAutomatic: store.preferredSourceID == nil
        )
    }

    private var rows: [AppAccessRow] {
        AppAccessRow.rows(
            in: store,
            installed: installed,
            demoAutomation: LaunchOptions.current.demoAutomation,
            demoAllowed: demoAllowed
        )
    }

    private func refresh() {
        installed = Set(AppAccessRow.apps.lazy
            .filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil }
            .map(\.id))
        let store = store
        Task { await AppAccessRow.refreshPermissions(in: store) }
    }

    private func perform(_ action: AppAccessRow.Action, for row: AppAccessRow) {
        switch action {
        case .openSystemSettings:
            PermissionGuide.openAutomationSettings()
        case .allow:
            if isDemo {
                demoAllowed.insert(row.id)
            } else if let source = store.source(for: row.id) {
                Task { await source.requestAutomationPermission() }
            }
        }
    }
}

/// The app Hum follows: its icon, name and what it's doing.
private struct StatusConnectionCard: View {
    var connection: StatusConnection

    static let iconSide: CGFloat = 32

    var body: some View {
        HStack(spacing: Spacing.m) {
            if let icon = connection.icon {
                AppIcon(icon: icon, side: Self.iconSide)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.name)
                    .humText(.rowTitle)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(connection.status)
                    .humText(.rowSubtitle)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption = connection.caption {
                    Text(caption)
                        .humText(.caption, color: .tertiaryLabel)
                        .padding(.top, Spacing.xxs)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCardFill(in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard connection != .noApp else { return "\(connection.name). \(connection.status)" }
        return ["Connected to \(connection.name)", connection.status, connection.caption]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
}

/// Music, then Spotify, each with whether Hum may control it.
private struct AppAccessCard: View {
    var rows: [AppAccessRow]
    var perform: (AppAccessRow.Action, AppAccessRow) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider()
                        .padding(.leading, Spacing.m + AppAccessRowView.iconSide + Spacing.s)
                }
                AppAccessRowView(row: row) { perform($0, row) }
            }
        }
        .echoCardFill(in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// One app: its icon and name, then its state trailing, and the button that
/// changes it, if any. Where the button doesn't fit beside the state, it goes
/// under it.
private struct AppAccessRowView: View {
    var row: AppAccessRow
    var perform: (AppAccessRow.Action) -> Void

    static let iconSide: CGFloat = 20

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.s) {
                title
                Spacer(minLength: Spacing.s)
                state
                button
            }
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    title
                    Spacer(minLength: Spacing.s)
                    state
                }
                button
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .modifier(RowAction(row: row, perform: perform))
    }

    private var title: some View {
        HStack(spacing: Spacing.s) {
            AppIcon(icon: icon, side: Self.iconSide)
                .opacity(row.isDimmed ? 0.5 : 1)
            Text(row.app.name)
                .humText(.rowTitle, color: row.isDimmed ? .tertiaryLabel : nil)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    /// The app's own icon; the generic one while it isn't installed (§6.3).
    private var icon: StatusConnection.Icon {
        row.isDimmed ? .generic : .app(bundleIdentifier: row.app.bundleIdentifier)
    }

    private var state: some View {
        HStack(spacing: Spacing.xxs) {
            if let glyph = row.glyph {
                Image(systemName: glyph.symbol)
                    .foregroundStyle(color(glyph.tint))
            }
            Text(row.statusText)
                .lineLimit(1)
                .foregroundStyle(row.isDimmed ? HumColor.tertiaryLabel : HumColor.secondaryLabel)
        }
        .humText(.rowSubtitle)
        .fixedSize()
    }

    @ViewBuilder
    private var button: some View {
        if let action = row.action, let title = row.actionTitle {
            Button { perform(action) } label: { ActionLabel(title) }
                .buttonStyle(ActionButtonStyle(compact: true))
                .fixedSize()
        }
    }

    private func color(_ tint: AppAccessRow.Glyph.Tint) -> HumColor {
        switch tint {
        case .secondaryLabel: HumColor.secondaryLabel
        case .warning: HumColor.warning
        case .tertiaryLabel: HumColor.tertiaryLabel
        }
    }
}

/// The row's button, for VoiceOver, which reads the row as one element.
private struct RowAction: ViewModifier {
    var row: AppAccessRow
    var perform: (AppAccessRow.Action) -> Void

    func body(content: Content) -> some View {
        if let action = row.action, let title = row.actionTitle {
            content.accessibilityAction(named: title) { perform(action) }
        } else {
            content
        }
    }
}

/// An app's icon as Status draws it: the app's own from its bundle, as macOS
/// hands it over (`AppIconLookup`), the system's generic application icon, or
/// Hum's.
struct AppIcon: View {
    var icon: StatusConnection.Icon
    var side: CGFloat

    var body: some View {
        Image(nsImage: Self.image(for: icon))
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }

    static func image(for icon: StatusConnection.Icon, lookup: AppIconLookup = .workspace) -> NSImage {
        switch icon {
        case .app(let bundleIdentifier): lookup.icon(bundleIdentifier: bundleIdentifier)
        case .generic: lookup.genericIcon()
        case .hum: NSApp.applicationIconImage
        }
    }
}

#if DEBUG
struct StatusSurface_Previews: PreviewProvider {
    static var previews: some View {
        PreviewGallery {
            StatusSurface()
        }
    }
}
#endif
