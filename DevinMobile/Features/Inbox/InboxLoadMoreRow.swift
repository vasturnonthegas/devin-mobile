import SwiftUI

/// Footer of the inbox list: spinner while a page is in flight, otherwise an explicit
/// "Load more" fallback for when scroll-triggered prefetch didn't fire (short lists, search).
struct InboxLoadMoreRow: View {
    let store: SessionStore

    var body: some View {
        HStack {
            Spacer()
            if store.isLoadingMore {
                ProgressView()
            } else {
                Button("Load more") {
                    Task { await store.loadMore() }
                }
                .buttonStyle(.borderless)
            }
            Spacer()
        }
        .frame(minHeight: 32)
        .accessibilityIdentifier("inbox.loadMore")
    }
}

extension InboxView {
    /// Rows this close to the end of the visible list trigger a prefetch of the next page.
    static let prefetchWindow = 10
}
