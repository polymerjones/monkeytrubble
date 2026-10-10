# Monkey Trubble for iPhone

The SwiftUI app packages `../web` as an offline game and presents it in a full-screen `WKWebView`.

## Run on an iPhone

1. Open `MonkeyTrubbleIOS.xcodeproj` in Xcode.
2. Select the **MonkeyTrubble** target, then **Signing & Capabilities**.
3. Choose your Apple Developer team. If the bundle identifier is unavailable, change `com.paulfisher.MonkeyTrubble` to a unique identifier.
4. Connect and unlock the iPhone, trust the Mac if prompted, and select the iPhone in Xcode's device menu.
5. Press **Run** (`⌘R`). If iOS asks, enable Developer Mode and trust the developer certificate.

The app is portrait-only, runs offline, uses Variant D, respects safe areas, and provides native haptics for flips, cage placement, successful pairs, and cage overflow.

Edits made inside `../web` are automatically included the next time the Xcode app is built.
