/// Light or dark: the two appearances a look is stored for.
///
/// `AppearanceMode` is what the user chose (including System); this is what the
/// screen actually shows, so it has no System case.
public enum LookAppearance: String, Codable, Sendable, CaseIterable, Identifiable {
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// What shows the playback position while the controls are hidden
/// (DESIGN.md §5.2).
public enum ProgressIndicator: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Nothing: the cover alone. Art Only's default.
    case none
    /// A 2-pt hairline along the bottom edge.
    case line
    /// A 2-pt ring drawn just inside the panel edge.
    case ring

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "None"
        case .line: "Line"
        case .ring: "Ring"
        }
    }
}

/// The optional pieces of a style's controls (DESIGN.md §6.1, §7). Play/pause
/// and skip always appear; everything here can be switched off, and each piece
/// still shows only at the size classes that have room for it.
public struct HoverControls: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Title and artist (M and L).
    public static let trackInfo = HoverControls(rawValue: 1 << 0)
    /// The seek bar: a hairline at S, the full bar with times from M.
    public static let seekBar = HoverControls(rawValue: 1 << 1)
    /// Shuffle and repeat, either side of the transport (every size).
    public static let shuffleRepeat = HoverControls(rawValue: 1 << 2)
    /// Save and More at the end of the title row.
    public static let save = HoverControls(rawValue: 1 << 3)
    /// The volume slider and the device button (L).
    public static let volume = HoverControls(rawValue: 1 << 4)
    /// The album, sharing the artist's line (M and L).
    public static let album = HoverControls(rawValue: 1 << 5)

    public static let all: HoverControls = [.trackInfo, .seekBar, .shuffleRepeat, .save, .volume, .album]

    /// Every piece, in the order the Settings list shows them.
    public static let ordered: [HoverControls] = [.trackInfo, .album, .seekBar, .shuffleRepeat, .save, .volume]

    /// The Settings toggle's label, in sentence case (DESIGN.md §3.3).
    public var title: String {
        switch self {
        case .trackInfo: "Title and artist"
        case .seekBar: "Seek bar"
        case .shuffleRepeat: "Shuffle and repeat"
        case .save: "Save and more"
        case .volume: "Volume"
        case .album: "Album"
        default: ""
        }
    }

    /// The size classes that have room for this piece, as shown in Settings.
    public var sizeClasses: String {
        switch self {
        case .trackInfo, .album: "Medium and large players"
        case .volume: "Large players"
        case .seekBar, .shuffleRepeat, .save: "Every size"
        default: ""
        }
    }

    /// The size classes that have room for this piece in `style`'s player.
    /// Wide's and Big Art's cards keep a row for the volume at every size.
    public func sizeClasses(in style: PlayerStyleID) -> String {
        if self == .volume, style.isLandscape || style.isPortrait {
            return "Every size"
        }
        return sizeClasses
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        // Bits from a newer Hum are dropped rather than kept as unnamed options.
        self.init(rawValue: raw & HoverControls.all.rawValue)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// How one style looks in one appearance: everything DESIGN.md §8 calls look,
/// apart from the style choice itself.
///
/// Values are always in range: initializers and setters clamp, so no stored
/// combination can draw an ugly player.
public struct StyleLook: Equatable, Sendable {
    public static let opacityRange: ClosedRange<Double> = 0.7...1
    public static let cornerRadiusScaleRange: ClosedRange<Double> = 0.5...1.5
    public static let defaultCustomAccent = PaletteColor(red: 0.2, green: 0.47, blue: 0.96)

    public var accent: AccentSource
    /// The color used when `accent` is `.custom`.
    public var customAccent: PaletteColor
    /// Multiplies the panel and artwork corner radii.
    public var cornerRadiusScale: Double {
        didSet { cornerRadiusScale = Self.clamp(cornerRadiusScale, to: Self.cornerRadiusScaleRange) }
    }
    /// The player's opacity while the pointer is away. Hovering and focus always
    /// bring it to full.
    public var opacity: Double {
        didSet { opacity = Self.clamp(opacity, to: Self.opacityRange) }
    }
    public var hoverControls: HoverControls
    public var progress: ProgressIndicator
    /// Fill the background with the cover's palette and set text in its colors.
    /// Only Text offers it.
    public var albumTint: Bool

    public init(
        accent: AccentSource = .system,
        customAccent: PaletteColor = StyleLook.defaultCustomAccent,
        cornerRadiusScale: Double = 1,
        opacity: Double = 1,
        hoverControls: HoverControls = .all,
        progress: ProgressIndicator = .none,
        albumTint: Bool = false
    ) {
        self.accent = accent
        self.customAccent = customAccent
        self.cornerRadiusScale = Self.clamp(cornerRadiusScale, to: Self.cornerRadiusScaleRange)
        self.opacity = Self.clamp(opacity, to: Self.opacityRange)
        self.hoverControls = hoverControls
        self.progress = progress
        self.albumTint = albumTint
    }

    /// The look a style ships with. Built-in looks never change at runtime; user
    /// edits are stored as a `LookOverride` on top, so Reset Style can always
    /// return here.
    public static func builtIn(for style: PlayerStyleID, in appearance: LookAppearance) -> StyleLook {
        // Every style's transport has shuffle and repeat (DESIGN.md §13.11).
        StyleLook()
    }

    /// The hover controls the built-in looks had before the 2026-11-07
    /// redesign, when Art Only and Minimal (now Text) shipped without shuffle
    /// and repeat. Overrides saved then hold a whole set, read against this.
    static func legacyBuiltInHoverControls(for style: PlayerStyleID?) -> HoverControls {
        switch style {
        case .artOnly, .text: HoverControls.all.subtracting(.shuffleRepeat)
        default: .all
        }
    }

    /// `override` applied on top of this look, field by field.
    public func applying(_ override: LookOverride) -> StyleLook {
        StyleLook(
            accent: override.accent ?? accent,
            customAccent: override.customAccent ?? customAccent,
            cornerRadiusScale: override.cornerRadiusScale ?? cornerRadiusScale,
            opacity: override.opacity ?? opacity,
            hoverControls: override.hoverControls.map { $0.applied(to: hoverControls) } ?? hoverControls,
            progress: override.progress ?? progress,
            albumTint: override.albumTint ?? albumTint
        )
    }

    /// The fields where `self` differs from `base`, as an override. A field equal
    /// to the built-in value stores nothing, so it keeps following the built-in.
    public func override(from base: StyleLook) -> LookOverride {
        var result = LookOverride()
        if accent != base.accent { result.accent = accent }
        if customAccent != base.customAccent { result.customAccent = customAccent }
        if cornerRadiusScale != base.cornerRadiusScale { result.cornerRadiusScale = cornerRadiusScale }
        if opacity != base.opacity { result.opacity = opacity }
        if hoverControls != base.hoverControls {
            result.hoverControls = HoverControlsChange(from: base.hoverControls, to: hoverControls)
        }
        if progress != base.progress { result.progress = progress }
        if albumTint != base.albumTint { result.albumTint = albumTint }
        return result
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.upperBound }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

/// Which hover controls the user turned on or off, relative to the built-in
/// look, so a piece they never touched keeps following it.
public struct HoverControlsChange: Codable, Equatable, Sendable {
    /// Turned on, though the built-in look leaves them off.
    public var shown: HoverControls
    /// Turned off, though the built-in look shows them.
    public var hidden: HoverControls

    public init(shown: HoverControls = [], hidden: HoverControls = []) {
        self.shown = shown
        self.hidden = hidden.subtracting(shown)
    }

    /// The change that turns `base` into `controls`.
    public init(from base: HoverControls, to controls: HoverControls) {
        self.init(shown: controls.subtracting(base), hidden: base.subtracting(controls))
    }

    public func applied(to base: HoverControls) -> HoverControls {
        base.union(shown).subtracting(hidden)
    }

    public var isEmpty: Bool { shown.isEmpty && hidden.isEmpty }
}

/// The user's edits to one style in one appearance. `nil` means "as built in".
public struct LookOverride: Codable, Equatable, Sendable {
    public var accent: AccentSource?
    public var customAccent: PaletteColor?
    public var cornerRadiusScale: Double?
    public var opacity: Double?
    public var hoverControls: HoverControlsChange?
    public var progress: ProgressIndicator?
    public var albumTint: Bool?

    public init() {}

    public var isEmpty: Bool { self == LookOverride() }

    private enum CodingKeys: String, CodingKey {
        case accent, customAccent, cornerRadiusScale, opacity, hoverChange, progress, albumTint
        /// A whole set, as Hum saved it before the 2026-11-07 redesign.
        case hoverControls
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accent = container.lenient(.accent, default: nil)
        customAccent = container.lenient(.customAccent, default: nil)
        let scale: Double? = container.lenient(.cornerRadiusScale, default: nil)
        cornerRadiusScale = scale.map { StyleLook.clamp($0, to: StyleLook.cornerRadiusScaleRange) }
        let opacity: Double? = container.lenient(.opacity, default: nil)
        self.opacity = opacity.map { StyleLook.clamp($0, to: StyleLook.opacityRange) }
        if let change: HoverControlsChange = container.lenient(.hoverChange, default: nil) {
            hoverControls = change.isEmpty ? nil : change
        } else if let legacy: HoverControls = container.lenient(.hoverControls, default: nil) {
            // Read against the built-in look of its day: a piece that matched
            // it was never chosen, so it follows today's built-in instead.
            let base = StyleLook.legacyBuiltInHoverControls(for: Self.style(at: decoder.codingPath))
            let change = HoverControlsChange(from: base, to: legacy)
            hoverControls = change.isEmpty ? nil : change
        }
        progress = container.lenient(.progress, default: nil)
        albumTint = container.lenient(.albumTint, default: nil)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(accent, forKey: .accent)
        try container.encodeIfPresent(customAccent, forKey: .customAccent)
        try container.encodeIfPresent(cornerRadiusScale, forKey: .cornerRadiusScale)
        try container.encodeIfPresent(opacity, forKey: .opacity)
        try container.encodeIfPresent(hoverControls, forKey: .hoverChange)
        try container.encodeIfPresent(progress, forKey: .progress)
        try container.encodeIfPresent(albumTint, forKey: .albumTint)
    }

    /// The style an override belongs to, from its key in
    /// `AppearanceSettings.overrides` ("artOnly.dark"), when it's decoded there.
    static func style(at codingPath: [any CodingKey]) -> PlayerStyleID? {
        guard let key = codingPath.last?.stringValue, let style = key.split(separator: ".").first else { return nil }
        return PlayerStyleID(rawValue: String(style))
    }
}

extension PlayerStyleID {
    /// Whether the style has a resting progress indicator to choose: Art Only,
    /// whose controls hide at rest. The others show position in their own
    /// controls, or show none (Text).
    public var offersProgressChoice: Bool {
        self == .artOnly
    }

    /// Whether the background can take the album's palette.
    public var offersAlbumTint: Bool {
        self == .text
    }

    /// The optional controls this style has a place for (DESIGN.md §7), which
    /// Settings › Player offers as switches. Every style has shuffle and repeat.
    public var hoverChoices: HoverControls {
        switch self {
        case .artOnly: .all
        // The title and artist give way to the transport and the seek row.
        case .title: [.seekBar, .shuffleRepeat]
        // Only the transport replaces the words.
        case .text: [.shuffleRepeat]
        // The cover, the seek notch and the transport; the title is in the help tag.
        case .strip: [.seekBar, .shuffleRepeat]
        // Beside the cover: the title row with Save and More, the seek bar,
        // the transport and the volume.
        case .wide: [.seekBar, .shuffleRepeat, .save, .volume]
        // Wide's stack under the cover, with the album on the artist's line.
        case .bigArt: [.album, .seekBar, .shuffleRepeat, .save, .volume]
        // The popover's title, seek bar and transport.
        case .menuBar: [.shuffleRepeat]
        }
    }

    /// One line describing the style, for its tile in Settings.
    public var summary: String {
        switch self {
        case .artOnly: "The cover, edge to edge. Controls appear on hover."
        case .strip: "A slim bar with the cover, a seek bar and the controls."
        case .text: "The title and artist in a capsule. Controls appear on hover."
        case .title: "The cover with the title and artist. Controls appear on hover."
        case .wide: "The cover with the title and every control beside it."
        case .bigArt: "A large cover with every control beneath it."
        case .menuBar: "The song and its controls in the menu bar."
        }
    }
}
