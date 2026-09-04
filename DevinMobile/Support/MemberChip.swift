import SwiftUI
import DevinKit

/// Initials avatar + name for the member who owns a session.
struct MemberChip: View {
    let member: OrgMember
    var showsName = true

    var body: some View {
        HStack(spacing: 4) {
            Text(member.initials)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(color, in: Circle())
            if showsName {
                Text(member.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Owner: \(member.displayName)")
    }

    /// Stable per-user hue so the same person always gets the same colour.
    private var color: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint, .brown]
        let hash = member.userID.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}
