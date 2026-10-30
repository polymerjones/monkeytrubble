import SwiftUI
import AVFoundation
import UIKit

@main
struct MonkeyTrubbleApp: App {
    init() {
        // The screen stays awake only while a level is being played (the page sends 'screen'; GameWebView sets this).
        UIApplication.shared.isIdleTimerDisabled = false
        Self.activateAudio()
        // MetricKit reports, saved on this device for dev tools (Perf.swift).
        MetricsStore.shared.start()
    }

    // The game's audio session: ambient, mixing with other apps. Re-applied after an ad, an interruption or a return to the app,
    // because the ad's video player changes it and the game's sound stayed silent after an ad was left open for a few minutes.
    static func activateAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            // Full height (the page handles the top and bottom insets itself) but inside the side safe areas: the unfolded iPhone Duo
            // keeps its status pill in an 84pt strip on the right, which covered the Settings gear and clipped the boosters
            // (Paul 2026-10-30). Upright iPhones have no side insets, so nothing changes there. The strip shows the launch colour.
            ZStack {
                Color(launchBackground).ignoresSafeArea()
                GameWebView()
                    .ignoresSafeArea(edges: .vertical)
            }
        }
    }
}
