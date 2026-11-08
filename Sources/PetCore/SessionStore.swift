import Foundation

public enum Activity: String, Codable {
    case idle, working, attention, completed, interrupted, failed, uncertain, retired
}

/// Only metadata crosses this boundary; prompts, results and tool arguments do not.
public struct SessionEvent: Codable {
    public var id: String
    public var provider: String
    public var session: String
    public var turn: String?
    public var kind: String
    public var observedNs: UInt64
    public var backgroundCount: Int?

    public init(id: String = UUID().uuidString, provider: String, session: String,
                turn: String? = nil, kind: String, observedNs: UInt64,
                backgroundCount: Int? = nil) {
        self.id = id; self.provider = provider; self.session = session
        self.turn = turn; self.kind = kind; self.observedNs = observedNs
        self.backgroundCount = backgroundCount
    }
    public var key: String { "\(provider):\(session)" }
}

public struct TrackedSession {
    public var provider: String
    public var session: String
    public var turn: String?
    public var activity: Activity = .idle
    public var lastObservedNs: UInt64 = 0
    public var backgroundCount: Int = 0
    public var stopPending = false
}

public final class SessionStore {
    public private(set) var sessions: [String: TrackedSession] = [:]
    // The prototype does not compact its queue; a long-running product needs bounded retention.
    private var seen: Set<String> = []
    public init() {}

    public func apply(_ event: SessionEvent) {
        guard !seen.contains(event.id) else { return }
        seen.insert(event.id)
        var state = sessions[event.key] ?? TrackedSession(provider: event.provider, session: event.session)
        // A late final-result callback cannot resurrect a process/session that already ended.
        guard state.activity != .retired || ["sessionStart", "turnStart"].contains(event.kind) else { return }
        // Arrival timestamps are not provider sequence numbers. They reject older observations,
        // but cannot prove source order when an uncorrelated hook starts late.
        guard event.observedNs >= state.lastObservedNs else { return }
        let sessionScoped = ["sessionStart", "sessionEnd", "backgroundStart", "backgroundEnd", "disconnected"]
        if event.kind != "turnStart", !sessionScoped.contains(event.kind),
           let turn = event.turn, let current = state.turn, turn != current { return }
        state.lastObservedNs = event.observedNs
        switch event.kind {
        case "sessionStart":
            if state.activity == .retired { state.activity = .idle }
        case "turnStart":
            state.turn = event.turn; state.activity = .working; state.stopPending = false
        case "toolStart", "requestStart", "resumeWork":
            state.activity = .working; state.stopPending = false
        case "toolEnd", "requestEnd", "heartbeat":
            break // A tool or request finishing never finishes the whole turn.
        case "attention": state.activity = .attention
        case "stopCandidate":
            state.stopPending = true
            if let count = event.backgroundCount { state.backgroundCount = count }
            // Stop hooks can still be continued by another hook. Reconcile before going idle.
        case "backgroundStart":
            state.backgroundCount += 1; state.activity = .working
        case "backgroundEnd":
            state.backgroundCount = max(0, state.backgroundCount - 1)
            // Parent status still requires a completion/reconciliation event.
        case "completed":
            if let count = event.backgroundCount { state.backgroundCount = count }
            state.activity = state.backgroundCount > 0 ? .working : .completed
            state.stopPending = false
        case "interrupted": state.activity = .interrupted; state.stopPending = false
        case "failed": state.activity = .failed; state.stopPending = false
        case "disconnected": state.activity = .uncertain
        case "sessionEnd": state.activity = .retired; state.stopPending = false
        case "idle": state.activity = .idle; state.stopPending = false
        default: return
        }
        sessions[event.key] = state
    }

    public var sharedActivity: Activity {
        let states = sessions.values.map(\.activity)
        // Keep ongoing work visible. Attention remains independently represented as a count.
        for value in [Activity.working, .attention, .uncertain, .failed, .completed, .interrupted] {
            if states.contains(value) { return value }
        }
        return .idle
    }
    public var attentionCount: Int { sessions.values.filter { $0.activity == .attention }.count }
}
