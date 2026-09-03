import SwiftUI
import DevinKit

struct StatusBadge: View {
    let session: Session

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .overlay {
                    if session.bucket == .working {
                        Circle().stroke(color.opacity(0.4), lineWidth: 3)
                    }
                }
            Text(session.statusSummary)
                .font(.caption)
                .foregroundStyle(session.needsAttention ? color : .secondary)
        }
    }

    private var color: Color {
        switch session.bucket {
        case .needsYou: .orange
        case .working: .blue
        case .finished: .green
        case .sleeping: .gray
        case .failed: .red
        }
    }
}
