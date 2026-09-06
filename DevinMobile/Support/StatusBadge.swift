import SwiftUI
import UIKit
import DevinKit

struct StatusBadge: View {
    let session: Session

    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 7

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: dotSize, height: dotSize)
                .overlay {
                    if session.bucket == .working {
                        Circle().stroke(color.opacity(0.4), lineWidth: dotSize * 0.4)
                    }
                }
            Text(session.statusSummary)
                .font(.caption)
                .foregroundStyle(session.needsAttention ? color : .secondary)
        }
        // The dot is the only cue for the bucket, so VoiceOver gets it in words.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.accessibilityStatus)
    }

    private var color: Color {
        switch session.bucket {
        case .needsYou: .needsYou
        case .working: .blue
        case .finished: .green
        case .sleeping: .gray
        case .failed: .red
        }
    }
}

extension Color {
    /// The Needs-you accent. System orange as *text* on a light background is 2.1:1, which fails the
    /// Accessibility Inspector's contrast audit; this shade is ~5:1 in light mode and falls back to
    /// system orange in dark mode, where that already passes. Text drawn on top of it uses `onNeedsYou`.
    static let needsYou = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemOrange : UIColor(red: 0.69, green: 0.33, blue: 0, alpha: 1)
    })

    /// White on the deep orange, black on system orange — both ≥ 5:1.
    static let onNeedsYou = Color(uiColor: .systemBackground)
}

extension Session {
    /// "Needs you: Waiting for you", or just "Finished" when the bucket and summary coincide.
    var accessibilityStatus: String {
        bucket.title == statusSummary ? statusSummary : "\(bucket.title): \(statusSummary)"
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(MockAPI.sessions.prefix(8)) { StatusBadge(session: $0) }
    }
    .padding()
}
#endif
