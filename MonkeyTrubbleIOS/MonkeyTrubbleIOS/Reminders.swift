import UIKit
import WebKit
import BackgroundTasks
@preconcurrency import UserNotifications

/// Streak reminders (1.1), the iPhone twin of the Android app's Reminders.kt. The page decides everything (which days, which silly
/// line) and posts {op, on, time, items:[{slot, at (ms), title, body}]} on the "reminders" handler; this replaces every pending
/// reminder with that list. op "ask" means the player turned REMINDERS on in Settings, the only time the system pop-up may show.
/// Otherwise a new install is asked quietly (provisional: Notification Center only, no pop-up), and nothing else ever prompts.
/// The on/off and time live here in UserDefaults, per device, not in the iCloud save, because permission is per device. The page
/// gets them at launch as window.__monkeyRemind and hears back through window.__monkeyReminders({status, asked}), status being
/// on, quiet (provisional), off or denied.
@MainActor
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    private weak var webView: WKWebView?
    private static let onKey = "reminders.on"
    private static let timeKey = "reminders.time"

    struct Item: Sendable {
        let slot: Int
        let at: Date
        let title: String
        let body: String
    }

    /// The week's ids; only these are replaced, so a dev test reminder survives a sync.
    private static let weekIDs = (0..<7).map { "reminder-\($0)" }
    nonisolated private static let testID = "reminder-test"

    func attach(_ webView: WKWebView) {
        self.webView = webView
        UNUserNotificationCenter.current().delegate = self
    }

    /// iOS hides notifications while the app is open; the dev test shows anyway, real reminders don't (you're already playing).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(notification.request.identifier == Self.testID ? [.banner, .list, .sound] : [])
    }

    /// Dev tools TEST: {op:'test', delay (s), title, body}. Asks for full permission if needed, then counts the delay from there,
    /// so time spent on the pop-up doesn't eat it. Answers window.__monkeyReminderTest(status). Leaves REMINDERS as it is.
    private func test(_ body: [String: Any]) {
        // TEST NEWS (dev): the friends news line instead, fetched now the same way the background refresh does (silly line if none).
        if let cfg = body["news"] as? [String: Any] {
            var plain = body
            plain.removeValue(forKey: "news")
            let sendable = plain as NSDictionary
            NewsRefresh.fetchLine(cfg) { line in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        var b = sendable as? [String: Any] ?? [:]
                        if let line { b["body"] = line }
                        self.test(b)
                    }
                }
            }
            return
        }
        let delay = max(1, (body["delay"] as? NSNumber)?.doubleValue ?? 10)
        let title = body["title"] as? String ?? "Monkey Trubble"
        let text = body["body"] as? String ?? ""
        let center = UNUserNotificationCenter.current()
        let fire: @Sendable (String) -> Void = { status in
            if status == "on" || status == "quiet" {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = text
                content.sound = .default
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.testID, content: content,
                                                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { _ = self.webView?.evaluateJavaScript("window.__monkeyReminderTest?.('\(status)')") }
            }
        }
        let name: @Sendable (UNAuthorizationStatus) -> String = {
            switch $0 {
            case .authorized, .ephemeral: return "on"
            case .provisional: return "quiet"
            case .denied: return "denied"
            default: return "off"
            }
        }
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            guard status == .notDetermined || status == .provisional else { fire(name(status)); return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in
                center.getNotificationSettings { fire(name($0.authorizationStatus)) }
            }
        }
    }

    /// Runs before the page: on is null until this device has ever synced (the page then picks: ON for a new install, OFF otherwise).
    static var startScript: String {
        let defaults = UserDefaults.standard
        let on = defaults.object(forKey: onKey) == nil ? "null" : (defaults.bool(forKey: onKey) ? "true" : "false")
        let time = defaults.string(forKey: timeKey).flatMap { $0.range(of: #"^\d\d:\d\d$"#, options: .regularExpression) != nil ? $0 : nil } ?? "19:00"
        return "window.__monkeyRemind={on:\(on),time:'\(time)'};"
    }

    func handle(_ body: [String: Any]) {
        if body["op"] as? String == "test" { test(body); return }
        let ask = body["op"] as? String == "ask"
        let on = body["on"] as? Bool ?? false
        if let time = body["time"] as? String { UserDefaults.standard.set(time, forKey: Self.timeKey) }
        let items: [Item] = (body["items"] as? [[String: Any]] ?? []).compactMap { item in
            guard let slot = (item["slot"] as? NSNumber)?.intValue, let at = (item["at"] as? NSNumber)?.doubleValue,
                  let title = item["title"] as? String, let text = item["body"] as? String else { return nil }
            return Item(slot: slot, at: Date(timeIntervalSince1970: at / 1000), title: title, body: text)
        }
        // Friends news settings for the background refresh (NewsRefresh), or none (reminders off, or no friends yet).
        NewsRefresh.save(on ? body["news"] as? [String: Any] : nil)
        // A reminder sitting in Notification Center is stale once the game is open.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        guard on else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.weekIDs)
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
            center.removePendingNotificationRequests(withIdentifiers: Self.weekIDs)
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
        center.removePendingNotificationRequests(withIdentifiers: Self.weekIDs)
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

/// Friends news in the daily reminder (Phase B, 2026-11-17). iOS can't push without a server, so a background refresh, which iOS runs
/// when it sees fit, asks for my_news a few hours before the reminder. If there's news (a nudge, a finished or growing shared puzzle,
/// a friend request, someone passing you), today's pending reminder is replaced with the same time and a news line. Otherwise
/// nothing changes. The page sends the server details and the lines in the player's language (reminderNews in index.html). There's
/// no reminder pending on a day the player has played, so there's nothing to rewrite then: still at most one a day, never after playing.
enum NewsRefresh {
    static let taskID = "com.paulfisher.MonkeyTrubble.news"
    private static let configKey = "reminders.news"

    /// Called from the app's init: the handler has to be registered before launch ends.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            run(task)
        }
    }

    static func save(_ config: [String: Any]?) {
        if let config, let data = try? JSONSerialization.data(withJSONObject: config) {
            UserDefaults.standard.set(data, forKey: configKey)
            schedule()
        } else {
            UserDefaults.standard.removeObject(forKey: configKey)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
        }
    }

    private static var config: [String: Any]? {
        guard let data = UserDefaults.standard.data(forKey: configKey) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Next run: three hours before the reminder time (today's if that's still ahead, else tomorrow's). iOS may run it later.
    static func schedule() {
        guard config != nil else { return }
        let time = UserDefaults.standard.string(forKey: "reminders.time") ?? "19:00"
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let calendar = Calendar.current
        var at = calendar.date(bySettingHour: parts.first ?? 19, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: Date()) ?? Date()
        at = at.addingTimeInterval(-3 * 3600)
        if at < Date() { at = Date().addingTimeInterval(15 * 60) }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = at
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func run(_ task: BGAppRefreshTask) {
        // The next one is booked first, so a run that fails or is cut short doesn't end the chain.
        schedule()
        guard let cfg = config else { task.setTaskCompleted(success: true); return }
        let job = fetchLine(cfg) { line in
            guard let line else { task.setTaskCompleted(success: true); return }
            rewriteToday(line) { task.setTaskCompleted(success: true) }
        }
        task.expirationHandler = { job?.cancel() }
    }

    /// Asks the server for my_news and picks the line (nil: no news, or no answer).
    @discardableResult
    static func fetchLine(_ cfg: [String: Any], done: @escaping @Sendable (String?) -> Void) -> URLSessionDataTask? {
        guard let base = cfg["url"] as? String, let key = cfg["key"] as? String, let id = cfg["id"] as? String,
              let secret = cfg["secret"] as? String, let t = cfg["t"] as? [String: Any],
              let url = URL(string: "\(base)/rest/v1/rpc/my_news") else { done(nil); return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        if key.hasPrefix("eyJ") { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["p_id": id, "p_secret": secret, "p_mark": false])
        let tSend = t as NSDictionary
        let job = URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data, let news = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { done(nil); return }
            done(line(news, tSend as? [String: Any] ?? [:]))
        }
        job.resume()
        return job
    }

    /// The most personal news first: a nudge, your shared puzzle finished or growing, a friend request, a shared puzzle invite, being passed.
    static func line(_ n: [String: Any], _ t: [String: Any]) -> String? {
        func fill(_ key: String, _ args: String...) -> String? {
            guard var s = t[key] as? String else { return nil }
            for (i, a) in args.enumerated() { s = s.replacingOccurrences(of: "{\(i)}", with: a) }
            return s
        }
        if let nudge = (n["nudges"] as? [[String: Any]])?.first, let name = nudge["name"] as? String {
            let lines = t["lines"] as? [String] ?? []
            let i = (nudge["line"] as? NSNumber)?.intValue ?? 0
            return fill("nudge", name, lines.indices.contains(i) ? lines[i] : (lines.first ?? ""))
        }
        if let duo = n["duo"] as? [String: Any], let name = duo["name"] as? String {
            if duo["done"] as? Bool == true { return fill("duoDone", name) }
            if ((duo["found"] as? NSNumber)?.intValue ?? 0) + ((duo["placed"] as? NSNumber)?.intValue ?? 0) > 0 { return fill("duo", name) }
        }
        if ((n["requests"] as? NSNumber)?.intValue ?? 0) > 0 {
            if let name = (n["request_names"] as? [String])?.first { return fill("request", name) }
            return fill("requestAny")
        }
        if ((n["duo_invites"] as? NSNumber)?.intValue ?? 0) > 0 { return fill("duoInvite") }
        if let p = (n["passed"] as? [[String: Any]])?.first, let name = p["name"] as? String { return fill("passed", name) }
        return nil
    }

    /// Today's pending reminder (if any) gets the news line, keeping its time, title and id.
    private static func rewriteToday(_ line: String, done: @escaping @Sendable () -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let calendar = Calendar.current
            guard let today = requests.first(where: { r in
                guard r.identifier.hasPrefix("reminder-"), r.identifier != "reminder-test",
                      let when = (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() else { return false }
                return calendar.isDateInToday(when)
            }), let trigger = today.trigger else { done(); return }
            let content = UNMutableNotificationContent()
            content.title = today.content.title
            content.body = line
            content.sound = .default
            center.add(UNNotificationRequest(identifier: today.identifier, content: content, trigger: trigger)) { _ in done() }
        }
    }
}
