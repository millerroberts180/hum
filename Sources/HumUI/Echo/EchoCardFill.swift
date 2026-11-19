import SwiftUI

extension View {
    /// The backing for Echo's cards and notes. They are the surface's content,
    /// not a layer floating over it, so they take a fill rather than glass, on
    /// every macOS version (DESIGN.md §3.6). Increase Contrast adds a hairline
    /// edge so the card still reads against a busy cover.
    func echoCardFill(in shape: some InsettableShape) -> some View {
        modifier(EchoCardFill(shape: shape))
    }
}

private struct EchoCardFill<S: InsettableShape>: ViewModifier {
    var shape: S

    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(HumColor.fillQuaternary, in: shape)
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(HumColor.separator, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
    }
}
