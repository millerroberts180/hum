import HumCore
import SwiftUI

/// A calm stand-in for a surface that hasn't been built yet.
struct SurfacePlaceholder: View {
    var surface: Surface
    var message: String

    @Environment(\.playerMetrics) private var metrics

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: surface.systemImage)
                .font(.system(size: 28, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HumColor.tertiaryLabel)
                .accessibilityHidden(true)
            Text(surface.title)
                .font(.headline)
                .foregroundStyle(HumColor.label)
            if metrics.sizeClass != .small {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(HumColor.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, metrics.contentInset * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ArtBackdrop(artwork: nil) }
        .accessibilityElement(children: .combine)
    }
}
