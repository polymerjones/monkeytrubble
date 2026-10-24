import UIKit
import WebKit
import GoogleMobileAds
import UserMessagingPlatform

/// AdMob rewarded ads for the page's reward buttons (resume, shuffle, undo, Owl Eyes), the iPhone twin of the Android app's Ads.kt.
/// The page posts {type, nonce} on the "ads" handler and gets back window.__monkeyAdResult(nonce, status), status being completed,
/// skipped, failed or unavailable, which is what its requestReward expects. Consent (UMP) is gathered at launch before any ad is
/// requested. The app and rewarded unit IDs come from Info.plist (ADMOB_APP_ID / ADMOB_REWARDED_ID build settings); Debug builds
/// use Google's sample rewarded unit, so test taps never touch the real one.
@MainActor
final class Ads: NSObject, FullScreenContentDelegate {
    private weak var webView: WKWebView?
    private let unitID = Bundle.main.object(forInfoDictionaryKey: "AdMobRewardedID") as? String ?? ""
    private var started = false
    private var ad: RewardedAd?
    // AdMob rewarded ads expire an hour after loading; one kept past maxAge is dropped and a fresh one loaded (a stale one can freeze).
    private var loadedAt = Date.distantPast
    private var loading = false
    private var showing = false
    private var earned = false
    private var showingNonce: String?
    // A tap that arrived while the ad was still loading; it plays once the load finishes or gives up after waitSeconds.
    private var waiting: String?
    private var giveUp: DispatchWorkItem?
    private static let waitSeconds = 8.0
    private static let quietMs = 120
    private static let maxAge: TimeInterval = 55 * 60

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func detach() {
        webView = nil
    }

    /// Asks for consent where the law requires it (EEA, UK, some US states), then starts the SDK. Call once at launch.
    func gatherConsent() {
        let params = RequestParameters()
        #if DEBUG && UMP_EEA_TEST
        // Debug builds with UMP_EEA_TEST in Active Compilation Conditions: start from no answer and pretend to be in the EEA.
        ConsentInformation.shared.reset()
        let debug = DebugSettings()
        debug.geography = .EEA
        params.debugSettings = debug
        #endif
        ConsentInformation.shared.requestConsentInfoUpdate(with: params) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                guard error == nil, let presenter = Self.presenter() else { return self.start() }
                ConsentForm.loadAndPresentIfRequired(from: presenter) { [weak self] _ in
                    Task { @MainActor in
                        self?.announcePrivacyOptions()
                        self?.start()
                    }
                }
            }
        }
        // A consent answer from an earlier launch is enough to start right away.
        start()
    }

    /// Tells the page whether Settings needs the "Ad privacy choices" row. Also called when the page (re)loads.
    func announcePrivacyOptions() {
        let required = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        webView?.evaluateJavaScript("window.__monkeyPrivacyOptions?.(\(required))")
    }

    private func start() {
        guard ConsentInformation.shared.canRequestAds, !started else { return }
        started = true
        MobileAds.shared.start { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
    }

    private func load() {
        guard ad == nil, !loading, started else { return }
        loading = true
        RewardedAd.load(with: unitID, request: Request()) { [weak self] loaded, _ in
            Task { @MainActor in
                guard let self else { return }
                self.loading = false
                self.ad = loaded
                self.loadedAt = Date()
                guard let nonce = self.waiting else { return }
                self.waiting = nil
                self.giveUp?.cancel()
                if loaded != nil { self.play(nonce) } else { self.report(nonce, "unavailable") }
            }
        }
    }

    /// The page's "ads" messages: {type, nonce} for a rewarded ad, or {type:'privacy'} to reopen the consent choices.
    func handle(_ message: [String: Any]) {
        if message["type"] as? String == "privacy" {
            if let presenter = Self.presenter() {
                ConsentForm.presentPrivacyOptionsForm(from: presenter) { _ in }
            }
            return
        }
        guard let nonce = message["nonce"] as? String, !nonce.isEmpty else { return }
        if ad != nil, Date().timeIntervalSince(loadedAt) > Self.maxAge { ad = nil }
        if showing || waiting != nil {
            report(nonce, "unavailable")
        } else if ad != nil {
            play(nonce)
        } else if started {
            waiting = nonce
            let item = DispatchWorkItem { [weak self] in
                guard let self, let nonce = self.waiting else { return }
                self.waiting = nil
                self.report(nonce, "unavailable")
            }
            giveUp = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.waitSeconds, execute: item)
            load()
        } else {
            report(nonce, "unavailable")
        }
    }

    private func play(_ nonce: String) {
        guard let current = ad, let presenter = Self.presenter() else { return report(nonce, "unavailable") }
        ad = nil
        showing = true
        earned = false
        showingNonce = nonce
        current.fullScreenContentDelegate = self
        // The game's sound fades out before the ad takes over the audio (a hard cut buzzes); the page's loading cover hides the wait.
        webView?.evaluateJavaScript("window.__quietMonkeyAudio?.()")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Self.quietMs)) {
            current.present(from: presenter) { [weak self] in
                self?.earned = true
            }
        }
    }

    // The page's loading screen comes down as the ad covers it, so it's gone when the ad closes.
    nonisolated func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.webView?.evaluateJavaScript("window.__monkeyAdOpening?.()") }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.finish(self.earned ? "completed" : "skipped") }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in self.finish("failed") }
    }

    private func finish(_ status: String) {
        showing = false
        if let nonce = showingNonce { report(nonce, status) }
        showingNonce = nil
        // The ad's own sound may have taken over: put the game's audio session back, then restart the page's audio engine
        // (true: even if it says it is running, since it can come back silent).
        MonkeyTrubbleApp.activateAudio()
        webView?.evaluateJavaScript("window.__resumeMonkeyAudio?.(true)")
        load()
    }

    private func report(_ nonce: String, _ status: String) {
        let data = (try? JSONSerialization.data(withJSONObject: nonce, options: .fragmentsAllowed)) ?? Data()
        let quoted = String(data: data, encoding: .utf8) ?? "\"\""
        webView?.evaluateJavaScript("window.__monkeyAdResult?.(\(quoted),'\(status)')")
    }

    /// The top view controller of the app's window, for the consent form and the ad to present from.
    private static func presenter() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
