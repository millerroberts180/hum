import Foundation

/// Where the music is when it isn't this Mac, for `DeviceRow` under the
/// transport (DESIGN.md §5.3, §4.6): a speaker, TV, or phone the music
/// plays on, or the device playback is moving to.
public struct DeviceStatus: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        /// The device is playing.
        case playing
        /// Playback is moving there.
        case connecting
    }

    public var device: PlaybackDevice
    public var phase: Phase

    public init(device: PlaybackDevice, phase: Phase) {
        self.device = device
        self.phase = phase
    }

    /// "Playing on Kitchen", or "Connecting to Kitchen…".
    public var title: String {
        switch phase {
        case .playing: "Playing on \(device.name)"
        case .connecting: "Connecting to \(device.name)…"
        }
    }

    /// What `devices` say: a move under way first, then another device that's
    /// playing. `nil` while this Mac plays, or when no device is playing.
    public static func resolve(devices: [PlaybackDevice], connectingTo id: String?) -> DeviceStatus? {
        if let id, let target = devices.first(where: { $0.id == id }) {
            return target.isThisMac ? nil : DeviceStatus(device: target, phase: .connecting)
        }
        guard let active = devices.first(where: \.isActive), !active.isThisMac else { return nil }
        return DeviceStatus(device: active, phase: .playing)
    }
}
