import SwiftUI
import DevinKit

/// "Start related session" flow for a session detail: presents the New Session sheet pre-linked to
/// `session`, then pushes the created session onto the enclosing navigation stack.
struct RelatedSessionFlow: ViewModifier {
    let store: SessionStore
    let session: Session?
    @Binding var isPresented: Bool

    @State private var created: Session?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                if let session {
                    NewSessionView(store: store, relatedSession: session) { created = $0 }
                }
            }
            .navigationDestination(item: $created) { session in
                SessionDetailView(store: store, sessionID: session.sessionID)
            }
    }
}

extension View {
    func relatedSessionFlow(store: SessionStore, session: Session?, isPresented: Binding<Bool>) -> some View {
        modifier(RelatedSessionFlow(store: store, session: session, isPresented: isPresented))
    }
}
