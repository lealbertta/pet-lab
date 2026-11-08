import Foundation

public enum DesktopGeometry {
    public static func petBounds(on screen: CGRect, accessoryHeight: CGFloat) -> CGRect {
        CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: max(0, screen.height-accessoryHeight))
    }
    public static func clamp(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        var result = frame
        result.origin.x = min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX-frame.width))
        result.origin.y = min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY-frame.height))
        return result
    }

    public static func containingScreen(for frame: CGRect, screens: [CGRect]) -> CGRect? {
        screens.max { a, b in
            let ai = frame.intersection(a), bi = frame.intersection(b)
            return max(0, ai.width)*max(0, ai.height) < max(0, bi.width)*max(0, bi.height)
        }
    }
}
