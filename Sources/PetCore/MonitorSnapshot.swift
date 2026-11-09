import Foundation

public struct MonitorSnapshot: Decodable {
    public let schemaVersion: Int
    public let generation: String
    public let mode: String?
    public let sharedPack: String?
    public let sessions: [Session]
    public struct Session: Decodable {
        public let key: String
        public let activity: Activity
        public let title: String?
        public let pack: String?
    }
    public func forSession(_ key: String) -> MonitorSnapshot {
        MonitorSnapshot(schemaVersion: schemaVersion, generation: generation, mode: mode, sharedPack: sharedPack, sessions: sessions.filter { $0.key == key })
    }
    public var sharedActivity: Activity {
        // A session waiting on the user outranks work, so it is never hidden behind a busy one.
        for state in [Activity.attention, .working, .uncertain, .failed, .completed, .interrupted] {
            if sessions.contains(where: { $0.activity == state }) { return state }
        }
        return .idle
    }
    public var preferredSession: Session? {
        let order: [Activity] = [.attention, .working, .uncertain, .idle, .completed, .failed, .interrupted, .retired]
        return sessions.sorted {
            let a = order.firstIndex(of: $0.activity) ?? order.count
            let b = order.firstIndex(of: $1.activity) ?? order.count
            return a == b ? $0.key < $1.key : a < b
        }.first
    }
}
