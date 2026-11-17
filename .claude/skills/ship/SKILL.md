---
name: ship
description: Build the Monkey Trubble iOS app in Xcode, install it on the user's iPhone and open it. Use when the user says "ship", "push xcode", "push to my phone", "build and open on my phone" or similar.
---

# Ship Monkey Trubble to the iPhone

Builds `MonkeyTrubbleIOS` (which bundles `web/`), installs it on the paired iPhone and launches it. Run from the repo root `<repo root>`.

## Steps

1. **Sanity-check the game script** so a JS syntax error never ships:
   ```sh
   cd <repo root>/web && sed -n '/<script>/,/<\/script>/p' index.html | sed '1d;$d' > /tmp/monkeytrubble-game.js && node --check /tmp/monkeytrubble-game.js
   ```
   If it fails, stop and fix the error before building.

   **Leaderboard cap check (blocks):** `cd <repo root>/web && node tools/check-scoring.mjs`. If it fails, a legitimate score can exceed the
   server's anti-cheat cap in `supabase/leaderboard.sql`, and those players' scores freeze silently (2026-11-16: the combo bonus outgrew
   the cap and froze ssaammllzz at 720). Stop and tell Paul. The fix is to raise the cap in leaderboard.sql and have Paul run it in Supabase.

   **What's New version check (warn, don't block):** compare the POLY card's notes version with the app version:
   ```sh
   cd <repo root> && notes=$(grep -o "RELEASE_NOTES={version:'[^']*'" web/index.html | grep -o "'.*'" | tr -d "'"); app=$(grep -m1 -o 'MARKETING_VERSION = [0-9.]*' MonkeyTrubbleIOS/MonkeyTrubbleIOS.xcodeproj/project.pbxproj | grep -o '[0-9.]*$'); [ "$notes" = "$app" ] && echo "What's New $notes matches the app" || echo "WARNING: What's New says $notes but the iOS MARKETING_VERSION is $app"
   ```
   On a mismatch, mention it in the report. It's fine for a native-only release (1.0.4 kept the 1.0.3 notes), but a release with player-facing changes should bump `RELEASE_NOTES.version` (2026-11-16: players saw 1.0.3 notes on 1.0.4).

2. **Find the iPhone.** The usual device is PolyiPhonePro (iPhone 14 Pro Max), UDID `00008120-000C291E1E78C01E` (since 2026-10-13; the older CoreDevice id `A73156EF-387D-5EEE-A590-A7CD391914B7` no longer shows). Confirm it's available:
   ```sh
   xcrun devicectl list devices
   ```
   If that id isn't listed as `available (paired)`, use the id of the connected iPhone that is. If none is available, tell the user to connect and unlock the phone. Don't build.
   If this or any Xcode command says the Xcode license hasn't been agreed to (common after an Xcode update), stop and ask the user to run `sudo xcodebuild -license accept` in Terminal. It needs their password.
3. **Build** (signing is automatic, team `976XKW42U9`):
   ```sh
   cd <repo root>/MonkeyTrubbleIOS && xcodebuild -project MonkeyTrubbleIOS.xcodeproj -scheme MonkeyTrubble -configuration Debug -destination 'platform=iOS,id=<DEVICE_ID>' -derivedDataPath build/DerivedData -allowProvisioningUpdates build 2>&1 | grep -E "error|BUILD" | tail -5
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
