import AppKit
import SwiftUI

/// Settings › Hum: Hum's icon, what it is and which version this is, whose the
/// music is, and the way to quit (DESIGN.md §8). About Hum in the app menu
/// opens it.
struct HumSettingsPane: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: Spacing.s) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: Self.iconSize, height: Self.iconSize)
                        .accessibilityHidden(true)
                    Text("Hum")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text(Self.version(from: Bundle.main.infoDictionary))
                        .foregroundStyle(HumColor.secondaryLabel)
                        .textSelection(.enabled)
                    VStack(spacing: Spacing.s) {
                        VStack(spacing: Spacing.xs) {
                            Text(Self.tagline)
                            Text(Self.description)
                                .foregroundStyle(HumColor.secondaryLabel)
                        }
                        .font(.callout)
                        VStack(spacing: Spacing.xs) {
                            Text(Self.requirement)
                            Text(Self.notice)
                        }
                        .font(.caption)
                        .foregroundStyle(HumColor.secondaryLabel)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: Self.textWidth)
                    .padding(.top, Spacing.s)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.l)
                .accessibilityElement(children: .combine)
            }

            Section("Quit") {
                LabeledContent {
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        ActionLabel("Quit Hum", symbol: "power")
                    }
                    .buttonStyle(ActionButtonStyle())
                } label: {
                    DetailLabel(title: "Leave the menu bar", detail: "Music and Spotify keep playing.")
                }
            }
        }
        .formStyle(.grouped)
    }

    static let iconSize: CGFloat = 64
    /// The text under the name is at most this wide, so its lines stay short.
    static let textWidth: CGFloat = 380

    nonisolated static let tagline = "The song you’re playing, always at hand."
    nonisolated static let description = "Hum shows what Music or Spotify is playing as a floating window of album art, with the controls there when you reach for them. Your listening history stays on this Mac."
    nonisolated static let requirement = "Requires macOS 15 or later"
    nonisolated static let notice = "Covers, titles and playback come from the music apps you use, and belong to their owners. Spotify is a trademark of Spotify AB. Apple Music is a trademark of Apple Inc. Hum is not affiliated with or endorsed by either."

    /// "Version 1.0.0 (1)" from the app's Info.plist. Run outside the app
    /// bundle (`swift run`) there's none, so it says this is a development
    /// build.
    nonisolated static func version(from info: [String: Any]?) -> String {
        guard let short = info?["CFBundleShortVersionString"] as? String, !short.isEmpty else {
            return "Development build"
        }
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty, build != short else {
            return "Version \(short)"
        }
        return "Version \(short) (\(build))"
    }
}
