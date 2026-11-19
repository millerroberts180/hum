/// Which material the player uses on macOS 26 (DESIGN.md §3.6.1). On macOS 15
/// there is no choice: the setting is kept but every material is Frosted.
public enum GlassMaterial: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The system's Liquid Glass, through the public `glassEffect` API.
    case liquidGlass
    /// The macOS 15 materials, on any version.
    case frosted

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .frosted: "Frosted"
        }
    }

    /// Whether this Mac can show Liquid Glass at all.
    public static var isLiquidGlassAvailable: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    /// The material actually drawn: Frosted wherever Liquid Glass isn't available.
    public var effective: GlassMaterial {
        Self.isLiquidGlassAvailable ? self : .frosted
    }
}
