import AppKit
import HumCore
import SwiftUI

/// The player's style, color, and shape (DESIGN.md §8).
///
/// A live preview sits at the top. Its Light and Dark buttons also pick which
/// look the settings below change: each style keeps one for each appearance.
/// Every choice is a row of tiles, and every change shows in the preview and
/// the player at once. The sections are Preview, Style, Look, and Details
/// (§8).
struct AppearanceSettingsPane: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerSizing.self) private var sizing: PlayerSizing?
    @Environment(\.colorScheme) private var colorScheme
    @State private var chosenAppearance: LookAppearance?
    @State private var showsControls = false

    /// Accent tiles in the order DESIGN.md §8 gives them.
    static let accentOrder: [AccentSource] = [.album, .system, .custom]
    /// Tiles per row for the small choices, so every row's tiles are one width.
    static let columns = 3
    static let tileArtHeight: CGFloat = 56

    /// The appearance in the preview: what the player shows now, until the user
    /// picks the other one.
    private var appearance: LookAppearance {
        if let chosenAppearance { return chosenAppearance }
        switch settings.appearance.mode {
        case .light: return .light
        case .dark: return .dark
        case .system: return LookAppearance(colorScheme)
        }
    }

    private var style: PlayerStyleID { settings.appearance.style }

    var body: some View {
        @Bindable var settings = settings
        let look = settings.appearance.look(for: style, in: appearance)
        let rows = AppearanceRow.rows(for: style)
        Form {
            Section {
                previewPanel
            } header: {
                Text("Preview")
            } footer: {
                FooterNote("Each style keeps a light look and a dark look. Changes below apply to the \(appearance.title.lowercased()) one.")
            }

            Section {
                TileRow(title: style.title, detail: style.summary) {
                    // Seven styles: four in the first row, three in the second (§8).
                    ChoiceTiles(
                        PlayerStyleID.allCases,
                        selection: $settings.appearance.style,
                        columns: 4,
                        artHeight: StyleTileArt.artHeight,
                        title: \.title
                    ) { option in
                        StyleTileArt(style: option)
                    }
                }
                LabeledContent {
                    Button {
                        settings.appearance.resetLook(for: style)
                    } label: {
                        ActionLabel("Reset Style", symbol: "arrow.counterclockwise")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(!settings.appearance.isCustomized(style))
                } label: {
                    DetailLabel(
                        title: "Built-in \(style.title) look",
                        detail: settings.appearance.isCustomized(style)
                            ? "Puts back the original look, light and dark."
                            : "This style has its original look."
                    )
                }
            } header: {
                Text("Style")
            }

            Section {
                TileRow(title: "Appearance", detail: nil) {
                    ChoiceTiles(
                        AppearanceMode.allCases,
                        selection: $settings.appearance.mode,
                        columns: Self.columns,
                        artHeight: Self.tileArtHeight,
                        title: \.title,
                        // The preview follows the player's new appearance.
                        onPick: { _ in chosenAppearance = nil }
                    ) { mode in
                        AppearanceModeTileArt(mode: mode)
                    }
                }
                if rows.contains(.material) {
                    TileRow(title: "Material", detail: "For every style. Frosted is the look from before Liquid Glass.") {
                        ChoiceTiles(
                            GlassMaterial.allCases,
                            selection: $settings.appearance.material,
                            columns: Self.columns,
                            artHeight: Self.tileArtHeight,
                            title: \.title
                        ) { material in
                            MaterialTileArt(material: material)
                        }
                    }
                }
                TileRow(title: "Accent", detail: accentDetail(look.accent)) {
                    ChoiceTiles(
                        Self.accentOrder,
                        selection: lookBinding(\.accent),
                        columns: Self.columns,
                        artHeight: Self.tileArtHeight,
                        title: \.title
                    ) { source in
                        AccentTileArt(source: source, custom: look.customAccent)
                    }
                }
                if look.accent == .custom {
                    ColorPicker("Custom color", selection: customAccent, supportsOpacity: false)
                }
                if rows.contains(.albumTint) {
                    TileRow(title: "Album tint", detail: "Fill the background with the cover’s own color, and set the text in its colors.") {
                        ChoiceTiles(
                            [false, true],
                            selection: lookBinding(\.albumTint),
                            columns: Self.columns,
                            artHeight: Self.tileArtHeight,
                            title: { $0 ? "Album" : "Neutral" }
                        ) { isTinted in
                            AlbumTintTileArt(isTinted: isTinted)
                        }
                    }
                }
            } header: {
                Text("Look")
            }

            if rows.contains(.corners) || rows.contains(.opacity) || rows.contains(.progress) {
                Section {
                    if rows.contains(.corners) {
                        TileRow(title: "Corners", detail: nil) {
                            ChoiceTiles(
                                CornerChoice.allCases,
                                selection: CornerChoice.nearest(to: look.cornerRadiusScale),
                                columns: Self.columns,
                                artHeight: Self.tileArtHeight,
                                title: \.title,
                                pick: { lookBinding(\.cornerRadiusScale).wrappedValue = $0.scale }
                            ) { choice in
                                CornersTileArt(choice: choice, style: style, size: sizing?.size)
                            }
                        }
                    }
                    if rows.contains(.opacity) {
                        TileRow(title: "Opacity at rest", detail: "The player comes to full when you point at it.") {
                            ChoiceTiles(
                                OpacityChoice.allCases,
                                selection: OpacityChoice.nearest(to: look.opacity),
                                columns: Self.columns,
                                artHeight: Self.tileArtHeight,
                                title: \.title,
                                pick: { lookBinding(\.opacity).wrappedValue = $0.opacity }
                            ) { choice in
                                OpacityTileArt(choice: choice, style: style, cornerRadiusScale: look.cornerRadiusScale)
                            }
                        }
                    }
                    if rows.contains(.progress) {
                        TileRow(title: "Progress", detail: "Shows the position while the controls are hidden.") {
                            ChoiceTiles(
                                ProgressIndicator.allCases,
                                selection: lookBinding(\.progress),
                                columns: Self.columns,
                                artHeight: Self.tileArtHeight,
                                title: \.title
                            ) { kind in
                                ProgressTileArt(kind: kind)
                            }
                        }
                    }
                } header: {
                    Text("Details")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var previewPanel: some View {
        VStack(spacing: Spacing.m) {
            Group {
                if style.hasWindow {
                    PlayerPreview(style: style, appearance: appearance, showsControls: showsControls)
                } else {
                    MenuBarPreview(appearance: appearance)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            // A picture, so it lines up as an image does. A scaled-down
            // preview reports its text's baselines at full scale, which the
            // form row would line up with, pushing the panel down.
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            .alignmentGuide(.lastTextBaseline) { $0[.bottom] }
            .padding(.vertical, Spacing.m)
            .background {
                PreviewBackdrop(appearance: appearance)
                    .clipShape(RoundedRectangle(cornerRadius: SystemTileMetrics.cornerRadius, style: .continuous))
            }
            HStack {
                // Two action buttons, the one shown selected (§5.9 family 9).
                // They change only the preview, and which look is edited.
                HStack(spacing: Spacing.s) {
                    ForEach(LookAppearance.allCases) { option in
                        let isShown = option == appearance
                        Button {
                            chosenAppearance = option
                        } label: {
                            ActionLabel(option.title)
                        }
                        .buttonStyle(ActionButtonStyle(isSelected: isShown))
                        .accessibilityAddTraits(isShown ? .isSelected : [])
                        .help("Preview the \(option.title.lowercased()) look")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Preview appearance")
                Spacer()
                // The title sits against its switch rather than across the row.
                Group {
                    Text("Show controls")
                        .foregroundStyle(style.hasWindow ? HumColor.label : HumColor.tertiaryLabel)
                        .accessibilityHidden(true)
                    Toggle("Show controls", isOn: $showsControls)
                        .labelsHidden()
                        .help("Show the player as it looks when you point at it")
                }
                // Menu Bar's popover always shows its controls.
                .disabled(!style.hasWindow)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    /// One field of the look being edited: this style, in the preview's appearance.
    private func lookBinding<Value>(_ keyPath: WritableKeyPath<StyleLook, Value>) -> Binding<Value> {
        let style = style
        let appearance = appearance
        return Binding {
            settings.appearance.look(for: style, in: appearance)[keyPath: keyPath]
        } set: { value in
            settings.appearance.updateLook(for: style, in: appearance) { $0[keyPath: keyPath] = value }
        }
    }

    /// The custom accent as a SwiftUI color; picked colors are stored in sRGB.
    private var customAccent: Binding<Color> {
        let accent = lookBinding(\.customAccent)
        return Binding {
            Color(accent.wrappedValue)
        } set: { color in
            accent.wrappedValue = PaletteColor(NSColor(color))
        }
    }

    private func accentDetail(_ source: AccentSource) -> String {
        switch source {
        case .system: "The accent color from System Settings."
        case .album: "A color from the cover, or the system’s when it has none."
        case .custom: "A color you choose."
        }
    }
}
