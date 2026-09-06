import SwiftUI
import DevinKit

struct OnboardingView: View {
    @Environment(AppModel.self) private var app

    @State private var token = ""
    @State private var orgID = ""
    @State private var showOrgField = false
    @State private var wantsNotifications = true
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        token.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("cog_") && !isSigningIn
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.tint)
                        Text("Control your Devins from anywhere")
                            .font(.title2.bold())
                        Text("Paste a Personal Access Token to see what's running, unblock sessions waiting on you, and kick off new work.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    SecureField("cog_…", text: $token)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        .onSubmit(submit)
                } header: {
                    Text("Personal Access Token")
                } footer: {
                    Text("Create one in Devin → Settings → Devin API → Personal Access Tokens. It's stored only in this device's Keychain.")
                }

                if showOrgField {
                    Section {
                        TextField("org-…", text: $orgID)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("Organization ID")
                    } footer: {
                        Text("Enterprise tokens aren't bound to one organization. Find the ID under Settings → Service Users.")
                    }
                }

                Section {
                    Toggle(isOn: $wantsNotifications) {
                        Label("Notify me when Devin needs me", systemImage: "bell.badge")
                    }
                } footer: {
                    Text("Checks about every 15 minutes in the background and notifies you when a session is waiting on you or finishes. You can change this later in Settings.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isSigningIn {
                                ProgressView()
                            } else {
                                Text("Connect")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)

                    if !showOrgField {
                        Button("I have an enterprise token") { showOrgField = true }
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Devin")
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isSigningIn = true
        errorMessage = nil
        Task {
            defer { isSigningIn = false }
            do {
                try await app.signIn(token: token, orgOverride: showOrgField ? orgID : nil)
                // The system prompt appears over the inbox that has just replaced this view.
                if wantsNotifications { await SessionNotifier.requestAuthorization() }
            } catch DevinError.missingOrganization {
                showOrgField = true
                errorMessage = DevinError.missingOrganization.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppModel(store: InMemoryCredentialStore()))
}
