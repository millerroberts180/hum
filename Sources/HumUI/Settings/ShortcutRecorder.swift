import AppKit
import HumCore
import SwiftUI

/// A button that shows a shortcut and, when clicked, records a new one.
///
/// While recording, the next key press with ⌘, ⌥, or ⌃ becomes the shortcut.
/// Escape cancels; Delete clears it (when clearing is allowed). Global shortcuts
/// are paused while recording so the current one can be pressed to keep it.
///
/// A shortcut that can't work is turned down and the previous one kept, with a
/// line underneath saying why: Hum already uses it, or macOS or another app
/// does (from `GlobalShortcutStatus`, after the app has tried to register it).
struct ShortcutRecorder: View {
    @Binding var chord: HotKeyChord?
    var defaultChord: HotKeyChord?
    /// Which global shortcut this is, to hear whether macOS took it.
    var action: GlobalShortcutStatus.Action?
    /// Hum's other global shortcuts, which this one mustn't repeat.
    var others: [ShortcutConflict.Taken] = []

    @Environment(\.playerActions) private var actions
    @Environment(GlobalShortcutStatus.self) private var status: GlobalShortcutStatus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejected = false
    /// Why the last shortcut pressed wasn't taken, until the next try.
    @State private var turnedDown: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: Spacing.xs) {
            recorder
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(HumColor.secondaryLabel)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(Motion.spatial(Motion.smooth, reduceMotion: reduceMotion), value: note)
        .onDisappear(perform: stopRecording)
    }

    /// The line under the recorder: the last shortcut turned down, or the saved
    /// one if macOS has since stopped it working.
    private var note: String? {
        if isRecording { return nil }
        if let turnedDown { return turnedDown }
        if let action, let chord, status?.unavailable.contains(action) == true {
            return ShortcutConflict.unavailableMessage(for: chord)
        }
        return nil
    }

    private var recorder: some View {
        HStack(spacing: Spacing.s) {
            // A compact action button, as buttons in list rows are (§8),
            // selected while it's listening.
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(label)
                    .monospacedDigit()
                    .frame(minWidth: 96)
                    .foregroundStyle(isRecording ? HumColor.secondaryLabel : HumColor.label)
            }
            .buttonStyle(ActionButtonStyle(compact: true, isSelected: isRecording))
            .accessibilityLabel(isRecording ? "Recording shortcut" : "Shortcut: \(chord?.displayString ?? "none")")
            .accessibilityHint("Click, then press the new shortcut. Escape cancels.")

            if let defaultChord, chord != defaultChord {
                Button {
                    reset(to: defaultChord)
                } label: {
                    ActionLabel("Reset", symbol: "arrow.counterclockwise")
                }
                .buttonStyle(ActionButtonStyle(compact: true))
                .help("Reset to \(defaultChord.displayString)")
            } else if defaultChord == nil, chord != nil {
                Button {
                    turnedDown = nil
                    chord = nil
                } label: {
                    ActionLabel("Clear")
                }
                .buttonStyle(ActionButtonStyle(compact: true))
            }
        }
    }

    private var label: String {
        if isRecording { return rejected ? "Add ⌘, ⌥, or ⌃" : "Type Shortcut…" }
        return chord?.displayString ?? "None"
    }

    private func startRecording() {
        rejected = false
        turnedDown = nil
        isRecording = true
        actions.suspendGlobalShortcuts(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if isRecording {
            actions.suspendGlobalShortcuts(false)
        }
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        let modifiers = HotKeyChord.Modifiers(event.modifierFlags)
        if modifiers.isEmpty, event.keyCode == PlayerKeyCommand.KeyCode.escape {
            stopRecording()
            return
        }
        if modifiers.isEmpty, event.keyCode == 51 || event.keyCode == 117 {
            if defaultChord == nil { chord = nil }
            stopRecording()
            return
        }
        let candidate = HotKeyChord(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            keyLabel: Self.keyLabel(for: event)
        )
        guard candidate.isValidGlobalShortcut else {
            rejected = true
            return
        }
        let previous = chord
        if let conflict = ShortcutConflict.check(candidate, character: event.charactersIgnoringModifiers ?? "", others: others) {
            stopRecording()
            turnDown(candidate, conflict, keeping: previous)
            return
        }
        chord = candidate
        // Resuming global shortcuts registers the new chord first (see `HumApp`),
        // so the status then says whether macOS took it.
        stopRecording()
        if candidate != previous, let action, status?.unavailable.contains(action) == true {
            chord = previous
            turnDown(candidate, .unavailable, keeping: previous)
        }
    }

    private func reset(to defaultChord: HotKeyChord) {
        turnedDown = nil
        if let conflict = ShortcutConflict.check(defaultChord, character: defaultChord.keyLabel, others: others) {
            turnDown(defaultChord, conflict, keeping: chord)
            return
        }
        chord = defaultChord
    }

    private func turnDown(_ candidate: HotKeyChord, _ conflict: ShortcutConflict, keeping previous: HotKeyChord?) {
        let message = conflict.message(for: candidate, keeping: previous)
        turnedDown = message
        AccessibilityNotification.Announcement(message).post()
    }

    static func keyLabel(for event: NSEvent) -> String {
        switch event.keyCode {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}
