import ApplicationServices

/// A yes/no window attribute read through the Accessibility API, such as AXMinimized
/// or AXFullScreen.
public enum AXFlag {
    /// The flag a read gives, or nil when the read failed. Many windows have no
    /// AXFullScreen (panels, apps without native full screen) and answer
    /// `.attributeUnsupported` or `.noValue`: that is a plain no, as is an answer
    /// that isn't a Bool. Only an app that didn't answer (`.cannotComplete`, also
    /// what a messaging timeout gives), a window that is gone (`.invalidUIElement`)
    /// or any other error is a failure, so the caller doesn't wait on that app again.
    public static func value(_ result: AXError, _ raw: CFTypeRef?) -> Bool? {
        switch result {
        case .success: (raw as? Bool) ?? false
        case .attributeUnsupported, .noValue: false
        default: nil
        }
    }
}
