import HumCore
import SwiftUI

/// Everything inside the player window.
struct PlayerRootView: View {
    @Environment(SurfacePager.self) private var pager
    @Environment(PlayerInteraction.self) private var interaction
    @Environment(\.playerActions) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playerLook) private var look
    @State private var size = CGSize(width: PlayerMetrics.defaultSide, height: PlayerMetrics.defaultSide)
    /// The window is an `NSGlassEffectView` (Compact and Minimal on macOS 26),
    /// so nothing inside it is glass again.
    @State private var usesWindowGlass = false

    var body: some View {
        let metrics = PlayerMetrics(side: min(size.width, size.height), cornerRadiusScale: look.look.cornerRadiusScale)
        let corners = RoundedRectangle(cornerRadius: Self.cornerRadius(
            style: look.style, surface: pager.current, size: size, scale: metrics.cornerRadiusScale
        ), style: .continuous)
        // Only while the page changes, never for hover (§6); a bar has none,
        // and its other surfaces open the player square.
        let showsIndicator = !look.isBar && pager.indicator.isShown
        let isPresented = interaction.isPresented || reduceMotion
        SurfaceContainer()
            .onPreferenceChange(WindowGlassKey.self) { usesWindowGlass = $0 }
            .overlay(alignment: .top) {
                // The top chrome's glass renders in one pass, never sampling itself.
                GlassGroup(spacing: Spacing.s) {
                    PageIndicator()
                        .padding(.top, PageIndicator.top(inset: metrics.contentInset))
                        .opacity(showsIndicator ? 1 : 0)
                        // `Motion.reveal`'s rise; opacity alone under Reduce Motion.
                        .offset(y: showsIndicator || reduceMotion ? 0 : Motion.revealTravel)
                        .allowsHitTesting(showsIndicator)
                        .accessibilityHidden(!showsIndicator)
                        .animation(showsIndicator ? Motion.reveal : Motion.conceal, value: showsIndicator)
                }
                .environment(\.colorScheme, .dark)
                .environment(\.humColorContext, .artwork)
            }
            .hudBandOverlay { VolumeHUDLayer() }
            .environment(\.isInWindowGlass, usesWindowGlass)
            .backgroundPreferenceValue(VolumeSwipeAreaKey.self) { anchor in
                GeometryReader { proxy in
                    Color.clear.onChange(of: anchor.map { proxy[$0] }, initial: true) { _, area in
                        interaction.volumeSwipeArea = area
                    }
                }
            }
            .modifier(AccentTransition())
            .environment(\.playerMetrics, metrics)
            // Concentric shapes inside (the glass card on macOS 26) follow the window's corners.
            .containerShape(corners)
            .clipShape(corners)
            // Materialize: scale and sharpen into place from the window's anchor.
            .scaleEffect(isPresented ? 1 : Motion.materializeScale, anchor: interaction.presentationAnchor)
            .blur(radius: isPresented ? 0 : Motion.materializeBlur)
            .animation(Motion.materialize, value: isPresented)
            .gesture(windowDrag)
            .allowsWindowActivationEvents(true)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                size = newSize
            }
            .onChange(of: reduceMotion, initial: true) { _, value in
                pager.reduceMotion = value
            }
            .onAppear { Self.runDebugKeyScript() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Hum Player")
            .accessibilityAction(named: "Next Surface") { pager.forward(animated: false) }
            .accessibilityAction(named: "Previous Surface") { pager.back(animated: false) }
    }

    /// The window's own corner radius (`PlayerContentView`): the style's
    /// corners, or a panel's while History or Status grows a bar or Wide to a
    /// square. A card keeps 12 pt at any size, where a panel's grow with it.
    nonisolated static func cornerRadius(style: PlayerStyleID, surface: Surface, size: CGSize, scale: CGFloat) -> CGFloat {
        let shape: PlayerContentView.CornerShape = StyleGeometry.needsExpansion(for: surface, style: style)
            ? .panel
            : PlayerContentView.CornerShape(style)
        return shape.radius(for: size, scale: scale)
    }

    /// `HUM_DEBUG_KEYS`, for checks of the keyboard paths in debug builds.
    private static func runDebugKeyScript() {
        #if DEBUG
        DebugKeyScript.runIfRequested()
        #endif
    }

    /// Dragging the content moves the window. Buttons and sliders take their own
    /// drags first.
    private var windowDrag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                actions.windowDrag(.changed(translation: value.translation))
            }
            .onEnded { _ in
                actions.windowDrag(.ended)
            }
    }
}

/// The volume HUD, centered over whichever surface is showing. It rises in with
/// `Motion.reveal` and fades out with `Motion.conceal` once the volume has held
/// still (DESIGN.md §5.8); under Reduce Motion it only fades. A newer library
/// notice takes its place.
private struct VolumeHUDLayer: View {
    @Environment(PlayerInteraction.self) private var interaction
    @Environment(LibraryStore.self) private var library: LibraryStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let level = interaction.volumeHUDLevel
        ZStack {
            if let level {
                VolumeHUD(level: level)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Motion.revealTravel)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(level == nil ? Motion.conceal : Motion.reveal, value: level == nil)
        .onChange(of: library?.notice?.id) { _, id in
            if id != nil { interaction.hideVolumeHUD() }
        }
    }
}
