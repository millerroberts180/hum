import HumCore
import SwiftUI

/// What the repeat button says, once, the first time One is picked for an
/// app whose own repeat is only on or off: the app's button keeps showing its
/// repeat on, and Hum starts the song over itself (DESIGN.md §5.2, §13.35).
/// The player never names the app (§10).
enum RepeatOneNote {
    nonisolated static let title = "Hum Repeats This Song"
    nonisolated static let message = "Your music app can’t show repeat one, so its own repeat button stays on. Hum starts the song over just before it ends."

    /// Whether choosing `mode` brings the note: One, for an app Hum repeats
    /// the song for, the first time.
    nonisolated static func shows(choosing mode: RepeatMode, capabilities: SourceCapabilities, alreadyShown: Bool) -> Bool {
        mode == .one && capabilities.contains(.repeatOneByRestart) && !alreadyShown
    }
}

extension View {
    /// Presents the repeat-one note from this view while `isOpen`.
    func repeatOneNote(isOpen: Binding<Bool>) -> some View {
        modifier(RepeatOneNoteHost(isOpen: isOpen))
    }
}

/// A system popover, as the volume slider's is (§5.11): it holds the controls
/// up, since pointing at it leaves the player, and closes on an outside
/// click, on Esc, and when the player hides.
private struct RepeatOneNoteHost: ViewModifier {
    @Binding var isOpen: Bool

    @Environment(PlayerInteraction.self) private var interaction: PlayerInteraction?
    @State private var holdToken = UUID()

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                RepeatOneNoteView()
            }
            .onChange(of: isOpen) { _, open in
                interaction?.setPopoverOpen(open, token: holdToken)
            }
            .onChange(of: interaction?.popoverCloseRequestCount) {
                if isOpen { isOpen = false }
            }
            .onChange(of: interaction?.isPresented) { _, presented in
                if presented == false { isOpen = false }
            }
            .onDisappear {
                interaction?.setPopoverOpen(false, token: holdToken)
            }
    }
}

/// The popover's content: the `repeat.1` glyph in the accent, as the button
/// shows One, then the title and the sentence.
struct RepeatOneNoteView: View {
    /// The text column.
    static let width: CGFloat = 240

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: HumIcon.repeatOne)
                .font(.body.weight(.semibold))
                .foregroundStyle(HumColor.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(RepeatOneNote.title)
                    .font(.headline)
                    .foregroundStyle(HumColor.label)
                Text(RepeatOneNote.message)
                    .font(.callout)
                    .foregroundStyle(HumColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Self.width, alignment: .leading)
        }
        .padding(Spacing.l)
        .environment(\.humColorContext, .material)
        .accessibilityElement(children: .combine)
    }
}
