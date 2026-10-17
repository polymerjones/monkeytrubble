# Monkey Trubble

A Matrix-themed, layered card-matching game starring primates. Clear the pile by pairing cards through a four-slot holding cage. Every level is seeded, solvable and replayable.

It runs three ways from the same code: as a browser game, as an offline iPhone app that wraps the same files in a `WKWebView`, and as an Android app that wraps them in a `WebView`.

## Play it in a browser

Open `web/index.html` in any modern browser. There's no server, install or internet connection needed.

Handy URL parameters: `?tutorial` opens the tutorial, `?play` skips the home screen, `?level=N` jumps to a level, `?reset` clears progress.

## Layout

| Folder | What's in it |
|---|---|
| `web/` | The game: `index.html`, card art, audio, fonts, species data, Supabase leaderboard SQL. See `web/README.md` for the mechanics. |
| `MonkeyTrubbleIOS/` | SwiftUI app that bundles `web/` for iPhone. See `MonkeyTrubbleIOS/README.md`. |
| `MonkeyTrubbleAndroid/` | Kotlin app that bundles `web/` for Android and Google Play. See `MonkeyTrubbleAndroid/README.md`. |
| `source/art/` | Original, full-size artwork and brand files. Not bundled in the app. `web/tools/make-card-images.sh` builds the game-size card images from here. |
| `source/sfx/` | Raw sound-effect recordings and compilations. The game uses the trimmed copies in `web/audio/`. |

## Build the iPhone app

Open `MonkeyTrubbleIOS/MonkeyTrubbleIOS.xcodeproj`, pick your signing team, and run on a device. Details are in `MonkeyTrubbleIOS/README.md`.
