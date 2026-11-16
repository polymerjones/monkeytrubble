import UIKit
import WebKit
import UserNotifications

/// Streak reminders (1.1), the iPhone twin of the Android app's Reminders.kt. The page decides everything (which days, which silly
/// line) and posts {op, on, time, items:[{slot, at (ms), title, body}]} on the "reminders" handler; this replaces every pending
/// reminder with that list. op "ask" means the player turned REMINDERS on in Settings, the only time the system pop-up may show.
/// Otherwise a new install is asked quietly (provisional: Notification Center only, no pop-up), and nothing else ever prompts.
/// The on/off and time live here in UserDefaults, per device, not in the iCloud save, because permission is per device. The page
/// gets them at launch as window.__monkeyRemind and hears back through window.__monkeyReminders({status, asked}), status being
/// on, quiet (provisional), off or denied.
@MainActor
final class Reminders {
    private weak var webView: WKWebView?
    private static let onKey = "reminders.on"
    private static let timeKey = "reminders.time"

    struct Item: Sendable {
        let slot: Int
        let at: Date
        let title: String
        let body: String
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    /// Runs before the page: on is null until this device has ever synced (the page then picks: ON for a new install, OFF otherwise).
    static var startScript: String {
        let defaults = UserDefaults.standard
        let on = defaults.object(forKey: onKey) == nil ? "null" : (defaults.bool(forKey: onKey) ? "true" : "false")
        let time = defaults.string(forKey: timeKey).flatMap { $0.range(of: #"^\d\d:\d\d$"#, options: .regularExpression) != nil ? $0 : nil } ?? "19:00"
        return "window.__monkeyRemind={on:\(on),time:'\(time)'};"
    }

    func handle(_ body: [String: Any]) {
        let ask = body["op"] as? String == "ask"
        let on = body["on"] as? Bool ?? false
        if let time = body["time"] as? String { UserDefaults.standard.set(time, forKey: Self.timeKey) }
        let items: [Item] = (body["items"] as? [[String: Any]] ?? []).compactMap { item in
            guard let slot = (item["slot"] as? NSNumber)?.intValue, let at = (item["at"] as? NSNumber)?.doubleValue,
                  let title = item["title"] as? String, let text = item["body"] as? String else { return nil }
            return Item(slot: slot, at: Date(timeIntervalSince1970: at / 1000), title: title, body: text)
        }
        // A reminder sitting in Notification Center is stale once the game is open.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        guard on else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            finish("off", asked: ask)
            return
        }
        apply(items, ask: ask, mayRequest: true)
    }

    private func apply(_ items: [Item], ask: Bool, mayRequest: Bool) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.decide(status, items: items, ask: ask, mayRequest: mayRequest) }
            }
        }
    }

    private func decide(_ status: UNAuthorizationStatus, items: [Item], ask: Bool, mayRequest: Bool) {
        let center = UNUserNotificationCenter.current()
        switch status {
        case .authorized, .ephemeral:
            schedule(items)
            finish("on", asked: ask)
        case .provisional where ask && mayRequest:
            // Quiet so far and the player asked for more: the real pop-up, then look again.
            request([.alert, .sound], items: items, ask: ask)
        case .provisional:
            schedule(items)
            finish("quiet", asked: ask)
        case .notDetermined where mayRequest:
            request(ask ? [.alert, .sound] : [.alert, .sound, .provisional], items: items, ask: ask)
        case .denied, .notDetermined:
            center.removeAllPendingNotificationRequests()
            finish(status == .denied ? "denied" : "off", asked: ask)
        @unknown default:
            finish("off", asked: ask)
        }
    }

    private func request(_ options: UNAuthorizationOptions, items: [Item], ask: Bool) {
        UNUserNotificationCenter.current().requestAuthorization(options: options) { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apply(items, ask: ask, mayRequest: false) }
            }
        }
    }

    private func schedule(_ items: [Item]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let calendar = Calendar.current
        for item in items where item.at > Date() {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let when = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.at)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            center.add(UNNotificationRequest(identifier: "reminder-\(item.slot)", content: content, trigger: trigger))
        }
    }

    private func finish(_ status: String, asked: Bool) {
        UserDefaults.standard.set(status == "on" || status == "quiet", forKey: Self.onKey)
        webView?.evaluateJavaScript("window.__monkeyReminders?.({status:'\(status)',asked:\(asked)})")
    }
}
