import SwiftUI
import UIKit
import WebKit
import CoreMotion

struct GameWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "haptics")
        controller.add(context.coordinator, name: "storage")
        // Level progress lives in UserDefaults (the web view's own storage is non-persistent) and is handed to the page before it runs.
        if let saved = UserDefaults.standard.string(forKey: Coordinator.saveKey),
           let data = saved.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
            controller.addUserScript(WKUserScript(
                source: "window.__monkeySave = \(saved);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Lets the page XHR its bundled sound files so they can be decoded into Web Audio buffers.
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        URLCache.shared.removeAllCachedResponses()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        context.coordinator.attach(webView)

        guard let indexURL = bundledIndexURL() else {
            webView.loadHTMLString(Self.missingGameHTML, baseURL: nil)
            return webView
        }

        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "haptics")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "storage")
        coordinator.detach()
    }

    private func bundledIndexURL() -> URL? {
        if let direct = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "web"
        ) {
            return direct
        }

        guard let resources = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: resources,
                includingPropertiesForKeys: nil
              ) else { return nil }

        return enumerator.compactMap { $0 as? URL }.first {
            $0.lastPathComponent == "index.html" &&
            $0.deletingLastPathComponent().lastPathComponent == "web"
        }
    }

    private static let missingGameHTML = """
    <!doctype html><meta name="viewport" content="width=device-width">
    <body style="margin:0;background:#010402;color:#57ff86;font:16px monospace;display:grid;place-items:center;height:100vh;text-align:center">
      <p>MONKEY//TRUBBLE<br><br>Game resources could not be loaded.</p>
    </body>
    """

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private weak var webView: WKWebView?
        private let lightImpact = UIImpactFeedbackGenerator(style: .light)
        private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
        private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
        private let notification = UINotificationFeedbackGenerator()
        private let motionManager = CMMotionManager()
        private var activeObserver: NSObjectProtocol?
        private var inactiveObserver: NSObjectProtocol?
        static let saveKey = "monkeyTrubbleSave"
        private var neutral: (turn: Double, lean: Double)?

        func attach(_ webView: WKWebView) {
            self.webView = webView
            lightImpact.prepare()
            mediumImpact.prepare()
            notification.prepare()
            startMotionUpdates()
            activeObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.webView?.evaluateJavaScript("window.__resumeMonkeyAudio?.()")
                self?.startMotionUpdates()
            }
            inactiveObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.motionManager.stopDeviceMotionUpdates()
            }
        }

        // Tilt comes from the gravity vector (stable upright, flat or anywhere between) and is sent relative to a neutral pose
        // that slowly follows the player's grip, so the shine reacts to movement however the phone is held and never sticks.
        private func startMotionUpdates() {
            guard motionManager.isDeviceMotionAvailable,
                  !motionManager.isDeviceMotionActive else { return }
            neutral = nil
            let interval = 1.0 / 30.0
            let follow = 1 - exp(-interval / 3.0)
            motionManager.deviceMotionUpdateInterval = interval
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let gravity = motion?.gravity else { return }
                let turn = atan2(gravity.x, hypot(gravity.y, gravity.z))
                let lean = atan2(-gravity.y, -gravity.z)
                guard var base = self.neutral else {
                    self.neutral = (turn, lean)
                    return
                }
                let wrap = { (angle: Double) in atan2(sin(angle), cos(angle)) }
                let dTurn = wrap(turn - base.turn)
                let dLean = wrap(lean - base.lean)
                base.turn = wrap(base.turn + dTurn * follow)
                base.lean = wrap(base.lean + dLean * follow)
                self.neutral = base
                let script = String(
                    format: "window.__setMonkeyTilt?.(%.4f,%.4f)",
                    dTurn,
                    dLean
                )
                self.webView?.evaluateJavaScript(script)
            }
        }

        func detach() {
            if let activeObserver {
                NotificationCenter.default.removeObserver(activeObserver)
            }
            if let inactiveObserver {
                NotificationCenter.default.removeObserver(inactiveObserver)
            }
            motionManager.stopDeviceMotionUpdates()
            activeObserver = nil
            inactiveObserver = nil
            webView = nil
        }

        deinit {
            detach()
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "storage", let json = message.body as? String {
                UserDefaults.standard.set(json, forKey: Coordinator.saveKey)
                return
            }
            guard message.name == "haptics", let event = message.body as? String else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch event {
                case "cardFlip":
                    self.lightImpact.impactOccurred(intensity: 0.55)
                    self.lightImpact.prepare()
                case "cardSettle":
                    self.lightImpact.impactOccurred(intensity: 0.3)
                    self.lightImpact.prepare()
                case "cardCaged":
                    self.mediumImpact.impactOccurred(intensity: 0.72)
                    self.mediumImpact.prepare()
                case "pairCleared":
                    self.notification.notificationOccurred(.success)
                    self.notification.prepare()
                case "cardBlocked":
                    self.rigidImpact.impactOccurred(intensity: 0.45)
                    self.rigidImpact.prepare()
                case "cageRattle", "cageRattleSoft":
                    // A quick triple knock, like bars rattling: three rigid taps 60ms apart, fading slightly.
                    let base: CGFloat = event == "cageRattle" ? 0.8 : 0.45
                    for (i, scale) in [1.0, 0.85, 0.7].enumerated() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(i * 60)) {
                            self.rigidImpact.impactOccurred(intensity: base * scale)
                            self.rigidImpact.prepare()
                        }
                    }
                case "cageOverflow":
                    self.notification.notificationOccurred(.error)
                    self.notification.prepare()
                default:
                    break
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url, !url.isFileURL, url.scheme != "about" {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
