import Foundation

/// Chooses artwork without interpreting an idle provider as a successful turn.
public struct AnimationPlayback {
    private var previous: Activity?
    private var oneShot: String?
    private var remaining: TimeInterval = 0
    private var idleSeconds: TimeInterval = 0
    public let sleepAfter: TimeInterval

    public init(sleepAfter: TimeInterval = 120) { self.sleepAfter = sleepAfter }

    public mutating func advance(activity: Activity, seconds: TimeInterval, interacted: Bool = false,
                                 durations: [String: TimeInterval]) -> String {
        let dt = seconds.isFinite ? min(max(seconds, 0), 0.25) : 0
        let changed = previous != activity
        let first = previous == nil
        previous = activity
        if changed || interacted { idleSeconds = 0; oneShot = nil; remaining = 0 }
        if changed {
            let requested: String?
            switch activity {
            case .completed: requested = "success"
            case .failed: requested = "error"
            case .idle where first: requested = "spawn"
            default: requested = nil
            }
            if let name = requested, let duration = durations[name] {
                oneShot = name; remaining = duration
            }
        } else if oneShot != nil {
            remaining -= dt
            if remaining <= 0 { oneShot = nil }
        }
        // Real activity always interrupts startup, celebrations, and sleep.
        switch activity {
        case .working: return "working"
        case .attention: return durations["attention"] != nil ? "attention" : "idle"
        case .retired: return "retire"
        default: break
        }
        if let oneShot { return oneShot }
        if [.idle, .completed, .failed, .interrupted].contains(activity) {
            if !interacted { idleSeconds += dt }
            if idleSeconds >= sleepAfter, durations["sleep"] != nil { return "sleep" }
        }
        return "idle"
    }
}
