import AppKit
import SwiftUI

/// Start-up and how Hum fits into the Mac.
struct GeneralSettingsPane: View {
    @State private var loginItem = LoginItem()

    var body: some View {
        Form {
            Section {
                DetailToggle(title: "Open at login", detail: loginDetail, isOn: loginBinding)
                if loginItem.needsApproval {
                    LabeledContent {
                        Button {
                            loginItem.openLoginItemsSettings()
                        } label: {
                            ActionLabel("Open Login Items…")
                        }
                        .buttonStyle(ActionButtonStyle())
                    } label: {
                        DetailLabel(title: "Waiting for approval", detail: "Allow Hum in System Settings › General › Login Items.")
                    }
                }
            } header: {
                Text("Startup")
            } footer: {
                FooterNote("Hum lives in the menu bar. Its menu shows the player, the surfaces, and Settings.")
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding {
            loginItem.isOn
        } set: { isOn in
            loginItem.set(isOn)
        }
    }

    private var loginDetail: String {
        if let failure = loginItem.failure { return failure }
        if loginItem.needsApproval { return "On once you allow it in System Settings." }
        return "Start Hum when you log in, ready in the menu bar."
    }
}
