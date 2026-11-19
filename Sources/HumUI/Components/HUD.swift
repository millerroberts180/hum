import HumCore
import SwiftUI

/// A centered capsule on `glassCard` with a glyph and a short label, for an
/// action whose result isn't otherwise visible (DESIGN.md §5.8). On macOS 26
/// the capsule is Liquid Glass.
struct HUD: View {
    var symbol: String
    var title: String

    /// The glyph, the size of the label's text.
    static let glyph: CGFloat = 13

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: Self.glyph, weight: .semibold))
                .foregroundStyle(HumColor.label)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(HumColor.label)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .hudCapsule()
        .environment(\.humColorContext, .material)
        .accessibilityElement(children: .combine)
    }
}

/// The volume as a HUD: the speaker glyph filled to the level, and a level bar,
/// with no words. A pure view: whoever shows it owns the timing and the motion.
struct VolumeHUD: View {
    /// 0...1.
    var level: Double

    /// The level bar, about as long as a HUD's label.
    static let levelWidth: CGFloat = 120

    var body: some View {
        let level = min(1, max(0, level))
        HStack(spacing: Spacing.s) {
            Image(systemName: "speaker.wave.3.fill", variableValue: level)
                .font(.system(size: HUD.glyph, weight: .semibold))
                .foregroundStyle(HumColor.label)
            CapsuleTrack(fraction: level, isActive: true)
                .frame(width: Self.levelWidth)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .hudCapsule()
        .environment(\.humColorContext, .material)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue(Self.spokenValue(level))
    }

    /// "40 percent".
    nonisolated static func spokenValue(_ level: Double) -> String {
        "\(Int((min(1, max(0, level)) * 100).rounded())) percent"
    }
}

/// The library's latest notice as a HUD. It fades in with `Motion.reveal`, rising
/// 8 pt, and fades out once the store clears it after 1.2 s. On macOS 26 the
/// glass materializes instead. Under Reduce Motion it only fades.
struct LibraryHUD: View {
    @Environment(LibraryStore.self) private var library: LibraryStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let notice = library?.notice
        ZStack {
            if let notice {
                HUD(symbol: Self.symbol(for: notice), title: Self.title(for: notice))
                    .id(notice.id)
                    .hudTransition(reduceMotion: reduceMotion)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(notice == nil ? Motion.conceal : Motion.reveal, value: notice?.id)
        .onChange(of: notice?.id) { _, id in
            guard id != nil, let notice else { return }
            AccessibilityNotification.Announcement(Self.title(for: notice)).post()
        }
    }

    static func title(for notice: LibraryNotice) -> String {
        switch notice.kind {
        case .saved: "Added to Favorites"
        case .unsaved: "Removed from Favorites"
        }
    }

    static func symbol(for notice: LibraryNotice) -> String {
        switch notice.kind {
        case .saved: SaveVocabulary.symbol(isSaved: true)
        case .unsaved: SaveVocabulary.symbol(isSaved: false)
        }
    }
}

/// Echo's notice, one HUD at a time with the volume HUD, which
/// centers in the same place: a volume change hides the notice for good, and
/// a newer notice hides the volume HUD (`PlayerRootView`).
struct LibraryNoticeLayer: View {
    @Environment(PlayerInteraction.self) private var interaction: PlayerInteraction?
    @Environment(LibraryStore.self) private var library: LibraryStore?
    /// The notice the volume HUD replaced, so it doesn't come back after.
    @State private var supersededNotice: UUID?

    var body: some View {
        let isVolumeShowing = interaction?.volumeHUDLevel != nil
        let shows = Self.showsNotice(library?.notice?.id, isVolumeShowing: isVolumeShowing, superseded: supersededNotice)
        // Hidden rather than removed, so a new notice is still announced.
        LibraryHUD()
            .opacity(shows ? 1 : 0)
            .accessibilityHidden(!shows)
            .animation(Motion.conceal, value: shows)
            .onChange(of: isVolumeShowing) { _, showing in
                if showing { supersededNotice = library?.notice?.id }
            }
    }

    nonisolated static func showsNotice(_ notice: UUID?, isVolumeShowing: Bool, superseded: UUID?) -> Bool {
        guard let notice else { return true }
        return !isVolumeShowing && notice != superseded
    }
}

private extension View {
    /// `glassCard` in a capsule on macOS 15; Liquid Glass on 26, except under
    /// Reduce Transparency and inside the window's own glass.
    func hudCapsule() -> some View {
        floatingGlass(in: Capsule(), fallback: .glassCard)
            // For `hudBandOverlay`, which places the capsule by its size.
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: HUDSizeKey.self, value: proxy.size)
                }
            }
    }

    @ViewBuilder
    func hudTransition(reduceMotion: Bool) -> some View {
        if #available(macOS 26, *) {
            glassEffectTransition(reduceMotion ? .identity : .materialize)
                .transition(.opacity)
        } else {
            transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Motion.revealTravel)))
        }
    }
}

#if DEBUG
struct HUD_Previews: PreviewProvider {
    static var previews: some View {
        PreviewGallery(backdrop: .artwork) {
            VStack(spacing: Spacing.m) {
                HUD(symbol: "heart.fill", title: "Added to Favorites")
                VolumeHUD(level: 0.4)
            }
        }
    }
}
#endif
