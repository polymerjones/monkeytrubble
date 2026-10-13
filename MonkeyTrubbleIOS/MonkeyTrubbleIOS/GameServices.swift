import GameKit
import UIKit
import WebKit

/// iCloud save sync and Game Center for the game page.
///
/// Save: the page's progress JSON is kept in UserDefaults (this device) and in the iCloud key-value store (every device on the
/// player's Apple ID). Both copies are handed to the page at launch and the page merges them (mergeSaves in index.html). When
/// another device updates the iCloud copy, it's passed to window.__monkeyCloudChanged.
///
/// Game Center: signs the player in at launch (the system banner, or Apple's sign-in sheet the first time), tells the page their
/// nickname (window.__gameCenterReady), submits leaderboard scores the page sends, and shows the Game Center access point while
/// the page asks for it (the home screen).
@MainActor
final class GameServices {
    static let saveKey = "monkeyTrubbleSave"

    private let cloud = NSUbiquitousKeyValueStore.default
    private weak var webView: WKWebView?
    private var cloudObserver: NSObjectProtocol?
    private var wantsAccessPoint = false

    var localSave: String? { Self.validSave(UserDefaults.standard.string(forKey: Self.saveKey)) }
    var cloudSave: String? { Self.validSave(cloud.string(forKey: Self.saveKey)) }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        cloud.synchronize()
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let json = self.cloudSave else { return }
                self.webView?.evaluateJavaScript("window.__monkeyCloudChanged?.(\(json))")
            }
        }
        authenticate()
    }

    func detach() {
        if let cloudObserver {
            NotificationCenter.default.removeObserver(cloudObserver)
        }
        cloudObserver = nil
        webView = nil
    }

    /// Saves on this device and in iCloud. The save is a few KB, well under the key-value store's 1 MB limit.
    func store(_ json: String) {
        UserDefaults.standard.set(json, forKey: Self.saveKey)
        cloud.set(json, forKey: Self.saveKey)
    }

    /// The page's "gameCenter" messages: {type:'score', leaderboard, value} and {type:'accessPoint', show}.
    func handle(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "score":
            guard GKLocalPlayer.local.isAuthenticated,
                  let id = body["leaderboard"] as? String,
                  let value = (body["value"] as? NSNumber)?.intValue else { return }
            GKLeaderboard.submitScore(value, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [id]) { _ in }
        case "accessPoint":
            wantsAccessPoint = body["show"] as? Bool ?? false
            if GKLocalPlayer.local.isAuthenticated {
                GKAccessPoint.shared.isActive = wantsAccessPoint
            }
        default:
            break
        }
    }

    private func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let viewController {
                    self.present(viewController)
                    return
                }
                let player = GKLocalPlayer.local
                guard player.isAuthenticated else { return }
                GKAccessPoint.shared.location = .bottomLeading
                GKAccessPoint.shared.isActive = self.wantsAccessPoint
                guard let data = try? JSONSerialization.data(withJSONObject: ["alias": player.alias]),
                      let json = String(data: data, encoding: .utf8) else { return }
                self.webView?.evaluateJavaScript("window.__gameCenterReady?.(\(json))")
            }
        }
    }

    private func present(_ viewController: UIViewController) {
        var top = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        while let presented = top?.presentedViewController {
            top = presented
        }
        top?.present(viewController, animated: true)
    }

    /// Only a JSON object is passed into the page as a script literal.
    private static func validSave(_ json: String?) -> String? {
        guard let json, let data = json.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return nil }
        return json
    }
}
