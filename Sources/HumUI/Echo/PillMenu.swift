import SwiftUI

/// DESIGN.md §5.9, family 10.
///
/// A menu drawn as family 9's tile in a capsule: the current choice, then a
/// chevron. For the Listening History window's filters (Any Artist, Any
/// Album, Any Playlist, Any Time) and Top's period. The system menu opens
/// from it and checks the current choice.
///
/// A filter gives its "Any" choice as `any`, listed first with a divider
/// after it; any other choice shows in the accent with the edge lit, so a
/// set filter reads as set at a glance.
struct PillMenu<Value: Hashable>: View {
    struct Option {
        var value: Value
        var title: String
    }

    /// What the menu chooses, for VoiceOver ("Artist").
    var title: String
    @Binding var selection: Value
    var any: Option?
    var options: [Option]

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                if let any {
                    Text(any.title).tag(any.value)
                    Divider()
                }
                ForEach(options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(choice)
                Image(systemName: "chevron.down")
                    .font(.system(size: PillMenuMetrics.chevronSize, weight: .semibold))
                    .foregroundStyle(HumColor.secondaryLabel)
                    .accessibilityHidden(true)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(PillMenuButtonStyle(isActive: isActive))
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(choice)
    }

    /// The chosen option's title, or the first option's when the choice
    /// isn't offered (a filter for an artist whose listens were removed).
    var choice: String {
        if let any, any.value == selection { return any.title }
        return options.first { $0.value == selection }?.title ?? any?.title ?? options.first?.title ?? ""
    }

    /// Whether a filter is set: anything but its "Any" choice.
    var isActive: Bool {
        guard let any else { return false }
        return selection != any.value
    }
}

nonisolated enum PillMenuMetrics {
    static let chevronSize: CGFloat = 9
}

/// The capsule itself: family 9's states (`ActionButtonLook`), and a set
/// filter's accent choice and edge.
struct PillMenuButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        PillMenuBody(configuration: configuration, isActive: isActive)
    }

    /// The look for a state. A set filter's edge is the accent at 45%, as
    /// family 9's hover; pressing shows family 9's press over it.
    nonisolated static func look(
        isPressed: Bool,
        isHovered: Bool,
        isActive: Bool,
        isEnabled: Bool,
        reduceMotion: Bool = false
    ) -> ActionButtonLook {
        var look = ActionButtonLook.resolve(
            isPressed: isPressed,
            isHovered: isHovered,
            isSelected: false,
            isEnabled: isEnabled,
            reduceMotion: reduceMotion
        )
        if isActive, !(isPressed && isEnabled) {
            look.edge = .accent
            look.edgeOpacity = 0.45
        }
        return look
    }

    /// The choice's color: `label`, the accent for a set filter, and
    /// `tertiaryLabel` while disabled.
    nonisolated static func titleColor(isActive: Bool, isEnabled: Bool) -> Color {
        guard isEnabled, isActive else {
            return ActionButtonLook.titleColor(isEnabled: isEnabled, isDestructive: false)
        }
        return .accentColor
    }
}

private struct PillMenuBody: View {
    let configuration: ButtonStyleConfiguration
    let isActive: Bool

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isPressed = configuration.isPressed
        let look = PillMenuButtonStyle.look(
            isPressed: isPressed,
            isHovered: isHovered,
            isActive: isActive,
            isEnabled: isEnabled,
            reduceMotion: reduceMotion
        )
        let shape = Capsule(style: .continuous)
        configuration.label
            .font(.system(size: ActionButtonMetrics.titleSize, weight: look.titleWeight))
            .foregroundStyle(PillMenuButtonStyle.titleColor(isActive: isActive, isEnabled: isEnabled))
            .lineLimit(1)
            .padding(.horizontal, ActionButtonMetrics.horizontalPadding)
            .padding(.vertical, ActionButtonMetrics.verticalPadding)
            .frame(minHeight: ActionButtonMetrics.minHeight)
            .background(shape.fill(ActionButtonLook.color(look.fill).opacity(look.fillOpacity)))
            .overlay(shape.strokeBorder(ActionButtonLook.color(look.edge).opacity(look.edgeOpacity), lineWidth: look.edgeWidth))
            .shadow(color: Color.accentColor.opacity(look.glowOpacity), radius: ActionButtonMetrics.glowRadius)
            .scaleEffect(look.scale)
            .opacity(look.opacity)
            .contentShape(.interaction, shape)
            .contentShape(.focusEffect, shape)
            // Down with `press`, back with `snappy`, as family 9 (§5.9).
            .animation(isPressed ? Motion.press : Motion.snappy, value: isPressed)
            .animation(Motion.easeOut(ActionButtonMetrics.hoverDuration), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
