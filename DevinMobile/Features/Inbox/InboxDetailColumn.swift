import SwiftUI
import DevinKit

/// Detail column of the iPad `NavigationSplitView`. Owns its own stack so child / related-session
/// links push inside the column; the stack resets whenever the sidebar selection changes.
struct InboxDetailColumn: View {
    let store: SessionStore
    @Binding var selectedID: Session.ID?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let selectedID {
                    SessionDetailView(store: store, sessionID: selectedID)
                        .id(selectedID)
                        // The column root has nothing to pop to, so "dismiss" means clearing the selection.
                        .environment(\.dismissSplitDetail, DismissSplitDetailAction { self.selectedID = nil })
                } else {
                    ContentUnavailableView(
                        "Select a session",
                        systemImage: "sidebar.left",
                        description: Text("Pick a session from the list to read its transcript and reply.")
                    )
                }
            }
            .navigationDestination(for: Session.self) { session in
                SessionDetailView(store: store, sessionID: session.id)
                    .id(session.id)
            }
        }
        .onChange(of: selectedID) { _, _ in path = NavigationPath() }
    }
}

/// Set by `InboxDetailColumn` on the root detail view. Absent (nil) when the detail was pushed or
/// presented, in which case the regular `dismiss` action applies.
struct DismissSplitDetailAction: Sendable {
    private let handler: @MainActor @Sendable () -> Void

    init(_ handler: @escaping @MainActor @Sendable () -> Void) {
        self.handler = handler
    }

    @MainActor
    func callAsFunction() { handler() }
}

extension EnvironmentValues {
    var dismissSplitDetail: DismissSplitDetailAction? {
        get { self[DismissSplitDetailKey.self] }
        set { self[DismissSplitDetailKey.self] = newValue }
    }
}

private struct DismissSplitDetailKey: EnvironmentKey {
    static let defaultValue: DismissSplitDetailAction? = nil
}
