import CoreGraphics

/// The connected displays as a key for remembered window frames: each display's UUID
/// and pixel size, in a fixed order, so the same monitors plugged in again give the
/// same key whatever order the system lists them in. A resolution change makes another
/// key, since frames recorded for the old one may not fit.
public struct DisplayConfiguration: Hashable, Sendable {
    public struct Display: Hashable, Sendable {
        public var uuid: String
        public var width: Int
        public var height: Int

        public init(uuid: String, width: Int, height: Int) {
            self.uuid = uuid
            self.width = width
            self.height = height
        }
    }

    public let displays: [Display]

    public init(_ displays: [Display]) {
        self.displays = displays.sorted { ($0.uuid, $0.width, $0.height) < ($1.uuid, $1.width, $1.height) }
    }
}

/// Window frames remembered per display configuration, in memory only, so plugging a
/// monitor back in can put windows where they were with it. Frames are kept per owner
/// (an app) so a recording pass replaces one app's windows at a time, and an app that
/// didn't answer keeps what was recorded before.
///
/// Recording only goes to the configuration in effect. From the moment the displays
/// change until the windows are restored on the new configuration (`resume`), nothing
/// is recorded: windows the system is shuffling around, or restoring is moving, would
/// otherwise overwrite the frames to restore.
public struct DisplayMemory<Owner: Hashable, Window: Hashable> {
    public private(set) var current: DisplayConfiguration
    public private(set) var isSettling = false
    private var frames: [DisplayConfiguration: [Owner: [Window: CGRect]]] = [:]

    public init(current: DisplayConfiguration) {
        self.current = current
    }

    /// Replaces `owner`'s windows for `configuration`, the one in effect when they were
    /// read. Ignored while settling or when that is no longer `current`, which also
    /// covers a change whose notification hasn't arrived yet. False when ignored.
    @discardableResult
    public mutating func record(_ windows: [Window: CGRect], of owner: Owner, in configuration: DisplayConfiguration) -> Bool {
        guard !isSettling, configuration == current else { return false }
        frames[configuration, default: [:]][owner] = windows
        return true
    }

    /// The displays changed: stop recording until `resume`.
    public mutating func displaysChanged() {
        isSettling = true
    }

    /// The displays stopped changing on `configuration`: it becomes current, and the
    /// frames remembered for it come back to restore (empty for a configuration not seen
    /// before). Recording stays stopped until `resume`, after the restore.
    public mutating func settle(on configuration: DisplayConfiguration) -> [Owner: [Window: CGRect]] {
        current = configuration
        return frames[configuration] ?? [:]
    }

    /// The restore is done; record again, on `current`.
    public mutating func resume() {
        isSettling = false
    }

    /// Drops an owner's windows from every configuration, for an app that quit.
    public mutating func forget(_ owner: Owner) {
        for configuration in frames.keys {
            frames[configuration]?[owner] = nil
        }
    }
}
