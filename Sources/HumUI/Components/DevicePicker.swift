import HumCore
import SwiftUI

/// The speakers, TVs, and computers the source can play on (DESIGN.md §5.8):
/// Music's AirPlay devices, or the demo's. The current one's glyph and
/// checkmark are in accent, its name in `label`; a move in progress says so in
/// its row. Spotify has no picker (§1.3).
struct DevicePicker: View {
    @Environment(LibraryStore.self) private var library: LibraryStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .humText(.sectionHeader)
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.m)
                .padding(.bottom, Spacing.xs)
                .accessibilityAddTraits(.isHeader)
            if let library {
                content(library)
            }
        }
        .padding(.bottom, Spacing.s)
        .frame(width: Self.width)
        .environment(\.humColorContext, .material)
        .onAppear { library?.loadDevices() }
    }

    /// Room for a device name and the "Connecting to …" line, as the AirPlay
    /// picker's.
    static var width: CGFloat { 260 }

    private var title: String {
        library?.sourceID == .musicApp ? "AirPlay" : "Play On"
    }

    @ViewBuilder
    private func content(_ library: LibraryStore) -> some View {
        let section = library.devices
        if let devices = section.value, !devices.isEmpty {
            VStack(spacing: 0) {
                ForEach(devices) { device in
                    DeviceRow(
                        device: device,
                        isConnecting: library.transferringDeviceID == device.id,
                        canSwitch: library.capabilities.contains(.deviceSwitching)
                    ) {
                        library.transfer(to: device)
                    }
                }
            }
            .padding(.horizontal, Spacing.xs)
        } else if section.isLoadingFirstTime || section.phase == .idle {
            HStack(spacing: Spacing.s) {
                DelayedSpinner()
                Text("Looking for devices…")
                    .humText(.rowSubtitle)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
        } else if let reason = section.unavailable {
            note(reason.message)
        } else if let message = section.failure {
            VStack(alignment: .leading, spacing: Spacing.s) {
                note(message)
                Button("Try Again") { library.loadDevices() }
                    .controlSize(.small)
                    .padding(.horizontal, Spacing.m)
            }
        } else {
            // The player never names the app (DESIGN.md §10).
            note("No other devices are available.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .humText(.rowSubtitle)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
    }
}

/// One device: its glyph, name, and the checkmark when it's playing.
struct DeviceRow: View {
    var device: PlaybackDevice
    var isConnecting: Bool
    var canSwitch: Bool
    var onSelect: @MainActor () -> Void

    @State private var isHovered = false

    /// A row is as tall as a menu item with a second line.
    static var minimumHeight: CGFloat { 36 }
    /// The glyph column, so names line up whatever the glyph's width.
    static var glyphColumn: CGFloat { 24 }
    nonisolated static let restrictedReason = "Can’t be controlled from here"

    var body: some View {
        let enabled = canSwitch && !device.isRestricted && !device.isActive
        Button {
            if enabled { onSelect() }
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: Self.symbol(for: device.kind))
                    .font(.title3)
                    .foregroundStyle(device.isActive ? HumColor.accent : HumColor.secondaryLabel)
                    .frame(width: Self.glyphColumn)
                VStack(alignment: .leading, spacing: 0) {
                    // Accent marks the glyph and checkmark only: as text it
                    // wouldn't keep 4.5:1 on the popover (§3.5.3).
                    Text(device.name)
                        .humText(.rowTitle, color: device.isRestricted ? .tertiaryLabel : nil)
                        .lineLimit(1)
                    if isConnecting {
                        HStack(spacing: Spacing.xs) {
                            Text("Connecting to \(device.name)…")
                                .humText(.rowSubtitle)
                                .lineLimit(1)
                            DelayedSpinner()
                                .scaleEffect(0.7)
                        }
                    } else if device.isRestricted {
                        Text(Self.restrictedReason)
                            .humText(.rowSubtitle)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if device.isActive {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(HumColor.accent)
                }
            }
            .padding(.horizontal, Spacing.s)
            .frame(minHeight: Self.minimumHeight)
            .background {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(HumColor.fillQuaternary)
                    .opacity(isHovered && enabled ? 1 : 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The playing device stays as it is; one Hum can't move to is
        // unavailable, and says why.
        .disabled(!enabled && !device.isActive)
        .onHover { isHovered = $0 }
        .animation(Motion.snappy, value: isHovered)
        .accessibilityLabel(device.name)
        .accessibilityValue(Self.accessibilityValue(device, isConnecting: isConnecting))
        .accessibilityAddTraits(device.isActive ? .isSelected : [])
    }

    nonisolated static func accessibilityValue(_ device: PlaybackDevice, isConnecting: Bool) -> String {
        if device.isActive { return "Playing" }
        if isConnecting { return "Connecting" }
        if device.isRestricted { return restrictedReason }
        return ""
    }

    static func symbol(for kind: PlaybackDevice.Kind) -> String {
        switch kind {
        case .computer: "laptopcomputer"
        case .speaker: "hifispeaker.fill"
        case .tv: "tv.fill"
        case .phone: "iphone"
        case .headphones: "headphones"
        case .other: "hifispeaker.fill"
        }
    }
}

/// Opens the device picker. Shown when the source can list devices.
struct DevicesButton: View {
    @Environment(LibraryStore.self) private var library: LibraryStore?
    @State private var isPresented = false

    var body: some View {
        if let library, library.capabilities.contains(.devices) {
            Button {
                isPresented.toggle()
            } label: {
                Image(systemName: library.sourceID == .musicApp ? "airplayaudio" : HumIcon.devices)
            }
            .buttonStyle(PlayerButtonStyle(.icon, size: .icon))
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                DevicePicker()
            }
            .accessibilityLabel("Devices")
            .help("Devices")
        }
    }
}

/// Devices at the end of Now's volume row at L (§6.1). Shows nothing when the
/// source can't list devices.
struct NowLibraryButtons: View {
    @Environment(LibraryStore.self) private var library: LibraryStore?

    var body: some View {
        if let library, library.capabilities.contains(.devices) {
            DevicesButton()
                // The hit targets overhang the glyphs; keep the glyphs on the edge.
                .padding(.horizontal, -ControlSizing.icon.outset)
                .padding(.vertical, -ControlSizing.icon.outset)
        }
    }
}

#if DEBUG
struct DevicePicker_Previews: PreviewProvider {
    static var previews: some View {
        // A popover as wide at every player size, so it's shown at L only.
        PreviewGallery(cases: [.largeLight, .largeDark], isSquare: false) {
            DevicePicker().libraryPreview()
        }
    }
}
#endif
