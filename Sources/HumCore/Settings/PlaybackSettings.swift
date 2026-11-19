/// Source preferences.
public struct PlaybackSettings: Codable, Equatable, Sendable {
    /// A source the user chose, or `nil` to follow whatever is playing.
    public var preferredSource: SourceID?
    /// The source that was active when Hum last ran.
    public var lastActiveSource: SourceID?
    /// Whether the repeat button has said, once, that Hum repeats the song
    /// itself for an app whose own repeat is only on or off (DESIGN.md §5.2).
    public var repeatOneNoteShown = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case preferredSource, lastActiveSource, repeatOneNoteShown
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredSource = container.lenient(.preferredSource, default: nil)
        lastActiveSource = container.lenient(.lastActiveSource, default: nil)
        repeatOneNoteShown = container.lenient(.repeatOneNoteShown, default: false)
    }
}
