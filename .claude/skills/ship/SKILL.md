---
name: ship
description: Build the Monkey Trubble iOS app in Xcode, install it on the user's iPhone and open it. Use when the user says "ship", "push xcode", "push to my phone", "build and open on my phone" or similar.
---

# Ship Monkey Trubble to the iPhone

Builds `MonkeyTrubbleIOS` (which bundles `matrix-match-prototype/`), installs it on the paired iPhone and launches it. Run from the repo root `/Users/paulfisher/fed2026open`.

## Steps

1. **Sanity-check the game script** so a JS syntax error never ships:
   ```sh
   cd /Users/paulfisher/fed2026open/matrix-match-prototype && sed -n '/<script>/,/<\/script>/p' index.html | sed '1d;$d' > /tmp/monkeytrubble-game.js && node --check /tmp/monkeytrubble-game.js
   ```
   If it fails, stop and fix the error before building.

2. **Find the iPhone.** The usual device is PolyiPhonePro (iPhone 14 Pro Max), id `A73156EF-387D-5EEE-A590-A7CD391914B7`. Confirm it's available:
   ```sh
   xcrun devicectl list devices
   ```
   If that id isn't listed as `available (paired)`, use the id of the connected iPhone that is. If none is available, tell the user to connect and unlock the phone. Don't build.

3. **Build** (signing is automatic, team `976XKW42U9`):
   ```sh
   cd /Users/paulfisher/fed2026open/MonkeyTrubbleIOS && xcodebuild -project MonkeyTrubbleIOS.xcodeproj -scheme MonkeyTrubble -configuration Debug -destination 'platform=iOS,id=<DEVICE_ID>' -derivedDataPath build/DerivedData -allowProvisioningUpdates build 2>&1 | grep -E "error|BUILD" | tail -5
   ```
   Needs `** BUILD SUCCEEDED **`. On failure, show the errors and stop.

4. **Install and open:**
   ```sh
   xcrun devicectl device install app --device <DEVICE_ID> build/DerivedData/Build/Products/Debug-iphoneos/MonkeyTrubble.app
   xcrun devicectl device process launch --terminate-existing --device <DEVICE_ID> com.paulfisher.MonkeyTrubble
   ```

5. **Report** in one or two lines: build succeeded, installed and launched (or exactly which step failed and why). Mention any known placeholder content that's in this build.

## Notes
- Saved progress, best times and the streak live in the app's UserDefaults and survive reinstalls.
- Don't commit or push to GitHub as part of shipping unless the user asks.
