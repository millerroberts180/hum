/// Listening-history preferences.
public struct HistorySettings: Codable, Equatable, Sendable {
    /// Record listens. When off, nothing new is written; what's stored stays.
    public var isCollecting = true

    public init() {}

    // A file from before 2026-11-08 may also hold `dataStyleInsight`, the
    // retired Data style's card choice (DESIGN.md §13.19); it's ignored.
    private enum CodingKeys: String, CodingKey {
        case isCollecting
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isCollecting = container.lenient(.isCollecting, default: true)
    }
}
