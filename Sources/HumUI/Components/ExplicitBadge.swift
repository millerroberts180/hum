import SwiftUI

/// The explicit mark: `e.square.fill` at the subtitle's size, so it follows
/// the text's size and weight.
struct ExplicitBadge: View {
    var body: some View {
        Image(systemName: "e.square.fill")
            .humText(.rowSubtitle, color: .secondaryLabel)
            .accessibilityLabel("Explicit")
    }
}
