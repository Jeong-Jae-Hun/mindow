import AppKit
import MindowCore
import Observation

/// Asks GitHub for the latest release at launch and once a day after that, and keeps
/// the result for the menu and Settings. Any failure (offline, rate limit, odd JSON)
/// leaves it empty without telling anyone: a missed notice costs nothing.
@MainActor @Observable
final class UpdateChecker {
    private(set) var available: LatestRelease?

    private static let endpoint = URL(string: "https://api.github.com/repos/Jeong-Jae-Hun/mindow/releases/latest")
    /// Ephemeral with no cookie store or cache: the request carries nothing that
    /// could tell one Mac from another.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()

    /// Hourly wake-ups decide by the stored last check, so a Mac that slept through
    /// the 24 hours checks soon after waking, and a relaunch doesn't check again early.
    /// An offline launch therefore waits a day too, as a failed check does.
    func start() {
        Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    /// Also called when the Settings toggle changes, so turning it off hides the notice
    /// right away and turning it on checks if a check is due.
    func refresh() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Preferences.checkForUpdates) else {
            available = nil
            return
        }
        let lastCheck = defaults.object(forKey: Preferences.lastUpdateCheck) as? Date
        guard UpdateSchedule.isDue(lastCheck: lastCheck, now: .now), let endpoint = Self.endpoint,
              let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { return }
        // Recorded before the request, so a failed one also waits a day, and a second
        // call while this one is out (toggle plus hourly wake-up) finds nothing due.
        defaults.set(Date.now, forKey: Preferences.lastUpdateCheck)
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await Self.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = LatestRelease(json: data)
        else { return }
        let newer = latest.isNewer(than: current) ? latest : nil
        // The toggle may have been turned off while the request was out.
        if defaults.bool(forKey: Preferences.checkForUpdates), newer != available {
            available = newer
        }
    }
}
