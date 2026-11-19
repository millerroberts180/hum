import SwiftUI

/// Settings › History & Privacy: what Hum remembers about your listening, and
/// how to export or erase it. Its stored value is still `echoPrivacy`.
struct EchoPrivacySettingsPane: View {
    var body: some View {
        Form {
            EchoSettingsSection()
        }
        .formStyle(.grouped)
    }
}
