import HumCore
import SwiftUI

/// When a song was heard: dots on a hairline from the start of tracking to now.
/// No axes, no gridlines (DESIGN.md §5.7).
struct MiniTimeline: View {
    var data: MiniTimelineData

    static let dot: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Canvas { context, size in
                let y = size.height / 2
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .style(HumColor.separator), lineWidth: 1)
                let usable = max(0, size.width - Self.dot)
                for mark in data.marks {
                    let rect = CGRect(x: usable * mark, y: y - Self.dot / 2, width: Self.dot, height: Self.dot)
                    context.fill(Path(ellipseIn: rect), with: .style(HumColor.accent))
                }
            }
            .frame(height: Self.dot + 2)
            HStack {
                Text(data.startLabel)
                Spacer(minLength: Spacing.s)
                Text(data.endLabel)
            }
            .font(.caption2)
            .foregroundStyle(HumColor.tertiaryLabel)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline")
        .accessibilityValue(HistoryFormat.count(data.marks.count, "play") + " between \(data.startLabel) and now")
    }
}

#if DEBUG
struct MiniTimeline_Previews: PreviewProvider {
    static var previews: some View {
        PreviewGallery(isSquare: false) {
            MiniTimeline(data: .preview)
                .padding(Spacing.m)
        }
    }
}
#endif
