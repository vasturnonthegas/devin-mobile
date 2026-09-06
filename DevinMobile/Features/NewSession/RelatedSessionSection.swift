import SwiftUI
import DevinKit

/// "Related session" section of the New Session form, shown when the sheet was opened from a
/// session's detail. The toggle decides whether that session's link rides along in `session_links`.
struct RelatedSessionSection: View {
    let session: Session
    @Binding var isLinked: Bool

    var body: some View {
        Section {
            Toggle(isOn: $isLinked) {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .foregroundStyle(isLinked ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.displayTitle)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            StatusBadge(session: session)
                            Text(session.sessionID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        } header: {
            Text("Related session")
        } footer: {
            Text(isLinked
                 ? "Devin gets a link to this session and can read its transcript for context."
                 : "The new session starts without a link to this one.")
        }
    }
}
