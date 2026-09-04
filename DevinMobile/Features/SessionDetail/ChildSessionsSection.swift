import SwiftUI
import DevinKit

/// "N children" disclosure on a parent session. Children are fetched on first expansion and
/// pushed into the `SessionStore` so tapping one opens its detail even if the inbox never listed it.
struct ChildSessionsSection: View {
    let store: SessionStore
    let parent: Session

    @State private var isExpanded = false
    @State private var children: [Session] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                if isLoading && children.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else if let error, children.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.vertical, 8)
                } else {
                    ForEach(children) { child in
                        NavigationLink(value: child) {
                            ChildSessionRow(session: child)
                        }
                        .buttonStyle(.plain)
                        if child.id != children.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label {
                Text("^[\(parent.childCount) child](inflect: true)")
            } icon: {
                Image(systemName: "arrow.triangle.branch")
            }
            .font(.subheadline)
        }
        .task(id: isExpanded ? parent.childSessionIDs : nil) {
            guard isExpanded else { return }
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await store.client.childSessions(org: store.orgID, of: parent.id)
            children = page.items.sorted { $0.createdAt < $1.createdAt }
            children.forEach(store.apply)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ChildSessionRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StatusBadge(session: session)
                    if session.isArchived {
                        Text("Archived")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if !session.pullRequests.isEmpty {
                        Label("\(session.pullRequests.count)", systemImage: "arrow.triangle.pull")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            Text(session.updatedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
