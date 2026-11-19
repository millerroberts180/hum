import SwiftUI

/// Hum's text roles, mapped onto macOS text styles so accessibility text sizes
/// work. Hierarchy comes from weight and color first, size second.
///
/// Tracking is never set by hand: SF Pro's optical sizes already tighten large
/// text and open up small text. Over artwork, text gets one weight heavier instead.
nonisolated enum HumType: Hashable, Sendable {
    case trackTitle
    case trackArtist
    case trackAlbum
    /// Text's title over its artist, in the 44-pt capsule (DESIGN.md §3.3, §7).
    case textTitle
    case textArtist
    /// Elapsed and remaining time; monospaced digits.
    case time
    case sectionHeader
    case rowTitle
    case rowSubtitle
    case cardTitle
    /// Echo numbers, in SF Pro Rounded.
    case statValue
    case statLabel
    case badge
    /// Banner and empty-state explanations.
    case caption

    func style(for sizeClass: PlayerSizeClass) -> Font.TextStyle {
        switch self {
        // A step above the artist line, so the title stands apart (§13.20).
        case .trackTitle: sizeClass == .large ? .title2 : .title3
        case .trackArtist: sizeClass == .small ? .subheadline : .body
        case .trackAlbum, .rowSubtitle: .subheadline
        case .textTitle: .headline
        case .textArtist: .subheadline
        case .time: sizeClass == .small ? .caption : .callout
        case .statLabel, .caption: .caption
        case .sectionHeader: .headline
        case .rowTitle: .body
        case .cardTitle: .callout
        case .statValue: sizeClass == .large ? .largeTitle : .title
        case .badge: .caption2
        }
    }

    var weight: Font.Weight {
        switch self {
        case .trackTitle, .cardTitle, .statValue, .textTitle: .semibold
        case .sectionHeader, .badge: .bold
        case .statLabel: .medium
        case .trackArtist, .trackAlbum, .textArtist, .time, .rowTitle, .rowSubtitle, .caption: .regular
        }
    }

    var color: HumColor {
        switch self {
        case .trackArtist, .textArtist, .rowSubtitle, .caption: .secondaryLabel
        case .trackAlbum, .time: .tertiaryLabel
        default: .label
        }
    }

    var usesMonospacedDigits: Bool { self == .time || self == .statValue }
    var isRounded: Bool { self == .statValue }

    func font(for sizeClass: PlayerSizeClass, overArtwork: Bool) -> Font {
        let base = Font.system(style(for: sizeClass), design: isRounded ? .rounded : .default)
            .weight(overArtwork ? weight.heavier : weight)
        return usesMonospacedDigits ? base.monospacedDigit() : base
    }
}

extension Font.Weight {
    /// One step heavier, for legibility over artwork and materials.
    nonisolated var heavier: Font.Weight {
        switch self {
        case .ultraLight: .thin
        case .thin: .light
        case .light: .regular
        case .regular: .medium
        case .medium: .semibold
        case .semibold: .bold
        case .bold: .heavy
        default: .black
        }
    }
}

/// Applies a `HumType` role: font, weight, and color for the current size class
/// and color context.
struct HumText: ViewModifier {
    var role: HumType
    /// Override the role's color, for example while a control is hovered.
    var color: HumColor?

    @Environment(\.playerMetrics) private var metrics
    @Environment(\.humColorContext) private var context

    func body(content: Content) -> some View {
        content
            .font(role.font(for: metrics.sizeClass, overArtwork: context == .artwork))
            .foregroundStyle(color ?? role.color)
    }
}

extension View {
    func humText(_ role: HumType, color: HumColor? = nil) -> some View {
        modifier(HumText(role: role, color: color))
    }
}
