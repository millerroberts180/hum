/// Everything Hum persists, in one versioned document.
///
/// Every field has a default and decodes leniently, so adding a field never needs a
/// migration. Bump `currentSchemaVersion` only for a change in meaning, and handle
/// the old version in `init(from:)`. A section that's gone, such as `library`
/// from Play's time, is ignored when an old file still has it.
public struct HumSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion = HumSettings.currentSchemaVersion
    public var behavior = BehaviorSettings()
    public var appearance = AppearanceSettings()
    public var shortcuts = ShortcutSettings()
    public var playback = PlaybackSettings()
    public var history = HistorySettings()
    public var window = WindowMemory()

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, behavior, appearance, shortcuts, playback, history, window
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = container.lenient(.schemaVersion, default: HumSettings.currentSchemaVersion)
        behavior = container.lenient(.behavior, default: BehaviorSettings())
        appearance = container.lenient(.appearance, default: AppearanceSettings())
        shortcuts = container.lenient(.shortcuts, default: ShortcutSettings())
        playback = container.lenient(.playback, default: PlaybackSettings())
        history = container.lenient(.history, default: HistorySettings())
        window = container.lenient(.window, default: WindowMemory())
        schemaVersion = HumSettings.currentSchemaVersion
    }
}
