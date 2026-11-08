import Foundation

/// Advances only while idle. Randomness is injectable for deterministic behavior checks.
public struct IdleRoaming {
    public enum Phase: String { case resting, walking }
    public private(set) var phase: Phase = .resting
    public private(set) var remaining: TimeInterval
    public private(set) var direction: CGFloat = 1

    private static func unit(_ value: Double) -> Double { min(max(value.isFinite ? value : 0.5, 0), 1) }
    public init(sample: () -> Double = { Double.random(in: 0...1) }) {
        remaining = 15 + 25 * Self.unit(sample())
    }

    public mutating func advance(seconds: TimeInterval, sample: () -> Double = { Double.random(in: 0...1) }) {
        remaining -= seconds.isFinite ? min(max(seconds, 0), 0.25) : 0
        guard remaining <= 0 else { return }
        if phase == .resting {
            phase = .walking
            remaining = 2 + 3 * Self.unit(sample())
            direction = Self.unit(sample()) < 0.5 ? -1 : 1
        } else {
            phase = .resting
            remaining = 15 + 25 * Self.unit(sample())
        }
    }
}
