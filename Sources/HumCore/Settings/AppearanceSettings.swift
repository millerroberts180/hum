/// How the player looks.
///
/// The style is one choice for both appearances. Everything else about the look
/// is kept per style and per appearance (DESIGN.md §8): built-in values from
/// `StyleLook.builtIn(for:in:)`, with the user's edits stored as overrides on top.
public struct AppearanceSettings: Codable, Equatable, Sendable {
    public var style: PlayerStyleID = .artOnly {
        didSet {
            if style == .menuBar, oldValue.hasWindow { lastWindowStyle = oldValue }
        }
    }
    /// The window style Pop Out Player returns to from Menu Bar (DESIGN.md §7.1).
    /// Choosing Menu Bar records the style it came from.
    public var lastWindowStyle: PlayerStyleID = .artOnly
    public var mode: AppearanceMode = .system
    /// Liquid Glass or Frosted, on macOS 26 (DESIGN.md §3.6.1). Read
    /// `material.effective` for what to draw: macOS 15 always gets Frosted.
    public var material: GlassMaterial = .liquidGlass
    /// Keep the controls visible instead of revealing them on hover or focus.
    public var alwaysShowControls = false
    /// User edits, keyed by `LookKey`. Only fields that differ from the built-in
    /// look are stored.
    public private(set) var overrides: [String: LookOverride] = [:]

    public init() {}

    /// The look `style` has in `appearance`, with the user's edits applied.
    public func look(for style: PlayerStyleID, in appearance: LookAppearance) -> StyleLook {
        let base = StyleLook.builtIn(for: style, in: appearance)
        guard let override = overrides[Self.key(style, appearance)] else { return base }
        return base.applying(override)
    }

    /// The current style's look in `appearance`.
    public func look(in appearance: LookAppearance) -> StyleLook {
        look(for: style, in: appearance)
    }

    /// Store `look` for `style` in `appearance`. Fields equal to the built-in look
    /// aren't stored, so they keep following it.
    public mutating func setLook(_ look: StyleLook, for style: PlayerStyleID, in appearance: LookAppearance) {
        let override = look.override(from: StyleLook.builtIn(for: style, in: appearance))
        let key = Self.key(style, appearance)
        overrides[key] = override.isEmpty ? nil : override
    }

    /// Change one style's look in one appearance in place.
    public mutating func updateLook(
        for style: PlayerStyleID,
        in appearance: LookAppearance,
        _ change: (inout StyleLook) -> Void
    ) {
        var look = look(for: style, in: appearance)
        change(&look)
        setLook(look, for: style, in: appearance)
    }

    /// Change one style's look in both appearances, as settings that don't
    /// depend on light or dark (the hover controls) do.
    public mutating func updateLookInBothAppearances(for style: PlayerStyleID, _ change: (inout StyleLook) -> Void) {
        for appearance in LookAppearance.allCases {
            updateLook(for: style, in: appearance, change)
        }
    }

    /// Whether `style` has any edits, in either appearance.
    public func isCustomized(_ style: PlayerStyleID) -> Bool {
        LookAppearance.allCases.contains { overrides[Self.key(style, $0)] != nil }
    }

    /// Drop every edit to `style`, in both appearances.
    public mutating func resetLook(for style: PlayerStyleID) {
        for appearance in LookAppearance.allCases {
            overrides[Self.key(style, appearance)] = nil
        }
    }

    /// The current style's accent source. Reading gives the light look's; setting
    /// writes both appearances. Settings edits each appearance on its own through
    /// `updateLook(for:in:_:)`.
    public var accent: AccentSource {
        get { look(in: .light).accent }
        set { updateLookInBothAppearances(for: style) { $0.accent = newValue } }
    }

    /// The current style's custom accent color, read and written like `accent`.
    public var customAccent: PaletteColor {
        get { look(in: .light).customAccent }
        set { updateLookInBothAppearances(for: style) { $0.customAccent = newValue } }
    }

    static func key(_ style: PlayerStyleID, _ appearance: LookAppearance) -> String {
        "\(style.rawValue).\(appearance.rawValue)"
    }

    /// The style an overrides key ("artOnly.dark") belongs to, if Hum has it.
    static func style(ofKey key: String) -> PlayerStyleID? {
        key.split(separator: ".").first.flatMap { PlayerStyleID(rawValue: String($0)) }
    }

    private enum CodingKeys: String, CodingKey {
        case style, lastWindowStyle, mode, material, alwaysShowControls, overrides
        // Written by Hum before looks were kept per style; read once and folded
        // into the overrides.
        case accent, customAccent
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppearanceSettings()
        style = container.lenient(.style, default: defaults.style)
        let lastWindowStyle: PlayerStyleID = container.lenient(.lastWindowStyle, default: defaults.lastWindowStyle)
        self.lastWindowStyle = lastWindowStyle.hasWindow ? lastWindowStyle : defaults.lastWindowStyle
        mode = container.lenient(.mode, default: defaults.mode)
        material = container.lenient(.material, default: defaults.material)
        alwaysShowControls = container.lenient(.alwaysShowControls, default: defaults.alwaysShowControls)
        let entries: [String: LenientValue<LookOverride>] = container.lenient(.overrides, default: [:])
        // A look saved for a style Hum no longer has (Glass, Data and Session,
        // retired 2026-11-08, DESIGN.md §13.19) is dropped.
        overrides = entries.filter { Self.style(ofKey: $0.key) != nil }.compactMapValues { entry in
            guard let override = entry.value, !override.isEmpty else { return nil }
            return override
        }
        if !container.contains(.overrides) {
            migrateFlatAccent(
                accent: container.lenient(.accent, default: nil),
                customAccent: container.lenient(.customAccent, default: nil)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(style, forKey: .style)
        try container.encode(lastWindowStyle, forKey: .lastWindowStyle)
        try container.encode(mode, forKey: .mode)
        try container.encode(material, forKey: .material)
        try container.encode(alwaysShowControls, forKey: .alwaysShowControls)
        try container.encode(overrides, forKey: .overrides)
    }

    /// Before looks were per style, one accent applied everywhere. Carry it to
    /// every style in both appearances, so nobody's color changes on update.
    private mutating func migrateFlatAccent(accent: AccentSource?, customAccent: PaletteColor?) {
        guard accent != nil || customAccent != nil else { return }
        for style in PlayerStyleID.allCases {
            for appearance in LookAppearance.allCases {
                updateLook(for: style, in: appearance) { look in
                    if let accent { look.accent = accent }
                    if let customAccent { look.customAccent = customAccent }
                }
            }
        }
    }
}

/// Decodes a value or nothing, so one malformed entry in a dictionary drops only
/// itself.
struct LenientValue<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: any Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Value.self)
    }
}
