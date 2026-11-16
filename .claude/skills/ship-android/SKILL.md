---
name: ship-android
description: Build the Monkey Trubble Android app, install it on a connected Android phone (or the emulator) and open it. Use when the user says "ship android", "push to android", "install on the android phone", "build and open on android" or similar. A plain "ship" or "push to my phone" means the iPhone (the ship skill).
---

# Ship Monkey Trubble to an Android phone

Builds `MonkeyTrubbleAndroid` (which bundles `web/`), installs it on a connected Android device and launches it. Run from the repo root `<repo root>`. Every command needs the JDK that ships with Android Studio:

```sh
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
ADB=~/Library/Android/sdk/platform-tools/adb
```

## Steps

1. **Sanity-check the game script** so a JS syntax error never ships:
   ```sh
   cd <repo root>/web && sed -n '/<script>/,/<\/script>/p' index.html | sed '1d;$d' > /tmp/monkeytrubble-game.js && node --check /tmp/monkeytrubble-game.js
   ```
   If it fails, stop and fix the error before building.

   **What's New version check (warn, don't block):** compare the POLY card's notes version with the app version:
   ```sh
   cd <repo root> && notes=$(grep -o "RELEASE_NOTES={version:'[^']*'" web/index.html | grep -o "'.*'" | tr -d "'"); app=$(grep -m1 -o 'versionName = "[0-9.]*"' MonkeyTrubbleAndroid/app/build.gradle* | grep -o '[0-9][0-9.]*'); [ "$notes" = "$app" ] && echo "What's New $notes matches the app" || echo "WARNING: What's New says $notes but the Android versionName is $app"
   ```
   On a mismatch, mention it in the report. It's fine for a native-only release (1.0.4 kept the 1.0.3 notes), but a release with player-facing changes should bump `RELEASE_NOTES.version` (2026-11-16: players saw 1.0.3 notes on 1.0.4).

2. **Find the device:**
   ```sh
   $ADB devices -l
   ```
   Use the one listed as `device`. If it says `unauthorized`, ask the user to unlock the phone and accept the "Allow USB debugging?" prompt. If nothing is listed, tell the user to connect the phone with USB debugging on (Settings › About phone › tap Build number 7 times, then Settings › System › Developer options › USB debugging). Don't build.
   Only if the user asks for the emulator, boot it headless and **muted** (never play sound on Paul's Mac):
   ```sh
   ~/Library/Android/sdk/emulator/emulator -avd Medium_Phone_API_37.0 -no-audio -no-window -no-snapshot-save -no-boot-anim
   ```
   (run in the background), then `$ADB wait-for-device` and poll `$ADB shell getprop sys.boot_completed` until it prints `1`.
   With more than one device listed, pass `-s <serial>` to every `$ADB` command below.

3. **Build:**
   ```sh
   cd <repo root>/MonkeyTrubbleAndroid && ./gradlew assembleDebug --console=plain -q 2>&1 | grep -E "^e: |What went wrong|BUILD" -A3 | tail -20
   ```
   If `local.properties` is missing, create it with `sdk.dir=$HOME/Library/Android/sdk`. Success prints nothing (with `-q`) and leaves `app/build/outputs/apk/debug/app-debug.apk`. On failure, show the errors and stop.

4. **Install and open:**
   ```sh
   $ADB install -r app/build/outputs/apk/debug/app-debug.apk
   $ADB shell am force-stop com.paulfisher.monkeytrubble
   $ADB shell am start -n com.paulfisher.monkeytrubble/.MainActivity
   ```
   Needs `Success` from the install. If it fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE` (a build signed with a different key, e.g. from Play), ask before running `$ADB uninstall com.paulfisher.monkeytrubble`: it deletes the saved progress on the phone.

5. **Report** in one or two lines: built, installed and launched (or exactly which step failed and why). Mention that Play Games stays off until the IDs in `app/src/main/res/values/games-ids.xml` are filled in, if they're still empty.

## Notes
- The page can be inspected from Chrome on the Mac at `chrome://inspect` (debug builds only).
- Saved progress lives in the app's SharedPreferences and survives `install -r`, but not an uninstall.
- Don't commit or push to GitHub as part of shipping unless the user asks.
