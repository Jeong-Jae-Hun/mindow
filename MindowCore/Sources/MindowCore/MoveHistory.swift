import CoreGraphics

/// Per-window undo/redo stacks of frames.
public struct MoveHistory<Key: Hashable> {
    /// Older entries are dropped so long sessions do not grow without bound.
    static var limit: Int { 20 }

    private var undoStack: [Key: [CGRect]] = [:]
    private var redoStack: [Key: [CGRect]] = [:]

    public init() {}

    /// Call before a move with the frame the window is leaving.
    public mutating func record(_ previous: CGRect, for key: Key) {
        undoStack[key, default: []].append(previous)
        undoStack[key] = Array(undoStack[key, default: []].suffix(Self.limit))
        redoStack[key] = nil
    }

    public mutating func undo(for key: Key, current: CGRect) -> CGRect? {
        guard let frame = undoStack[key]?.popLast() else { return nil }
        redoStack[key, default: []].append(current)
        return frame
    }

    public mutating func redo(for key: Key, current: CGRect) -> CGRect? {
        guard let frame = redoStack[key]?.popLast() else { return nil }
        undoStack[key, default: []].append(current)
        return frame
    }
}
