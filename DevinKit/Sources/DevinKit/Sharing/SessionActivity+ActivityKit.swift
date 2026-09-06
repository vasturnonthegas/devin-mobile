#if os(iOS) && canImport(ActivityKit)
import ActivityKit

// ActivityKit is `@available(macOS, unavailable)` even though the macOS SDK ships the module, hence
// the `os(iOS)` guard. Both the app (requests/updates) and the widget extension (renders) see the
// same conformance through DevinKit.
extension SessionActivityAttributes: ActivityAttributes {
    public typealias ContentState = State
}
#endif
