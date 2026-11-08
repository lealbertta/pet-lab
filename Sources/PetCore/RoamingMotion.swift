import Foundation

/// Keep sub-point motion independent from the window server's rounded coordinates.
public struct RoamingMotion {
    public private(set) var x: CGFloat
    public private(set) var direction: CGFloat
    public init(x: CGFloat, direction: CGFloat = 1) {
        self.x = x
        self.direction = direction < 0 ? -1 : 1
    }

    @discardableResult
    public mutating func advance(seconds: TimeInterval, minX: CGFloat, maxX: CGFloat) -> CGFloat {
        let maximum = max(minX, maxX)
        x = min(max(x, minX), maximum)
        let delta = seconds.isFinite ? min(max(seconds, 0), 0.25) : 0
        x += direction * 22 * delta
        if x >= maximum { x = maximum; direction = -1 }
        if x <= minX { x = minX; direction = 1 }
        return x
    }
}
