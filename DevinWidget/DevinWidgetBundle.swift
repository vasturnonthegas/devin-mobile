import SwiftUI
import WidgetKit

@main
struct DevinWidgetBundle: WidgetBundle {
    var body: some Widget {
        NeedsYouWidget()
    }
}

/// "Needs you: N" plus the top sessions from the app's last `SessionSnapshot`. The widget never
/// calls the API; the app reloads its timeline whenever the snapshot changes.
struct NeedsYouWidget: Widget {
    static let kind = "ai.devin.mobile.needs-you"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotTimelineProvider()) { entry in
            NeedsYouWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Needs you")
        .description("Sessions waiting on you and what Devin is working on.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
