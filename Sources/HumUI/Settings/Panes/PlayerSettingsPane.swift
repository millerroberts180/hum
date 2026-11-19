import HumCore
import SwiftUI

/// Settings › Behavior: what appears when you reach for the player, its size,
/// where it lives, and when it shows (DESIGN.md §8). The pane was called
/// Player, which now names its sidebar group; its stored value is still
/// `player`.
///
/// The controls and size belong to the current style; the window and gesture
/// settings are the same for every style. Menu Bar has no window, so its size,
/// position and visibility rows hide; its popover always shows its controls
/// and never pages, so "Always show controls" and the gestures hide too.
struct PlayerSettingsPane: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerSizing.self) private var sizing: PlayerSizing?
    @Environment(\.colorScheme) private var colorScheme

    private var style: PlayerStyleID { settings.appearance.style }

    var body: some View {
        @Bindable var settings = settings
        let rows = PlayerRow.rows(for: style)
        Form {
            Section {
                if rows.contains(.alwaysShowControls) {
                    DetailToggle(
                        title: "Always show controls",
                        detail: "Keep them up instead of waiting for the pointer.",
                        isOn: $settings.appearance.alwaysShowControls
                    )
                    .disabled(!showsControlsOnHover)
                }
                ForEach(HoverControls.ordered.filter { style.hoverChoices.contains($0) }, id: \.rawValue) { control in
                    Toggle(isOn: hoverBinding(control)) {
                        Label {
                            // Only a window that resizes has sizes to name.
                            DetailLabel(title: control.title, detail: style.hasWindow && !style.isBar ? control.sizeClasses(in: style) : nil)
                        } icon: {
                            // One width for every glyph, so the titles line up.
                            Image(systemName: Self.glyph(for: control))
                                .foregroundStyle(HumColor.secondaryLabel)
                                .frame(width: Spacing.xl)
                        }
                    }
                }
            } header: {
                Text("Controls")
            } footer: {
                FooterNote(controlsIntro + " Play, pause, and skip always appear. Changes apply to the \(style.title) style.")
            }

            if rows.contains(.size) {
                Section {
                    TileRow(title: "Size", detail: sizeDetail) {
                        ChoiceTiles(
                            PlayerSizePreset.allCases,
                            selection: currentPreset,
                            columns: 3,
                            artHeight: 72,
                            title: \.title,
                            pick: { sizing?.apply($0) }
                        ) { preset in
                            SizeTileArt(preset: preset, style: style, cornerRadiusScale: cornerRadiusScale)
                        }
                    }
                } header: {
                    Text("Size")
                }
            }

            if rows.contains(.position) {
                Section {
                    TileRow(title: "Position", detail: sizing?.pin == nil ? "Drag the player anywhere, or pick a place." : nil) {
                        PositionTile(style: style, pin: sizing?.pin, playerSize: sizing?.size) { position in
                            sizing?.pin(to: position)
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                    DetailToggle(
                        title: "Snap when thrown",
                        detail: "Throw the player and it settles in the nearest of these places.",
                        isOn: $settings.behavior.snapToCorners
                    )
                } header: {
                    Text("Position")
                }
            }

            if rows.contains(.visibility) {
                Section {
                    TileRow(title: "Show the player", detail: visibilityDetail(settings.behavior.visibility)) {
                        ChoiceTiles(
                            PlayerVisibility.allCases,
                            selection: $settings.behavior.visibility,
                            columns: 4,
                            artHeight: 60,
                            title: \.title
                        ) { mode in
                            VisibilityTileArt(mode: mode, style: style)
                        }
                    }
                } header: {
                    Text("Visibility")
                }
            }

            Section {
                DetailToggle(
                    title: "Keep above other windows",
                    detail: "The player floats over the app you’re using.",
                    isOn: $settings.behavior.alwaysOnTop
                )
                DetailToggle(
                    title: "Show on every Space",
                    detail: "The player follows you to every desktop and full-screen app.",
                    isOn: $settings.behavior.showOnAllSpaces
                )
            } header: {
                Text("Window")
            } footer: {
                if !style.hasWindow {
                    FooterNote("Size, position, when the player shows, and gestures apply when it’s in a window.")
                }
            }

            if rows.contains(.gestures) {
                Section("Gestures") {
                    DetailToggle(
                        title: "Swipe between surfaces",
                        detail: "Swipe left or right with two fingers to move between Now, History, and Status.",
                        isOn: $settings.behavior.swipeBetweenSurfaces
                    )
                    DetailToggle(
                        title: "Swipe to skip",
                        detail: "On the cover in Now, a two-finger swipe skips to the next or previous track instead.",
                        isOn: $settings.behavior.swipeToSkip
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Each hover control's glyph, the label's icon.
    static func glyph(for control: HoverControls) -> String {
        switch control {
        case .trackInfo: "textformat"
        case .album: "square.stack"
        case .seekBar: "timeline.selection"
        case .shuffleRepeat: HumIcon.shuffle
        case .save: HumIcon.favorite
        case .volume: HumIcon.volumeHigh
        default: "circle"
        }
    }

    /// Strip, Wide, and Big Art always show their controls (§7).
    private var showsControlsOnHover: Bool {
        ![.strip, .wide, .bigArt].contains(style)
    }

    private var controlsIntro: String {
        switch style {
        case .strip: "What the strip shows beside the cover and transport."
        case .wide: "What the card shows beside the cover."
        case .bigArt: "What the card shows under the cover."
        case .menuBar: "What the menu bar’s popover shows."
        case .artOnly, .text, .title: "What appears when you point at the player. A smaller player has room for less."
        }
    }

    private var sizeDetail: String {
        style.isSquare
            ? "Drag any edge of the player for a size between these."
            : "Drag either end of the player for any width between these."
    }

    /// The look's corners in the appearance Settings is shown in, so the size
    /// tiles round as the player does.
    private var cornerRadiusScale: Double {
        settings.appearance.look(for: style, in: LookAppearance(colorScheme)).cornerRadiusScale
    }

    /// The preset nearest the player's size, or its default before it has one.
    private var currentPreset: PlayerSizePreset {
        PlayerSizePreset(sizing?.size ?? StyleGeometry.defaultSize(for: style), style: style)
    }

    private func visibilityDetail(_ mode: PlayerVisibility) -> String {
        switch mode {
        case .pinned: "On screen until you hide it."
        case .trackChanges: "Appears for a moment when the track changes."
        case .tucked: "Hangs under the menu bar and slides up out of the way."
        case .summoned: "Only when you open it from the menu bar or a shortcut."
        }
    }

    /// One hover control for the current style, the same in light and dark.
    /// Changing it shows the player's controls for a moment, so it can be seen.
    private func hoverBinding(_ control: HoverControls) -> Binding<Bool> {
        let style = style
        return Binding {
            settings.appearance.look(for: style, in: .dark).hoverControls.contains(control)
        } set: { isOn in
            settings.appearance.updateLookInBothAppearances(for: style) { look in
                if isOn { look.hoverControls.insert(control) } else { look.hoverControls.remove(control) }
            }
            sizing?.revealControls()
        }
    }
}
