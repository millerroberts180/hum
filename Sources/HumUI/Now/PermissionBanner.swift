import HumCore
import SwiftUI

/// Shown above the controls when a track is showing but Hum isn't allowed to
/// control its app (DESIGN.md §5.8). It doesn't name the app; Status does.
/// Never a modal alert.
struct PermissionBanner: View {
    var onDismiss: () -> Void

    @Environment(\.playerMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                // Only the glyph takes the status color (§3.5).
                Image(systemName: HumIcon.permission)
                    .foregroundStyle(HumColor.warning)
                    .accessibilityHidden(true)
                Text(PermissionGuide.bannerMessage)
                    .humText(.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Side by side where they fit, else stacked with the default on top.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s) {
                    Spacer(minLength: 0)
                    notNow
                    openSettings
                }
                VStack(alignment: .trailing, spacing: Spacing.s) {
                    openSettings
                    notNow
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            // A banner's buttons are `.regular` (§3.8). At S, “Open System
            // Settings” fits only at `.small`.
            .controlSize(metrics.sizeClass == .small ? .small : .regular)
        }
        .padding(Spacing.m)
        .bannerBackground()
        .accessibilityElement(children: .contain)
    }

    private var notNow: some View {
        Button("Not Now", action: onDismiss)
            .bannerButtonStyle(prominent: false)
    }

    private var openSettings: some View {
        Button("Open System Settings", action: PermissionGuide.openAutomationSettings)
            .bannerButtonStyle(prominent: true)
    }
}

/// A command keeps failing: say so plainly, once, until dismissed.
struct WarningBanner: View {
    var warning: PlaybackWarning
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: HumIcon.warning)
                .foregroundStyle(HumColor.warning)
                .accessibilityHidden(true)
            Text(warning.message)
                .humText(.cardTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: HumIcon.dismiss)
            }
            .buttonStyle(PlayerButtonStyle(.icon, size: .icon))
            .padding(-ControlSizing.icon.outset)
            .accessibilityLabel("Dismiss")
            .help("Dismiss")
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(HumColor.warning)
                .opacity(0.1)
        }
        .bannerBackground()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isStaticText)
    }
}

#if DEBUG
struct PermissionBanner_Previews: PreviewProvider {
    static var previews: some View {
        PreviewGallery(backdrop: .artwork) {
            VStack(spacing: Spacing.s) {
                Spacer()
                PermissionBanner(onDismiss: {})
                WarningBanner(warning: PlaybackWarning(message: "Music isn\u{2019}t responding."), onDismiss: {})
            }
            .padding(Spacing.s)
        }
    }
}
#endif
