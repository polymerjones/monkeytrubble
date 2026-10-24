import SwiftUI
import UIKit
import WebKit
import CoreMotion
import AVFoundation

/// Same near-black green as the launch screen and the page's loading screen, so launch → web view → loader shows no black flash.
let launchBackground = UIColor(named: "LaunchBackground") ?? .black

struct GameWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "haptics")
        controller.add(context.coordinator, name: "storage")
        controller.add(context.coordinator, name: "gameCenter")
        controller.add(context.coordinator, name: "motion")
        controller.add(context.coordinator, name: "ads")
        controller.add(context.coordinator, name: "share")
        controller.add(context.coordinator, name: "screen")
        // Debug builds (Xcode / ship) keep the page's dev mode on; Release builds (TestFlight, App Store) turn it off.
        #if DEBUG
        let debugBuild = true
        #else
        let debugBuild = false
        #endif
        // __monkeyAds turns on the page's real rewarded ads (Ads.swift).
        // The hidden dev mode (three taps on the home logo) works in Debug builds only. Not in TestFlight either: App Review installs
        // builds the same way TestFlight does, and guideline 2.3.1 forbids hidden features.
        controller.addUserScript(WKUserScript(
            source: "window.__monkeyDebugBuild = \(debugBuild); window.__monkeyDevTaps = \(debugBuild); window.__monkeyAds = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        // Level progress lives in UserDefaults and iCloud (the web view's own storage is non-persistent); both copies are handed to
        // the page before it runs, and the page merges them.
        let services = context.coordinator.services
        for (name, save) in [("__monkeySave", services.localSave), ("__monkeyCloudSave", services.cloudSave)] {
            guard let save else { continue }
            controller.addUserScript(WKUserScript(
                source: "window.\(name) = \(save);",
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
        // No text selection anywhere in the game: this is what stops the long-press magnifier (the CSS user-select alone doesn't).
        configuration.preferences.isTextInteractionEnabled = false

        URLCache.shared.removeAllCachedResponses()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = launchBackground
        webView.scrollView.backgroundColor = launchBackground
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
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
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "gameCenter")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "motion")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "ads")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "share")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "screen")
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

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let services = GameServices()
        let ads = Ads()
        private var consentAsked = false
        private weak var webView: WKWebView?
        private let lightImpact = UIImpactFeedbackGenerator(style: .light)
        private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
        private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
        private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
        private let notification = UINotificationFeedbackGenerator()
        private let motionManager = CMMotionManager()
        private var activeObserver: NSObjectProtocol?
        private var inactiveObserver: NSObjectProtocol?
        private var interruptionObserver: NSObjectProtocol?
        private var backgroundObserver: NSObjectProtocol?
        private var neutral: (turn: Double, lean: Double)?
        private var lastSent: (turn: Double, lean: Double)?
        /// The page says when tilt shows on screen (the board, Settings, the lightbox); nil until it first says, so older pages keep motion on.
        private var pageWantsMotion: Bool?

        func attach(_ webView: WKWebView) {
            self.webView = webView
            services.attach(webView)
            ads.attach(webView)
            lightImpact.prepare()
            mediumImpact.prepare()
            notification.prepare()
            startMotionUpdates()
            activeObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    MonkeyTrubbleApp.activateAudio()
                    // Undo the background suspend below, then let the page fade its sound back in.
                    self?.webView?.setAllMediaPlaybackSuspended(false) { [weak self] in
                        self?.webView?.evaluateJavaScript("window.__resumeMonkeyAudio?.()")
                    }
                    if self?.pageWantsMotion != false { self?.startMotionUpdates() }
                }
            }
            // A call, Siri or another app's audio interrupted the game: when it ends, take the session back and restart the engine.
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
                MainActor.assumeIsolated {
                    MonkeyTrubbleApp.activateAudio()
                    self?.webView?.evaluateJavaScript("window.__resumeMonkeyAudio?.(true)")
                }
            }
            // In the background nothing of the game should run (2026-10-24 audit): media suspended, the audio session let go, no tilt.
            backgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.motionManager.stopDeviceMotionUpdates()
                    self?.webView?.setAllMediaPlaybackSuspended(true, completionHandler: nil)
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
            }
            inactiveObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.motionManager.stopDeviceMotionUpdates()
                    // Fade the game's sound out now, while the page still runs; cutting it off mid-sound buzzes.
                    self?.webView?.evaluateJavaScript("window.__quietMonkeyAudio?.()")
                }
            }
        }

        // Tilt comes from the gravity vector (stable upright, flat or anywhere between) and is sent relative to a neutral pose
        // that slowly follows the player's grip, so the shine reacts to movement however the phone is held and never sticks.
        private func startMotionUpdates() {
            guard motionManager.isDeviceMotionAvailable,
                  !motionManager.isDeviceMotionActive else { return }
            neutral = nil
            lastSent = nil
            let interval = 1.0 / 24.0
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
                // Skip hand tremor (under ~0.35°) so a phone held still stops waking the web view; deliberate tilts still come through.
                if let last = self.lastSent, abs(dTurn - last.turn) + abs(dLean - last.lean) < 0.006 { return }
                self.lastSent = (dTurn, dLean)
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
            if let interruptionObserver {
                NotificationCenter.default.removeObserver(interruptionObserver)
            }
            if let backgroundObserver {
                NotificationCenter.default.removeObserver(backgroundObserver)
            }
            motionManager.stopDeviceMotionUpdates()
            services.detach()
            ads.detach()
            activeObserver = nil
            inactiveObserver = nil
            interruptionObserver = nil
            backgroundObserver = nil
            webView = nil
        }

        private func presentShare(_ image: UIImage) {
            var top = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
                .first
            while let presented = top?.presentedViewController { top = presented }
            guard let top else { return }
            let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            // iPad shows the sheet as a popover; anchor it mid-screen.
            sheet.popoverPresentationController?.sourceView = top.view
            sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            sheet.popoverPresentationController?.permittedArrowDirections = []
            top.present(sheet, animated: true)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "storage", let json = message.body as? String {
                services.store(json)
                return
            }
            if message.name == "gameCenter", let body = message.body as? [String: Any] {
                services.handle(body)
                return
            }
            if message.name == "ads", let body = message.body as? [String: Any] {
                ads.handle(body)
                return
            }
            // A finished jigsaw (Paul, 2026-10-24): the page sends {image: PNG data URL}; the share sheet offers Save Image, Messages...
            if message.name == "share", let body = message.body as? [String: Any],
               let url = body["image"] as? String, let comma = url.firstIndex(of: ","),
               let data = Data(base64Encoded: String(url[url.index(after: comma)...])), let image = UIImage(data: data) {
                presentShare(image)
                return
            }
            // The page keeps the screen awake only during play (see syncAwake in index.html).
            if message.name == "screen", let on = message.body as? Bool {
                UIApplication.shared.isIdleTimerDisabled = on
                return
            }
            if message.name == "motion", let on = message.body as? Bool {
                pageWantsMotion = on
                if on {
                    if UIApplication.shared.applicationState == .active { startMotionUpdates() }
                } else {
                    motionManager.stopDeviceMotionUpdates()
                }
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
                case "rankPass":
                    // Leaderboard climb: a tick each time the player's row moves past another player.
                    self.mediumImpact.impactOccurred(intensity: 0.6)
                    self.mediumImpact.prepare()
                case "jokerSlam":
                    // The joker slams down on his pair: one heavy thud, then a softer rebound.
                    self.heavyImpact.impactOccurred(intensity: 1.0)
                    self.heavyImpact.prepare()
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(90)) {
                        self.rigidImpact.impactOccurred(intensity: 0.5)
                        self.rigidImpact.prepare()
                    }
                case "rankClimb":
                    self.notification.notificationOccurred(.success)
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

        // Consent is asked once the game is on screen (the form needs a window to present from); every page load hears whether
        // Settings needs the "Ad privacy choices" row.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if consentAsked {
                ads.announcePrivacyOptions()
            } else {
                consentAsked = true
                ads.gatherConsent()
            }
        }
    }
}
