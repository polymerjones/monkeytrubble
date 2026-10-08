# Matrix Match prototype

Throwaway browser prototype testing one question: does a four-slot holding buffer make a layered, always-solvable Matrix-themed matching game fun?

Cards are arranged in a four-layer staggered pile. Some begin face-up and others face-down. A visible card can still be locked by a card above it. Click an accessible face-down card once for a fast flip, then click the revealed card again to move it into the holding buffer. Drag an accessible covering card aside to peek underneath; it snaps back without unlocking the buried card.

Auto-clear happens only when two consecutive player flips reveal the same symbol. Those two flipped cards automatically move into the buffer, explode, and clear. Cards that began face-up must always be clicked to enter the buffer, even when their mate is visible or already held.

## Levels, boosters and the joker

Each level number seeds its own board, so a level always deals the same cards and **Retry Level** (shown when the cage fills) replays it exactly. The cards free at the start never contain a matching pair, and every deal is solvable within the 4-slot cage. Each level starts with **2 undos** and **1 shuffle**, shown as count badges above the cage; from the cage-full screen an undo rewinds the overflowing move.

**Joker Caulin** (one per board) is a wildcard: in the cage he pairs with the oldest other card.

Clearing a board shows the level-complete sequence: clear time, then **BEST TIME SET** on a level's first clear or **NEW RECORD!** when a saved time is beaten by at least a second, then the daily streak on the first clear of the day, then the roll to the next level. Progress (level, best times, streak) is saved in `UserDefaults` by the iOS app and in `localStorage` in a browser.

The board has four layers placed so the four bottom corners and the four top cards start open (8 tappable cards, about half of all cards face-up). A card is locked exactly while a higher card visually overlaps it; tapping a locked card shakes it and plays `card cant select.wav`. Pair clears run in the background, so play never pauses while the cage clears. Patriot cards add one of the `warmonkeyclear` clips to their call.

**KEVIN KELLY — Limited Edition 2019 MVP** is a single card, one per level (boards hold 45 cards). Tapping him never uses a cage slot: he pops, plays `kevinkellyclear.mp3`, and fires MVP Vision, flipping every face-down card up for as long as his clip plays (about 4.4 seconds). The Caulin Plushie's clear plays `kaulinannounce2.mp3`.

The game opens on a home screen with a big LEVEL button, a rotating featured card and the streak week. Drop `logo.png`, `bg.jpg` or `button.png` into `art/home/` to replace the built-in logo, background or button look.

Testing parameters: `?play` skips the home screen, `?level=N` jumps to a level, `?reset` clears progress, `?today=YYYY-MM-DD` fakes the date for streak testing, and `?soundcheck` lists every card with its calls.

Open `index.html` in a modern browser. No server, install, or internet connection is required.

The bundled UI sounds preload when the page opens and unlock on the first pointer interaction. `japanesevoice.mp3` plays at the start of each level; on the initial page load, browser autoplay rules defer it until the first interaction. `polyjong-mus1.mp3` loops at approximately -22 dB through a gentle low-pass filter. Monkey calls play above the music and repeat once as a quieter one-second echo. Use **Sound on/off** to toggle music and effects together.

The featured card has a gloss layer that follows device tilt on iPhone and pointer movement in a desktop browser. The special silver card uses a continuous GPU-transformed foil sweep without a pause between passes.

Three playable visual directions are included:

- `index.html?variant=A` — Layered terminal
- `index.html?variant=B` — Operator console
- `index.html?variant=C` — Glyph shrine

The deck is built from `../matrix-match-source/raw images/` (kept outside the app bundle; run `tools/make-card-images.sh` to rebuild the downsized `cards/thumb` and `cards/hero` copies the game loads). It keeps one portrait per look-alike group (two chimps), plus the Caulin plushie, two Monkey Patriots and the Joker Caulin. Boards repeat some cards as extra pairs to fill all 46 slots. Revealing or selecting a portrait updates the hero bar with the animal’s common name, scientific name, and a short species fact.

## Species database

`data/monkey-species.json` is the reusable knowledge and media-source database. It currently contains 30 primate profiles ingested from the chaptered transcript of Animal Insider’s “Weir Sound of Different Monkeys (Primates),” with scientific names, concise facts, source provenance, chapter ranges, and candidate animal-call windows. Clean narration-section stills are stored in `../matrix-match-source/raw images/video-stills/`; rough MP3 call selects, cut from the opening pre-narration windows with short edge fades, are stored in `audio/video-calls/`. The video narration is recorded as a discovery source and should not be treated as an authoritative taxonomic reference without independent verification.

Use the floating switcher or the left/right arrow keys to compare them. Once a direction wins, record the decision below and replace this prototype with a production implementation.

## Verdict

Pending playtest.

## Online leaderboard (Supabase)

1. In the Supabase dashboard, open **SQL Editor → New query**, paste `supabase/leaderboard.sql` and run it.
2. In **Project Settings → API**, copy the Project URL and the `anon` public key into `config.js`.
3. Rebuild the app. Until `config.js` has both values the leaderboard shows "not connected yet"; scores keep saving on the phone and post on the next launch after it's connected.

Players have no login: each install gets a random id and a private secret (stored in the save), and only the SQL functions can write scores.
