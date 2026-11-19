import HumCore
import SwiftUI

/// Everything over the cover on hover, bottom to top: transport, seek bar, track
/// header, and any banner. What appears depends on the size class (§6.1) and on
/// the look's choice of hover controls (§8).
struct NowControls: View {
    var menu: TrackMenu?
    /// The S volume popover, drawn by the view that covers the player.
    var isVolumeOpen: Binding<Bool> = .constant(false)

    @Environment(NowPlayingStore.self) private var store
    @Environment(\.playerMetrics) private var metrics
    @Environment(\.playerLook) private var look
    @State private var dismissedPermissionFor: SourceID?

    var body: some View {
        let shown = look.hoverControls(at: metrics.sizeClass)
        let canSave = shown.contains(.save) && store.capabilities.contains(.favorite)
        let canAdjustVolume = shown.contains(.volume) && store.capabilities.contains(.volume)
        VStack(alignment: .leading, spacing: spacing) {
            banners
            switch metrics.sizeClass {
            case .small:
                if canSave || canAdjustVolume {
                    HStack {
                        if canAdjustVolume {
                            VolumeButton(isOpen: isVolumeOpen)
                        }
                        Spacer(minLength: 0)
                        if canSave {
                            SaveButton()
                        }
                    }
                    .padding(-metrics.tertiary.outset)
                }
                if shown.contains(.seekBar) {
                    SeekBar()
                }
                TransportRow(showsShuffleRepeat: shown.contains(.shuffleRepeat))
            case .medium, .large:
                if shown.contains(.trackInfo), let track = store.track {
                    TrackHeader(
                        track: track,
                        menu: menu,
                        showsSave: shown.contains(.save),
                        // The album shares the artist's line at L (§7).
                        showsAlbum: shown.contains(.album) && metrics.sizeClass == .large
                    )
                } else if shown.contains(.save) {
                    HStack(spacing: Spacing.xxs) {
                        Spacer(minLength: 0)
                        if canSave {
                            SaveButton()
                        }
                        if let menu {
                            MoreButton(menu: menu)
                        }
                    }
                    .padding(.trailing, -metrics.tertiary.outset)
                    .padding(.vertical, -metrics.tertiary.outset)
                }
                if shown.contains(.seekBar) {
                    SeekBar()
                }
                TransportRow(showsShuffleRepeat: shown.contains(.shuffleRepeat))
                if metrics.sizeClass == .large, canAdjustVolume {
                    HStack(spacing: Spacing.s) {
                        VolumeControl()
                        NowLibraryButtons()
                    }
                    .padding(.top, Spacing.xxs)
                } else if metrics.sizeClass == .large, shown.contains(.volume) {
                    NowLibraryButtons()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        if let warning = store.warning {
            WarningBanner(warning: warning) { store.dismissWarning() }
                .transition(.opacity)
        } else if store.permission == .denied,
                  let source = store.activeSource,
                  dismissedPermissionFor != source.id {
            PermissionBanner {
                dismissedPermissionFor = source.id
            }
            .transition(.opacity)
        }
    }

    /// The seek bar's 20-pt hit strip already leaves air around its line, so
    /// the rows sit close at S and open up with the size class.
    private var spacing: CGFloat {
        switch metrics.sizeClass {
        case .small: Spacing.xs
        case .medium: Spacing.s
        case .large: Spacing.m
        }
    }
}
