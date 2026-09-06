import SwiftUI
import DevinKit

/// "Advanced" disclosure of the New Session form. Every field starts at the API default, and
/// `applied(to:)` copies only the ones the user changed so the server keeps applying its own
/// defaults (and future default changes) for the rest.
struct NewSessionAdvancedOptions: Equatable {
    var bypassApproval = false
    var resumable = true
    var platform = ""
    var schemaText = ""

    private var trimmedPlatform: String { platform.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasSchema: Bool { !schemaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Blank text means "no schema"; anything else must pass `StructuredOutputSchema.parse`.
    var schemaProblem: String? {
        guard hasSchema else { return nil }
        do {
            _ = try StructuredOutputSchema.parse(schemaText)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var isValid: Bool { schemaProblem == nil }

    var isDefault: Bool { self == NewSessionAdvancedOptions() }

    func applied(to request: NewSessionRequest) throws -> NewSessionRequest {
        var request = request
        if bypassApproval { request.bypassApproval = true }
        if !resumable { request.resumable = false }
        if !trimmedPlatform.isEmpty { request.platform = trimmedPlatform }
        if hasSchema { request.structuredOutputSchema = try StructuredOutputSchema.parse(schemaText) }
        return request
    }
}

struct NewSessionAdvancedSection: View {
    @Binding var options: NewSessionAdvancedOptions
    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded.animation()) {
                Toggle("Bypass plan approval", isOn: $options.bypassApproval)
                Toggle("Resumable", isOn: $options.resumable)
                TextField("Platform (e.g. windows or an outpost pool)", text: $options.platform)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Structured output schema (JSON)", text: $options.schemaText, axis: .vertical)
                    .lineLimit(3...12)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                if let problem = options.schemaProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } label: {
                HStack {
                    Text("Advanced")
                    Spacer()
                    if !isExpanded, !options.isDefault {
                        Text(options.isValid ? "Customized" : "Needs attention")
                            .font(.footnote)
                            .foregroundStyle(options.isValid ? Color.secondary : Color.red)
                    }
                }
            }
        } footer: {
            if isExpanded {
                Text("Bypass plan approval lets Devin start working without waiting for you to confirm its plan. Turning off Resumable discards the VM when the session stops. Platform overrides the VM (e.g. windows) or names an outpost pool. The schema is a self-contained Draft 7 JSON Schema object, up to 64 KB.")
            }
        }
    }
}

#Preview {
    struct Host: View {
        @State private var options = NewSessionAdvancedOptions(
            bypassApproval: true,
            schemaText: #"{"type": "object", "properties": {"count": {"type": "integer"}}"#
        )
        var body: some View {
            Form { NewSessionAdvancedSection(options: $options) }
        }
    }
    return Host()
}
