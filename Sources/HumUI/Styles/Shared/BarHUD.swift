import HumCore
import SwiftUI

/// The HUD in Title, Text and Strip, which are too short for the capsule
/// (DESIGN.md §5.8): its glyph and label take the place of the bar's content
/// while it shows (`Motion.hudHold`, 1.2 s), then the content returns. The bar
/// is marked `hudInline()`, so the floating HUD stays hidden but keeps its
/// timing and announcements.
///
/// One at a time, as the capsule: a newer notice puts the volume away, and a
/// volume change puts the notice away for good.
struct BarHUD<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(PlayerInteraction.self) private var interaction: PlayerInteraction?
    @Environment(LibraryStore.self) private var library: LibraryStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.surfaceIsActive) private var surfaceIsActive
    /// The notice the volume replaced, so it doesn't come back after.
    @State private var supersededNotice: UUID?

    var body: some View {
        let item = BarHUDItem.current(
            volume: interaction?.volumeHUDLevel,
            notice: library?.notice,
            superseded: supersededNotice
        )
        ZStack {
            content
                .opacity(item == nil ? 1 : 0)
                .allowsHitTesting(item == nil)
            if let item {
                BarHUDLabel(item: item)
                    .id(item.identity)
                    .transition(.opacity)
            }
        }
        .hudInline(surfaceIsActive)
        .animation(item == nil ? Motion.conceal : Motion.reveal, value: item?.identity)
        .onChange(of: interaction?.volumeHUDLevel != nil) { _, showing in
            if showing { supersededNotice = library?.notice?.id }
        }
    }
}

/// What a bar's HUD shows.
nonisolated enum BarHUDItem: Equatable, Sendable {
    /// 0...1.
    case volume(Double)
    case notice(LibraryNotice)

    /// Changes only when a different HUD takes over, not as the level moves.
    var identity: String {
        switch self {
        case .volume: "volume"
        case .notice(let notice): notice.id.uuidString
        }
    }

    /// The volume while it shows, else the latest notice unless the volume
    /// replaced it.
    static func current(volume: Double?, notice: LibraryNotice?, superseded: UUID?) -> BarHUDItem? {
        if let volume { return .volume(min(1, max(0, volume))) }
        if let notice, notice.id != superseded { return .notice(notice) }
        return nil
    }
}

/// The glyph and label, centered in the bar and set in its colors. VoiceOver
/// hears the floating HUD's announcement, so this is hidden from it.
private struct BarHUDLabel: View {
    var item: BarHUDItem

    var body: some View {
        HStack(spacing: Spacing.s) {
            switch item {
            case .volume(let level):
                Image(systemName: "speaker.wave.3.fill", variableValue: level)
                    .font(.system(size: HUD.glyph, weight: .semibold))
                    .foregroundStyle(HumColor.label)
                CapsuleTrack(fraction: level, isActive: true)
                    .frame(maxWidth: VolumeHUD.levelWidth)
            case .notice(let notice):
                Image(systemName: LibraryHUD.symbol(for: notice))
                    .font(.system(size: HUD.glyph, weight: .semibold))
                    .foregroundStyle(HumColor.label)
                Text(LibraryHUD.title(for: notice))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(HumColor.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
