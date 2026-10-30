import Foundation
import MetricKit
import os
import StateReporting
import WebKit

/// Performance data for the game page (Apple's perf talk, Paul 2026-10-29).
///
/// Signposts: the page's perf.begin/end (index.html) arrive as {op:"begin"|"end", name, id} and become OSSignposter intervals in
/// the Points of Interest category, so an Instruments trace (⌘I → Time Profiler) shows bars like "startLevel" or
/// "levelTransition" next to the Hangs row. {op:"event"} (a hang the page caught, a fake hang) becomes a point event.
///
/// States: {op:"state", feature, label} is the mode the game is in ("mode" = home/playing/won/failed/map/tutorial) and which FX
/// switches are off ("fx"). It's a signpost event on every iOS version, and on iOS 27 a StateReporting transition, so MetricKit
/// splits its numbers by mode and FX setup instead of one total for the day.
///
/// The page's JavaScript runs in WebKit's own process, so MetricKit's hang numbers are the app's native side (launch, ads,
/// Game Center); the page's hang detector (dev tools) covers the game code.
final class PerfBridge {
    static let shared = PerfBridge()

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.paulfisher.MonkeyTrubble"
    static let stateDomains = ["mode", "fx"].map { "\(subsystem).\($0)" }

    private let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
    private var intervals: [Int: OSSignpostIntervalState] = [:]

    func handle(_ body: [String: Any]) {
        switch body["op"] as? String {
        case "begin":
            guard let id = body["id"] as? Int, let name = body["name"] as? String else { return }
            intervals[id] = signposter.beginInterval("Game", id: signposter.makeSignpostID(), "\(name, privacy: .public)")
        case "end":
            // The same name and the state beginInterval returned, so the pair matches in the trace.
            guard let id = body["id"] as? Int, let state = intervals.removeValue(forKey: id) else { return }
            signposter.endInterval("Game", state)
        case "event":
            let name = body["name"] as? String ?? "", info = body["info"] as? String ?? ""
            signposter.emitEvent("Game", "\(name, privacy: .public) \(info, privacy: .public)")
        case "state":
            guard let feature = body["feature"] as? String, let label = body["label"] as? String else { return }
            signposter.emitEvent("State", "\(feature, privacy: .public)=\(label, privacy: .public)")
            if #available(iOS 27.0, *) {
                StateReporter<Never, Never>.reporter(for: "\(Self.subsystem).\(feature)").reportTransition(to: label)
            }
        default:
            break
        }
    }
}

/// MetricKit reports, kept on this device only (nothing is uploaded, so the privacy policy is unchanged). Each daily metrics
/// report and each diagnostic (hang, crash, disk writes...) is saved as JSON in Documents/metrickit, newest 20 kept. Dev tools'
/// COPY PERF LOG asks for them ({op:"metrics"} on the perf handler). To test without waiting a day: Xcode → Debug → Simulate
/// MetricKit Payloads while the app runs.
final class MetricsStore: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricsStore()

    private let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("metrickit", isDirectory: true)
    private var manager: AnyObject?

    func start() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if #available(iOS 27.0, *) {
            // iOS 27: reports broken down by the page's mode and FX states (PerfBridge).
            let manager = MetricManager(enabledStateReportingDomains: Set(PerfBridge.stateDomains.map(StateReportingDomain.init(rawValue:))))
            self.manager = manager
            Task.detached { [weak self] in for await report in manager.metricReports { self?.save(report, kind: "metrics") } }
            Task.detached { [weak self] in for await report in manager.diagnosticReports { self?.save(report, kind: "diagnostics") } }
        } else {
            MXMetricManager.shared.add(self)
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads { write(payload.jsonRepresentation(), kind: "metrics") }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads { write(payload.jsonRepresentation(), kind: "diagnostics") }
    }

    private func save<Report: Encodable>(_ report: Report, kind: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(report) { write(data, kind: kind) }
    }

    private func write(_ data: Data, kind: String) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? data.write(to: folder.appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(4))-\(kind).json"))
        let old = files().dropLast(20)
        for url in old { try? FileManager.default.removeItem(at: url) }
    }

    private func files() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The newest reports as a JSON array of {file, report}, for the page's perf log.
    func latestJSON(limit: Int = 4) -> String {
        let entries: [[String: Any]] = files().suffix(limit).reversed().compactMap { url in
            guard let data = try? Data(contentsOf: url), let report = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return ["file": url.lastPathComponent, "report": report]
        }
        let data = (try? JSONSerialization.data(withJSONObject: entries)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
