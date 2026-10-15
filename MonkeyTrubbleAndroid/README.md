# Monkey Trubble for Android

A small Kotlin app that packages `../web` as an offline game and presents it in a full-screen `WebView`, the Android twin of `MonkeyTrubbleIOS`.

The page is served from `https://appassets.androidplatform.net/web/` (`WebViewAssetLoader`), and a start script gives it the same `window.webkit.messageHandlers` (`haptics`, `storage`, `gameCenter`) the iPhone app registers, so `web/index.html` runs unchanged. Edits made in `../web` are copied in on the next build (`bundleWeb` task).

| iPhone | Android |
|---|---|
| UserDefaults + iCloud key-value store | SharedPreferences + Android Auto Backup (restored on reinstall or a new phone; not live sync) |
| Game Center | Google Play Games leaderboards (`res/values/games-ids.xml`) |
| UIImpactFeedbackGenerator | Vibration composition primitives, or the system's standard feedback on simpler phones |
| CoreMotion gravity | `TYPE_GRAVITY` sensor, flipped to CoreMotion's sign convention |
| — | Back gesture: `window.__monkeyBack()` closes the top dialog or leaves the level; on the home screen the app goes to the background |

## Build

Needs Android Studio (or a JDK 17+ and the Android SDK; set `sdk.dir` in `local.properties`).

```sh
./gradlew assembleDebug       # app/build/outputs/apk/debug/app-debug.apk
./gradlew bundleRelease       # app/build/outputs/bundle/release/app-release.aab, for Play Console
```

Install on a phone with USB debugging on: `adb install -r app/build/outputs/apk/debug/app-debug.apk`.

Debug builds keep the hidden dev mode (three taps on the home logo) and Chrome WebView inspection (`chrome://inspect`); release builds turn both off.

## Release signing

Create an upload key once and keep it backed up outside the repo:

```sh
keytool -genkeypair -v -keystore ~/keys/monkeytrubble-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

Then add `keystore.properties` here (git-ignored):

```
storeFile=/Users/you/keys/monkeytrubble-upload.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

## Play Games

Until `game_services_project_id` in `res/values/games-ids.xml` is filled in, the app runs without Play Games. To turn it on: in Play Console → Play Games Services, create the project, add the Android credential with the SHA-1 of both the upload key and the Play app-signing key, create the **Troop Rating** and **Highest Level** leaderboards, then copy the project ID and the two leaderboard IDs into `games-ids.xml`.
