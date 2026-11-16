import Foundation

/// What a `mindow://` URL asks for. Only window moves exist: no URL changes a setting
/// or writes a file, so any page or app that can open a URL can't reach more than a
/// shortcut can.
public enum URLCommand: Equatable, Sendable {
    /// `mindow://action/MoveToLeftHalf`
    case action(WindowAction)
    /// `mindow://layout/<name>`, percent-encoded as URLs require (`코딩` →
    /// `%EC%BD%94%EB%94%A9`). The name is kept exactly; layouts decide how to match it.
    case layout(String)

    /// Nil for anything else: another scheme or host, a user, password or port, no name
    /// or more than one path component, a query or fragment, or an action name Mindow doesn't have. The scheme
    /// and host match in any case, as URLs do. Action names do too, so a hand-typed
    /// `mindow://action/movetolefthalf` works; no two raw values differ only in case.
    public init?(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "mindow",
              components.query == nil, components.fragment == nil,
              components.user == nil, components.password == nil, components.port == nil,
              let host = components.host?.lowercased()
        else { return nil }
        // Split before decoding, so an encoded slash (`%2F`) stays inside a layout name.
        // Only `/name` and `/name/` pass; empty components elsewhere make it malformed.
        var path = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        if path.count == 3, path[2].isEmpty { path.removeLast() }
        guard path.count == 2, path[0].isEmpty, let name = path[1].removingPercentEncoding, !name.isEmpty else { return nil }
        switch host {
        case "action":
            guard let action = WindowAction.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) else { return nil }
            self = .action(action)
        case "layout":
            self = .layout(name)
        default:
            return nil
        }
    }
}
