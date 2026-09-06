import SwiftUI
import DevinKit

/// Multi-select list of secrets by name. Only metadata (`key`, `note`, type) is ever rendered —
/// the API does not return values and `OrgSecret` cannot hold one.
struct SecretPickerView: View {
    let model: SessionResourcesModel
    @Binding var selection: Set<String>

    @State private var search = ""

    var body: some View {
        let secrets = model.secrets(matching: search)
        List {
            if secrets.isEmpty {
                ContentUnavailableView.search(text: search)
            }
            Section {
                ForEach(secrets) { secret in
                    SecretRow(secret: secret, isSelected: selection.contains(secret.secretID)) {
                        toggle(secret.secretID)
                    }
                }
            } footer: {
                if !secrets.isEmpty {
                    Text("Values stay on the server. Devin receives them inside the session only.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search secrets")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .navigationTitle("Secrets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selection.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") { selection.removeAll() }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}

private struct SecretRow: View {
    let secret: OrgSecret
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .imageScale(.large)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(secret.displayName)
                            .font(secret.key != nil ? .body.monospaced() : .body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if secret.accessType == .personal {
                            Image(systemName: "person")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Personal secret")
                        }
                    }
                    if let detail = secret.detailSummary {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
