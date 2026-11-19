import HumCore
import SwiftUI

/// "Playing on Kitchen" as the last line of the track header at M and L while
/// the music plays on another device (DESIGN.md §5.3), and "Connecting to
/// Kitchen…" while it moves there (§4.6). Clicking it opens the device picker.
///
/// Reads `LibraryStore` from the environment. It draws nothing and takes no
/// space while this Mac plays, before the devices are known, for Music, or
/// without a library, so it can sit in a layout unconditionally. The demo
/// shows it with `--demo-device kitchen`, or after picking Kitchen.
struct DeviceStatusRow: View {
    @Environment(LibraryStore.self) private var library: LibraryStore?

    init() {}

    var body: some View {
        if let status = library?.deviceStatus {
            DeviceStatusButton(status: status)
        }
    }
}

/// The row itself, for a known status.
struct DeviceStatusButton: View {
    var status: DeviceStatus

    @State private var isPresented = false
    @State private var isHovered = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: HumIcon.devices)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HumColor.accent)
                    .accessibilityHidden(true)
                Text(status.title)
                    .humText(.caption, color: isHovered ? .label : nil)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if status.phase == .connecting {
                    DelayedSpinner()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Motion.snappy, value: isHovered)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            DevicePicker()
        }
        .accessibilityLabel(status.title)
        .accessibilityHint("Shows the devices music can play on")
        .help("Choose where music plays")
    }
}
