import SwiftUI

/// One line of text that, when it doesn't fit, scrolls once while the pointer
/// rests on it: a pause, a steady crawl to the end, a pause, then a fade back to
/// the start. It never moves on its own, and never under Reduce Motion.
struct MarqueeText: View {
    var text: String
    /// Take the line's whole width, or only what the text needs, so a line
    /// beside it gets the rest.
    var fillsWidth = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isScrolling = false
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1
    @State private var fullWidth: CGFloat = 0
    @State private var visibleWidth: CGFloat = 0

    init(_ text: String, fillsWidth: Bool = true) {
        self.text = text
        self.fillsWidth = fillsWidth
    }

    private var overflow: CGFloat { max(0, fullWidth - visibleWidth) }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(isScrolling ? 0 : 1)
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                visibleWidth = width
            }
            .background(alignment: .leading) {
                // The whole line, measured, and shown only while scrolling.
                Text(text)
                    .lineLimit(1)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { width in
                        fullWidth = width
                    }
                    .offset(x: offset)
                    .opacity(isScrolling ? opacity : 0)
            }
            .clipped()
            .onHover { isHovered = $0 }
            .task(id: isHovered && overflow > 0 && !reduceMotion) {
                await run()
            }
    }

    private func run() async {
        defer { reset() }
        guard isHovered, overflow > 0, !reduceMotion else { return }
        do {
            try await Task.sleep(for: Motion.marqueeDelay)
            isScrolling = true
            let distance = overflow
            let seconds = Double(distance / Motion.marqueeSpeed)
            withAnimation(.linear(duration: seconds)) { offset = -distance }
            try await Task.sleep(for: .seconds(seconds) + Motion.marqueeEndPause)
            withAnimation(Motion.crossfade) { opacity = 0 }
            try await Task.sleep(for: .milliseconds(200))
        } catch {
            return
        }
    }

    private func reset() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            offset = 0
            opacity = 1
            isScrolling = false
        }
    }
}
