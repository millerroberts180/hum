import AppKit
import HumCore
import SwiftUI

/// Player › Position (DESIGN.md §4.5, §8): one wide tile drawing the screen
/// with its menu bar and the nine places the player can be pinned. The current
/// pin holds a small player, drawn to scale; clicking a target pins the player
/// there. With no pin, nothing is marked.
///
/// Keyboard: one stop in the key-view loop. The arrow keys pick the
/// neighbouring place, and Space picks the focused one. VoiceOver reads each
/// place as a button, with "selected" on the pin.
struct PositionTile: View {
    var style: PlayerStyleID
    var pin: PinPosition?
    var playerSize: PlayerSize?
    var pick: (PinPosition) -> Void

    /// The drawn display's shape, and how many points the real one is across.
    var display = PositionTile.mainDisplay()

    @State private var hovered: PinPosition?
    @FocusState private var focused: PinPosition?

    nonisolated static let height = PositionTileLayout.screenHeight + 2 * Spacing.m

    /// The display the player is on, or a 16:10 laptop's when there's none.
    static func mainDisplay() -> CGSize {
        NSScreen.main?.frame.size ?? CGSize(width: 1512, height: 1512 / PositionTileLayout.fallbackAspect)
    }

    var body: some View {
        WideTile(height: Self.height) {
            GeometryReader { proxy in
                let size = proxy.size
                let aspect = display.height > 0 ? display.width / display.height : PositionTileLayout.fallbackAspect
                let screen = PositionTileLayout.screen(in: size, aspect: aspect)
                ZStack(alignment: .topLeading) {
                    DisplayDrawing(size: screen.size)
                        .offset(x: screen.minX, y: screen.minY)
                        .accessibilityHidden(true)
                    if let pin {
                        player(at: pin, in: size, screen: screen, aspect: aspect)
                    }
                    ForEach(PinPosition.allCases) { position in
                        target(position)
                            .position(PositionTileLayout.target(position, in: size, aspect: aspect))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { point in
                    if let position = PositionTileLayout.position(at: point, in: size, aspect: aspect) {
                        choose(position)
                    }
                }
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let point): hovered = PositionTileLayout.position(at: point, in: size, aspect: aspect)
                    case .ended: hovered = nil
                    }
                }
            }
        }
        .onKeyPress(.leftArrow) { step(columns: -1, rows: 0) }
        .onKeyPress(.rightArrow) { step(columns: 1, rows: 0) }
        .onKeyPress(.upArrow) { step(columns: 0, rows: 1) }
        .onKeyPress(.downArrow) { step(columns: 0, rows: -1) }
        .onKeyPress(.space) {
            guard let focused else { return .ignored }
            choose(focused)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Position")
    }

    /// The player as it sits at `position`, to the drawing's scale.
    private func player(at position: PinPosition, in size: CGSize, screen: CGRect, aspect: CGFloat) -> some View {
        let scale = display.width > 0 ? screen.width / display.width : 0.14
        let drawn = StyleMiniature.drawnSize(style, size: playerSize, scale: scale)
        let frame = PositionTileLayout.playerFrame(drawn, at: position, in: size, aspect: aspect)
        return StyleMiniature(style: style, scale: scale, size: playerSize)
            .offset(x: frame.minX, y: frame.minY)
            .animation(Motion.snappy, value: position)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func target(_ position: PinPosition) -> some View {
        let isPinned = position == pin
        let isHovered = position == hovered
        let side = PositionTileLayout.target
        return Circle()
            .fill(isHovered ? AnyShapeStyle(HumColor.secondaryLabel) : AnyShapeStyle(HumColor.fillTertiary))
            .overlay(Circle().strokeBorder(HumColor.secondaryLabel, lineWidth: 1))
            .frame(width: side, height: side)
            // The pinned place is under the player; its target gives way.
            .opacity(isPinned ? 0 : 1)
            .frame(width: side + Spacing.s, height: side + Spacing.s)
            .contentShape(.focusEffect, Circle())
            .focusable(position == tabStop || position == focused, interactions: .activate)
            .focused($focused, equals: position)
            .accessibilityElement()
            .accessibilityLabel(position.title)
            .accessibilityAddTraits(isPinned ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default) { choose(position) }
    }

    /// Where Tab lands: the pin, or the center when there's none.
    private var tabStop: PinPosition {
        pin ?? .center
    }

    private func choose(_ position: PinPosition) {
        pick(position)
    }

    private func step(columns: Int, rows: Int) -> KeyPress.Result {
        guard let current = focused else { return .ignored }
        guard let next = current.neighbor(columns: columns, rows: rows) else { return .handled }
        choose(next)
        focused = next
        return .handled
    }
}

nonisolated extension PinPosition {
    /// The place `columns` to the right and `rows` up from this one, if
    /// there's one there.
    func neighbor(columns: Int, rows: Int) -> PinPosition? {
        PinPosition.allCases.first { $0.column == column + columns && $0.row == row + rows }
    }
}

/// A display: the desktop with a menu bar across its top.
private struct DisplayDrawing: View {
    var size: CGSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PositionTileLayout.screenRadius, style: .continuous)
        TileDesktop()
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.bar)
                    .frame(height: PositionTileLayout.menuBarHeight)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 4) {
                            ForEach(Array([6, 10, 9, 8].enumerated()), id: \.offset) { _, width in
                                MiniBar(width: CGFloat(width), height: 2, color: .tertiaryLabel)
                            }
                        }
                        .padding(.leading, 6)
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(HumColor.separator).frame(height: 0.5)
                    }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(HumColor.separator, lineWidth: 0.5))
    }
}
