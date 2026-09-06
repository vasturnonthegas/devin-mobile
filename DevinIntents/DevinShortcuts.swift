import AppIntents

/// Siri phrases. `\(.applicationName)` is "Devin" (`CFBundleDisplayName`); every phrase must
/// contain it. Living in the extension means Siri never has to launch the app to answer.
struct DevinShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatIsDevinWaitingOnIntent(),
            phrases: [
                "What is \(.applicationName) waiting on",
                "What's \(.applicationName) waiting on",
                "What does \(.applicationName) need",
                "Is \(.applicationName) waiting on me",
                "Check on \(.applicationName)",
            ],
            shortTitle: "What's Devin waiting on?",
            systemImageName: "exclamationmark.bubble"
        )
        AppShortcut(
            intent: StartDevinSessionIntent(),
            phrases: [
                "Start a \(.applicationName) session",
                "New \(.applicationName) session",
                "Ask \(.applicationName) to do something",
                "Give \(.applicationName) a task",
            ],
            shortTitle: "Start a session",
            systemImageName: "plus.bubble"
        )
        AppShortcut(
            intent: ReplyToDevinIntent(),
            phrases: [
                "Reply to \(.applicationName)",
                "Message \(.applicationName)",
                "Answer \(.applicationName)",
            ],
            shortTitle: "Reply to a session",
            systemImageName: "arrowshape.turn.up.left"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}
