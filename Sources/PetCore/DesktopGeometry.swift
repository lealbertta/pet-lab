import Foundation

public enum DesktopGeometry {
    /// Window frames a pet may occupy. `footInset` is how far the pet's feet sit above the
    /// bottom of its window; the window may dip that far below `screen` so the feet, not the
    /// transparent padding under them, rest on the floor.
    public static func petBounds(on screen: CGRect, accessoryHeight: CGFloat, footInset: CGFloat = 0) -> CGRect {
        CGRect(x: screen.minX, y: screen.minY-footInset, width: screen.width,
               height: max(0, screen.height-accessoryHeight+footInset))
    }
    /// Where pets can stand: the visible frame extended down to the physical bottom edge, so pets
    /// can sit flush with the bottom of the screen even beside a bottom Dock.
    public static func standingArea(screen: CGRect, visible: CGRect) -> CGRect {
        CGRect(x: visible.minX, y: screen.minY, width: visible.width, height: visible.maxY-screen.minY)
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
