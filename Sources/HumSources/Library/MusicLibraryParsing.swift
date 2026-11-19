import Foundation
import HumCore

/// Turns what `MusicLibraryScripts` and Music's state answer with into Hum's
/// models. Pure, so every shape Music answers with can be tested.
enum MusicLibraryParsing {
    /// The context for Music's current playlist: the whole library, a radio
    /// station, or a playlist.
    static func context(name: String?, identifier: String?, className: String?) -> PlaybackContext? {
        guard let name, !name.isEmpty else { return nil }
        let kind: PlaybackContext.Kind = switch className?.lowercased() ?? "" {
        case "library playlist": .library
        case "radio tuner playlist": .radio
        default: .playlist
        }
        let id = identifier.flatMap { $0.isEmpty ? nil : $0.uppercased() }
        return PlaybackContext(kind: kind, name: name, identifier: kind == .playlist ? id : nil)
    }

    // MARK: Devices

    /// AirPlay devices from `{persistent IDs, names, kinds, selected, available}`.
    static func devices(_ columns: ScriptValue) -> [PlaybackDevice] {
        guard let fields = columns.list, fields.count >= 5 else { return [] }
        let lists = fields.map { $0.list ?? [$0] }
        return lists[0].indices.compactMap { index in
            func value(_ column: Int) -> ScriptValue? {
                lists[column].indices.contains(index) ? lists[column][index].nonNull : nil
            }
            let name = value(1)?.string ?? ""
            guard !name.isEmpty else { return nil }
            return PlaybackDevice(
                id: value(0)?.string ?? name,
                name: name,
                kind: deviceKind(value(2)?.string ?? ""),
                isActive: value(3)?.bool ?? false,
                isRestricted: !(value(4)?.bool ?? true)
            )
        }
    }

    static func deviceKind(_ kind: String) -> PlaybackDevice.Kind {
        switch kind.lowercased() {
        case "computer": .computer
        case "apple tv": .tv
        case "bluetooth device": .headphones
        case "homepod", "airport express", "airplay device": .speaker
        default: .other
        }
    }
}
