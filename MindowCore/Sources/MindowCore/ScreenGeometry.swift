import CoreGraphics

public enum ScreenGeometry {
    /// Converts between Cocoa (NSScreen, bottom-left origin) and Accessibility
    /// (AXUIElement, top-left origin) global coordinates.
    ///
    /// Both systems anchor to the primary screen (the one with the menu bar),
    /// so flipping around its height is enough for every display. The mapping
    /// is its own inverse, which is why one function serves both directions.
    /// Keep every coordinate conversion in this function only.
    public static func flipped(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
