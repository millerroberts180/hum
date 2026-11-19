import SwiftUI

/// The background of an inline banner (permission, warning, failure). Over
/// artwork, or on Big Art's backdrop, a banner floats, so it's glass: Liquid
/// Glass on macOS 26 and the HUD material before (`HumMaterial`). On a card or
/// material it's part of what's under it, so it's a fill, never glass on glass.
struct BannerBackground: ViewModifier {
    @Environment(\.humColorContext) private var context

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        if floats {
            content
                .environment(\.humColorContext, .material)
                .humMaterial(.glassCard, in: shape)
        } else {
            content.background(HumColor.fillQuaternary, in: shape)
        }
    }

    private var floats: Bool {
        switch context {
        case .artwork, .swatch: true
        case .material, .tinted: false
        }
    }
}

extension View {
    func bannerBackground() -> some View {
        modifier(BannerBackground())
    }

    /// A banner's text buttons (§5.9 family 5): bordered, the prominent one
    /// tinted with the accent. Never glass, even on macOS 26: a banner over
    /// artwork is glass already.
    @ViewBuilder
    func bannerButtonStyle(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
