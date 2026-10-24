import SwiftUI
import AVFoundation
import UIKit

@main
struct MonkeyTrubbleApp: App {
    init() {
        // The screen stays awake only while a level is being played (the page sends 'screen'; GameWebView sets this).
        UIApplication.shared.isIdleTimerDisabled = false
        Self.activateAudio()
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
            GameWebView()
                .background(Color(launchBackground))
                .ignoresSafeArea()
        }
    }
}
