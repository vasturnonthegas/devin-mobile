import SwiftUI
import DevinKit

extension Session.Messaging {
    var composerPlaceholder: String {
        switch self {
        case .active: "Message Devin…"
        case .wakesSession: "Message Devin — this wakes the session"
        case .unavailable: ""
        }
    }
}

/// One-line caption shown above the composer when sending will resume a sleeping session.
struct ComposerWakeHint: View {
    var body: some View {
        Label("Asleep — sending a message resumes this session.", systemImage: "moon.zzz")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 8)
            .accessibilityIdentifier("composer.wakeHint")
    }
}

/// Replaces the composer when the API cannot deliver a message (`Session.Messaging.unavailable`).
struct ComposerUnavailableFooter: View {
    let reason: String
    let openInDevin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Can't message this session", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                .font(.subheadline.weight(.semibold))
            Text(reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Open in Devin", action: openInDevin)
                .font(.footnote.weight(.medium))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityIdentifier("composer.unavailable")
    }
}

#Preview("Unavailable") {
    ComposerUnavailableFooter(reason: "This session has exited. Its machine is gone, so it can't be resumed — start a new session instead.") {}
}

#Preview("Wake hint") {
    ComposerWakeHint()
}
