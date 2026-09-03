import SwiftUI
import DevinKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                if let account = app.account {
                    Section("Account") {
                        LabeledContent("Signed in as", value: account.credentials.displayName ?? "—")
                        LabeledContent("Organization", value: account.credentials.orgID)
                        LabeledContent("Token", value: masked(account.credentials.token))
                    }
                }

                Section("Links") {
                    Link(destination: URL(string: "https://app.devin.ai")!) {
                        Label("Open Devin web app", systemImage: "safari")
                    }
                    Link(destination: URL(string: "https://docs.devin.ai/api-reference/personal-access-tokens")!) {
                        Label("Manage Personal Access Tokens", systemImage: "key")
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                } footer: {
                    Text("Devin Mobile \(Bundle.main.shortVersion) · DevinKit \(DevinKitVersion.string)")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Sign out and remove the token from this device?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    app.signOut()
                    dismiss()
                }
            }
        }
    }

    private func masked(_ token: String) -> String {
        guard token.count > 10 else { return "••••" }
        return String(token.prefix(6)) + "…" + String(token.suffix(4))
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
