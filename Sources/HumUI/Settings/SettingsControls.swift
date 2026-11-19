import SwiftUI

/// System Settings' own Appearance-tile metrics, which every choice tile matches
/// (DESIGN.md §8). They are the named exception to the 4-pt grid (§3.1): the
/// values are the system's, not Hum's tokens.
nonisolated enum SystemTileMetrics {
    /// Between neighbouring tiles.
    static let gap: CGFloat = 14
    /// The tile's own corners.
    static let cornerRadius: CGFloat = 10
    /// The selection ring, drawn just outside the tile and touching its edge.
    static let ringWidth: CGFloat = 3
    /// The ring's corners, concentric with the tile's.
    static let ringCornerRadius: CGFloat = cornerRadius + ringWidth
    /// The tile's title: semibold in `label` when selected, regular in
    /// `secondaryLabel` otherwise, as System Settings sets it.
    static let titleFont: Font = .subheadline

    static func titleWeight(isSelected: Bool) -> Font.Weight {
        isSelected ? .semibold : .regular
    }

    static func titleColor(isSelected: Bool) -> HumColor {
        isSelected ? .label : .secondaryLabel
    }

    /// How much a tile that can't be picked (an app that isn't installed)
    /// shows of its drawing.
    static let unavailableOpacity: Double = 0.4
}

/// Equal tiles, each a small drawing of what its option does with its title
/// under it, for a choice people should see rather than read (DESIGN.md §8):
/// the style, the size, the accent, and so on.
///
/// Picking a tile calls `pick`, which applies the choice and demonstrates it.
/// The chosen tile wears a 3-pt accent ring; with no `selection` (a saved value
/// that matches no tile) none does.
///
/// Keyboard: the row is one stop in the key-view loop, as a radio group is,
/// when the system's Keyboard Navigation setting is on. ← and → pick the
/// neighbouring tile, and Space picks the focused one. VoiceOver reads each
/// tile by its title, with "selected" on the chosen one; the drawings are hidden.
struct ChoiceTiles<Option: Hashable, Art: View>: View {
    var options: [Option]
    var selection: Option?
    /// Tiles per row; `0` puts every option in one row.
    var columns: Int
    var artHeight: CGFloat
    var title: (Option) -> String
    /// A second, quieter line under the title, such as "Not installed".
    var caption: (Option) -> String?
    /// Whether the option can be picked. One that can't is dimmed.
    var isAvailable: (Option) -> Bool
    var pick: (Option) -> Void
    var art: (Option) -> Art

    @FocusState private var focused: Option?

    init(
        _ options: [Option],
        selection: Option?,
        columns: Int = 0,
        artHeight: CGFloat = 52,
        title: @escaping (Option) -> String,
        caption: @escaping (Option) -> String? = { _ in nil },
        isAvailable: @escaping (Option) -> Bool = { _ in true },
        pick: @escaping (Option) -> Void,
        @ViewBuilder art: @escaping (Option) -> Art
    ) {
        self.options = options
        self.selection = selection
        self.columns = columns
        self.artHeight = artHeight
        self.title = title
        self.caption = caption
        self.isAvailable = isAvailable
        self.pick = pick
        self.art = art
    }

    /// Tiles bound to a setting: picking one stores it, then `onPick`
    /// demonstrates it.
    init(
        _ options: [Option],
        selection: Binding<Option>,
        columns: Int = 0,
        artHeight: CGFloat = 52,
        title: @escaping (Option) -> String,
        caption: @escaping (Option) -> String? = { _ in nil },
        isAvailable: @escaping (Option) -> Bool = { _ in true },
        onPick: @escaping (Option) -> Void = { _ in },
        @ViewBuilder art: @escaping (Option) -> Art
    ) {
        self.init(
            options,
            selection: selection.wrappedValue,
            columns: columns,
            artHeight: artHeight,
            title: title,
            caption: caption,
            isAvailable: isAvailable,
            pick: { option in
                if selection.wrappedValue != option { selection.wrappedValue = option }
                onPick(option)
            },
            art: art
        )
    }

    var body: some View {
        let count = columns > 0 ? columns : max(options.count, 1)
        let grid = Array(repeating: GridItem(.flexible(), spacing: SystemTileMetrics.gap, alignment: .top), count: count)
        LazyVGrid(columns: grid, spacing: SystemTileMetrics.gap) {
            ForEach(options, id: \.self) { option in
                ChoiceTile(
                    title: title(option),
                    caption: caption(option),
                    isSelected: option == selection,
                    isAvailable: isAvailable(option),
                    artHeight: artHeight,
                    choose: { choose(option) }
                ) {
                    art(option)
                }
                .focusable(option == tabStop || option == focused, interactions: .activate)
                .focused($focused, equals: option)
            }
        }
        // Room for the ring, which sits outside the tiles.
        .padding(.horizontal, SystemTileMetrics.ringWidth)
        .padding(.vertical, Spacing.xs)
        .onKeyPress(.leftArrow) { step(by: -1) }
        .onKeyPress(.rightArrow) { step(by: 1) }
        .onKeyPress(.space) {
            guard let focused else { return .ignored }
            choose(focused)
            return .handled
        }
    }

    /// The tile Tab lands on: the chosen one, or the first that can be picked.
    private var tabStop: Option? {
        if let selection, options.contains(selection) { return selection }
        return options.first(where: isAvailable)
    }

    private func choose(_ option: Option) {
        guard isAvailable(option) else { return }
        pick(option)
    }

    /// Pick the next tile that can be picked, the way a radio group moves.
    private func step(by offset: Int) -> KeyPress.Result {
        guard let current = focused, let start = options.firstIndex(of: current) else { return .ignored }
        var index = start + offset
        while options.indices.contains(index) {
            let option = options[index]
            if isAvailable(option) {
                choose(option)
                focused = option
                return .handled
            }
            index += offset
        }
        return .handled
    }
}

private struct ChoiceTile<Art: View>: View {
    var title: String
    var caption: String?
    var isSelected: Bool
    var isAvailable: Bool
    var artHeight: CGFloat
    var choose: () -> Void
    @ViewBuilder var art: () -> Art

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SystemTileMetrics.cornerRadius, style: .continuous)
        VStack(spacing: Spacing.s) {
            art()
                // The column's width, never the art's: art wider than its
                // tile is clipped rather than pushing into the next one.
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(height: artHeight)
                .background(shape.fill(HumColor.fillQuaternary))
                .clipShape(shape)
                .opacity(isAvailable ? 1 : SystemTileMetrics.unavailableOpacity)
                .overlay {
                    // Concentric with the tile, touching its edge. The
                    // system accent, as System Settings marks its own tiles:
                    // Hum's accent belongs to the player.
                    RoundedRectangle(cornerRadius: SystemTileMetrics.ringCornerRadius, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: SystemTileMetrics.ringWidth)
                        .padding(-SystemTileMetrics.ringWidth)
                        .opacity(isSelected ? 1 : 0)
                }
            VStack(spacing: 0) {
                Text(title)
                    .font(SystemTileMetrics.titleFont)
                    .fontWeight(SystemTileMetrics.titleWeight(isSelected: isSelected))
                    .foregroundStyle(SystemTileMetrics.titleColor(isSelected: isSelected))
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(HumColor.tertiaryLabel)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .contentShape(.interaction, Rectangle())
        .contentShape(.focusEffect, shape)
        .onTapGesture(perform: choose)
        .animation(reduceMotion ? nil : Motion.snappy, value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(caption ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, choose)
        .disabled(!isAvailable)
    }
}

/// A row that is one wide drawing rather than a set of tiles, such as the
/// player's position on the screen: the tile's shape and fill, no title.
struct WideTile<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SystemTileMetrics.cornerRadius, style: .continuous)
        content()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(shape.fill(HumColor.fillQuaternary))
            .clipShape(shape)
    }
}

/// A Settings row whose control is a set of tiles: the label above, then the
/// tiles across the row's whole width.
struct TileRow<Tiles: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var tiles: () -> Tiles

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            DetailLabel(title: title, detail: detail)
            tiles()
        }
        .padding(.vertical, Spacing.xxs)
    }
}

/// Shortcuts written as plain text ("⌥⌘K"), the way menus show them, for the
/// shortcut reference. Several are alternatives: "⌘K, ⌘F".
struct ShortcutKeys: View {
    var keys: [String]

    init(keys: [String]) {
        self.keys = keys
    }

    var body: some View {
        Text(keys.joined(separator: ", "))
            .foregroundStyle(HumColor.secondaryLabel)
            .accessibilityLabel(keys.joined(separator: " or "))
    }
}
