import Foundation

public extension Session {
    /// What `POST …/sessions/{id}/messages` will do for this session, per the v3 spec:
    /// "Send a message to an active session. The session will be automatically resumed if suspended."
    ///
    /// `exit` means the VM was destroyed (terminate, or a session created with `resumable: false`)
    /// and `error` sessions have nothing to resume, so the API cannot deliver a message to either.
    /// `SessionResponse` carries no `resumable` flag, so a disposable session that is still
    /// `suspended` looks wakeable until the API rejects the message — surface that error as-is.
    enum Messaging: Hashable, Sendable {
        /// Session is live; the message is delivered straight away.
        case active
        /// Session is asleep; the message resumes it (`suspended → resuming → running`).
        case wakesSession
        /// The message cannot be delivered; `reason` is user-facing copy explaining why.
        case unavailable(reason: String)

        public var acceptsMessages: Bool {
            switch self {
            case .active, .wakesSession: true
            case .unavailable: false
            }
        }
    }

    var messaging: Messaging {
        switch status {
        case .new, .claimed, .running, .resuming:
            return .active
        case .suspended:
            return .wakesSession
        case .exit:
            return .unavailable(reason: "This session has exited. Its machine is gone, so it can't be resumed — start a new session instead.")
        case .error:
            return .unavailable(reason: "This session failed and can't receive messages. Start a new session instead.")
        }
    }
}
