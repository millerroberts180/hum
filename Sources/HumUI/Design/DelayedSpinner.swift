import SwiftUI

/// A small spinner that appears only once something has taken longer than
/// `Motion.spinnerDelay`, so quick operations never flash one.
struct DelayedSpinner: View {
    @State private var isShowing = false

    var body: some View {
        ZStack {
            if isShowing {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
        }
        .frame(width: 16, height: 16)
        .task {
            try? await Task.sleep(for: Motion.spinnerDelay)
            withAnimation(Motion.reveal) { isShowing = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}
