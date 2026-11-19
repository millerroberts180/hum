import AppKit
import HumCore
import SwiftUI

/// A centered symbol, a short title, a short explanation, and at most one
/// button (DESIGN.md §5.5). The copy is factual. At M and L it's the system's
/// `ContentUnavailableView`; S keeps a tighter layout of its own to fit, and
/// wraps rather than truncates: where the words don't fit, the symbol gives
/// way first, then they scroll.
struct EmptyState: View {
    struct Action {
        var title: String
        var perform: @MainActor () -> Void
    }

    var symbol: String
    var title: String
    var message: String?
    var action: Action?

    @Environment(\.playerMetrics) private var metrics

    /// The symbol at S, where `ContentUnavailableView`'s would crowd the text.
    static let compactSymbolSize: CGFloat = 28

    var body: some View {
        if metrics.sizeClass == .small {
            compact
        } else {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                if let message { Text(message) }
            } actions: {
                if let action {
                    Button(action.title) { action.perform() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        }
    }

    private var compact: some View {
        ViewThatFits(in: .vertical) {
            compact(showsSymbol: true)
            compact(showsSymbol: false)
            ScrollView { compact(showsSymbol: false) }
        }
    }

    private func compact(showsSymbol: Bool) -> some View {
        VStack(spacing: Spacing.s) {
            if showsSymbol {
                Image(systemName: symbol)
                    .font(.system(size: Self.compactSymbolSize, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(HumColor.tertiaryLabel)
                    .accessibilityHidden(true)
            }
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(HumColor.label)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(metrics.sizeClass == .small ? .caption : .callout)
                        .foregroundStyle(HumColor.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            if let action {
                Button(action.title) { action.perform() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(metrics.sizeClass == .small ? .regular : .large)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(.horizontal, metrics.contentInset * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Carries out a `LibraryUnavailable.Fix`.
@MainActor
enum LibraryFixes {
    static func perform(_ fix: LibraryUnavailable.Fix, library: LibraryStore?) {
        switch fix {
        case .allowAutomation:
            guard let library else { return }
            Task { await library.nowPlaying.requestPermission() }
        case .openAutomationSettings:
            PermissionGuide.openAutomationSettings()
        case .openApp:
            guard let bundleID = appToOpen(fix, library: library),
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// The app an Open fix starts: the one its source names, whichever source
    /// the library follows by then.
    static func appToOpen(_ fix: LibraryUnavailable.Fix, library: LibraryStore?) -> String? {
        guard case .openApp(let id, _) = fix else { return nil }
        return library?.nowPlaying.source(for: id)?.appBundleIdentifier
    }
}

/// An action that didn't work: a red glyph, the reason, and one recovery action.
/// It stays until dismissed or fixed; never a toast. Where the reason and the
/// action can't share a row, as at the smallest players, the action goes under
/// the reason, so its title is never cut short.
struct FailureBanner: View {
    var message: String
    var actionTitle: String?
    var action: (@MainActor () -> Void)?
    var onDismiss: (@MainActor () -> Void)?

    /// The narrowest the reason gets beside the action before the action moves
    /// under it.
    static let minimumMessageWidth: CGFloat = 120

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content(actionBelow: false)
            content(actionBelow: true)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(HumColor.critical)
                .opacity(0.1)
        }
        .bannerBackground()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message)
    }

    private func content(actionBelow: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: HumIcon.warning)
                .foregroundStyle(HumColor.critical)
                .accessibilityHidden(true)
            if actionBelow {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    messageText
                    actionButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                messageText
                    .frame(idealWidth: Self.minimumMessageWidth, maxWidth: .infinity, alignment: .leading)
                actionButton
            }
            if let onDismiss {
                Button { onDismiss() } label: {
                    Image(systemName: HumIcon.dismiss)
                }
                .buttonStyle(PlayerButtonStyle(.icon, size: .icon))
                .padding(-ControlSizing.icon.outset)
                .accessibilityLabel("Dismiss")
                .help("Dismiss")
            }
        }
    }

    private var messageText: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(HumColor.label)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionTitle, let action {
            Button(actionTitle) { action() }
                .bannerButtonStyle(prominent: false)
                .controlSize(.small)
                .fixedSize()
        }
    }
}

/// The store's current failure as a banner, with its fix, or Try Again when
/// the request may work a second time.
struct LibraryFailureBanner: View {
    @Environment(LibraryStore.self) private var library: LibraryStore?

    var body: some View {
        if let library, let failure = library.failure {
            FailureBanner(
                message: failure.message,
                actionTitle: Self.actionTitle(failure),
                action: action(failure, library: library),
                onDismiss: { library.dismissFailure() }
            )
            .id(failure.id)
            .transition(.opacity)
        }
    }

    /// The banner's one recovery action (DESIGN.md §4.6): the fix, or Try
    /// Again for a failure that may pass.
    nonisolated static func actionTitle(_ failure: LibraryFailure) -> String? {
        if let fix = failure.fix {
            return LibraryUnavailable(title: "", message: "", fix: fix).fixTitle
        }
        return failure.canRetry ? "Try Again" : nil
    }

    private func action(_ failure: LibraryFailure, library: LibraryStore) -> (@MainActor () -> Void)? {
        if let fix = failure.fix {
            return {
                library.dismissFailure()
                LibraryFixes.perform(fix, library: library)
            }
        }
        guard failure.canRetry else { return nil }
        return { library.retryFailure() }
    }
}

#if DEBUG
struct EmptyState_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreviewGallery {
                EmptyState(symbol: HumIcon.noSource, title: "No Music App", message: "Install Music or Spotify, or open one of them.")
            }
            PreviewGallery {
                EmptyState(
                    symbol: HumIcon.permission,
                    title: "Allow Access",
                    message: "Hum needs your permission to control your music app.",
                    action: EmptyState.Action(title: "Allow…") {}
                )
            }
        }
    }
}
#endif
