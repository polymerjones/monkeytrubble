import SwiftUI
import AVFoundation
import UIKit

@main
struct MonkeyTrubbleApp: App {
    init() {
        UIApplication.shared.isIdleTimerDisabled = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            GameWebView()
                .background(Color.black)
                .ignoresSafeArea()
        }
    }
}
