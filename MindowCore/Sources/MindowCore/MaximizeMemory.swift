import CoreGraphics

/// Per-window frame from right before Fullscreen, so pressing Fullscreen again on a
/// window that still fills the screen puts it back.
public struct MaximizeMemory<Key: Hashable> {
    private var frames: [Key: CGRect] = [:]

    public init() {}

    /// Call after Fullscreen actually changed the frame, with the frame it left.
    /// A later Fullscreen from another place overwrites it.
    public mutating func remember(_ previous: CGRect, for key: Key) {
        frames[key] = previous
    }

    /// The frame to go back to, or nil when nothing is remembered or the window no
    /// longer sits at `position.fullscreen` (moved since). Call `forget` once the window got
    /// there, so a failed restore can be tried again.
    public func restoreFrame(for key: Key, at position: (current: CGRect, fullscreen: CGRect)) -> CGRect? {
        guard WindowLayout.isClose(position.current, position.fullscreen) else { return nil }
        return frames[key]
    }

    public mutating func forget(_ key: Key) {
        frames[key] = nil
    }
}
