import HumCore
import SwiftUI

/// The layer that appears over the cover on hover or focus: the controls, on
/// the scrim, or with Liquid Glass in the controls platter (DESIGN.md §3.6, §7).
///
/// Controls settle up into place as they fade in and drift back down as they
/// leave. Under Reduce Motion they only fade. Everything here is drawn in the
/// artwork color context, so it is light-on-dark whatever the appearance; the S
/// volume popover is drawn on material in the real appearance.
struct ControlsOverlay: View {
    var isRevealed: Bool
    var menu: TrackMenu?

    @Environment(\.playerMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.surfaceIsActive) private var surfaceIsActive
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @State private var isVolumeOpen = false
    /// The controls' measured height, which the scrim deepens behind.
    @State private var controlsHeight: CGFloat = 0

    var body: some View {
        let usesPlatter = ControlsPlatter.usesPlatter(
            liquidGlass: LiquidGlass.isOn(settings),
            reduceTransparency: reduceTransparency
        )
        ZStack(alignment: .bottom) {
            if !usesPlatter {
                Scrim(contentHeight: controlsHeight)
                    .opacity(isRevealed ? 1 : 0)
            }
            controls(usesPlatter: usesPlatter)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    controlsHeight = height
                }
                .offset(y: isRevealed || reduceMotion ? 0 : Motion.revealTravel)
                .opacity(isRevealed ? 1 : 0)
            if isRevealed, surfaceIsActive {
                // A HUD goes on the cover above the controls, not on the title
                // row it may be confirming (§5.8).
                Color.clear
                    .hudBand()
                    .padding(.top, metrics.contentInset + PageIndicator.contentClearance)
                    .padding(.bottom, controlsHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .environment(\.humColorContext, .artwork)
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(isRevealed)
        .accessibilityHidden(!isRevealed)
        .animation(isRevealed ? Motion.reveal : Motion.conceal, value: isRevealed)
        .volumePopover(isOpen: $isVolumeOpen)
        .onChange(of: isRevealed) { _, revealed in
            if !revealed { isVolumeOpen = false }
        }
    }

    /// On the scrim the controls take the content inset. In the platter they
    /// sit `Spacing.s` in from its sides, with `Spacing.m` of room above and
    /// below them together, and the platter `Spacing.s` in from the window.
    @ViewBuilder
    private func controls(usesPlatter: Bool) -> some View {
        let controls = NowControls(menu: menu, isVolumeOpen: $isVolumeOpen)
        if usesPlatter {
            controls
                .padding(.horizontal, ControlsPlatter.inset)
                .padding(.vertical, ControlsPlatter.verticalRoom / 2)
                .background { ControlsPlatter(windowRadius: metrics.cornerRadius) }
                .environment(\.isInControlsPlatter, true)
                .padding([.horizontal, .bottom], ControlsPlatter.inset)
        } else {
            controls
                .padding(metrics.contentInset)
        }
    }
}
