# Monkey Trubble

A Matrix-themed, layered card-matching game starring primates. Clear the pile by pairing cards through a four-slot holding cage. Every level is seeded, solvable and replayable.

It runs two ways from the same code: as a browser game, and as an offline iPhone app that wraps the same files in a `WKWebView`.

## Play it in a browser

Open `web/index.html` in any modern browser. There's no server, install or internet connection needed.

Handy URL parameters: `?play` skips the home screen, `?level=N` jumps to a level, `?reset` clears progress.

## Layout

| Folder | What's in it |
|---|---|
| `web/` | The game: `index.html`, card art, audio, fonts, species data, Supabase leaderboard SQL. See `web/README.md` for the mechanics. |
| `MonkeyTrubbleIOS/` | SwiftUI app that bundles `web/` for iPhone. See `MonkeyTrubbleIOS/README.md`. |
| `source/art/` | Original, full-size artwork and brand files. Not bundled in the app. `web/tools/make-card-images.sh` builds the game-size card images from here. |
| `source/sfx/` | Raw sound-effect recordings and compilations. The game uses the trimmed copies in `web/audio/`. |

## Build the iPhone app

Open `MonkeyTrubbleIOS/MonkeyTrubbleIOS.xcodeproj`, pick your signing team, and run on a device. Details are in `MonkeyTrubbleIOS/README.md`.
