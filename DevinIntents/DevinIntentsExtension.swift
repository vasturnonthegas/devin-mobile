import AppIntents

/// Siri / Shortcuts entry point. Intents run here, out of process, so asking "what is Devin
/// waiting on?" never launches the app; everything they need (credentials, last snapshot, API)
/// comes from DevinKit through the shared App Group.
@main
struct DevinIntentsExtension: AppIntentsExtension {}
