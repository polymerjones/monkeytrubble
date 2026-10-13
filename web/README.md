# Matrix Match prototype

Throwaway browser prototype testing one question: does a four-slot holding buffer make a layered, always-solvable Matrix-themed matching game fun?

Cards are arranged in a four-layer staggered pile. Some begin face-up and others face-down. A visible card can still be locked by a card above it. Click an accessible face-down card once for a fast flip, then click the revealed card again to move it into the holding buffer. Drag an accessible covering card aside to peek underneath; it snaps back without unlocking the buried card.

Auto-clear happens only when two consecutive player flips reveal the same symbol. Those two flipped cards automatically move into the buffer, explode, and clear. Cards that began face-up must always be clicked to enter the buffer, even when their mate is visible or already held.

## Levels, boosters and the joker

Each level number seeds its own board, so a level always deals the same cards and **Retry Level** (shown when the cage fills) replays it exactly. The cards free at the start never contain a matching pair, and every deal is solvable within the 4-slot cage. Each level starts with **2 undos** and **1 shuffle**, shown as count badges above the cage; from the cage-full screen an undo rewinds the overflowing move. An empty booster shows a ▶ badge: tapping it offers an ad for more. With three cards caged and no shuffles left, the shuffle button pulses to point at that. The game-over screens offer **RESUME (Watch Ad)** (cage full: clears the cage), **SHUFFLE (Watch Ad)** (no moves, out of shuffles: re-opens the level and shuffles at once) and **UNDO (Watch Ad)** (out of undos). Until a real ad SDK is in, dev builds show the **YOUR AD HERE** placeholder, which lets you pick how the ad ends.

**Difficulty after the jungle (level 11 on, Normal):** chapters 3–10 mix in the cascade shapes (**COLUMNS**, **WATERFALL**, **VALLEY**, **TWIN STACKS**). These are solitaire-style columns where only each column's end card is free, so as few as 3 cards are open at the start. Levels 11–20 open with one free pair and levels 21+ with none. A correct line can need three unmatched cards waiting in the cage (two before level 11). The face-up share keeps falling past level 13, to 50% by about level 30. Easy keeps the classic shapes and rules. Every deal is still solvable: `node tools/check-deals.mjs [levels]` checks it.

**Joker Caulin** (one per board) is a wildcard: in the cage he pairs with the oldest other card.

Clearing a board shows the level-complete sequence: clear time, then **BEST TIME SET** on a level's first clear or **NEW RECORD!** when a saved time is beaten by at least a second, then the daily streak on the first clear of the day, then the roll to the next level. Progress (level, best times, streak) is saved in `UserDefaults` by the iOS app and in `localStorage` in a browser.

The board has four layers placed so the four bottom corners and the four top cards start open (8 tappable cards, about half of all cards face-up). A card is locked exactly while a higher card visually overlaps it; tapping a locked card shakes it and plays `card cant select.wav`. Pair clears run in the background, so play never pauses while the cage clears. Patriot cards add one of the `warmonkeyclear` clips to their call.

**KEVIN KELLY — Limited Edition 2019 MVP** is a single card, one per level (boards hold 45 cards). Tapping him never uses a cage slot: he pops, plays `kevinkellyclear.mp3`, and fires MVP Vision, flipping every face-down card up for as long as his clip plays (about 4.4 seconds). The Caulin Plushie's clear plays `kaulinannounce2.mp3`.

The game opens on a home screen with a big LEVEL button, a rotating featured card and the streak week. Drop `logo.png`, `bg.jpg` or `button.png` into `art/home/` to replace the built-in logo, background or button look.

Testing parameters: `?play` skips the home screen, `?level=N` jumps to a level, `?reset` clears progress, `?today=YYYY-MM-DD` fakes the date for streak testing, and `?soundcheck` lists every card with its calls.

Open `index.html` in a modern browser. No server, install, or internet connection is required.

The bundled UI sounds preload when the page opens and unlock on the first pointer interaction. `japanesevoice.mp3` plays at the start of each level; on the initial page load, browser autoplay rules defer it until the first interaction. `polyjong-mus1.mp3` loops at approximately -22 dB through a gentle low-pass filter. Monkey calls play above the music and repeat once as a quieter one-second echo. Use **Sound on/off** to toggle music and effects together. The home screen loops `audio/music/homescreen.mp3`, starting at the beat (7.5s in, its `start`). The HOME MUSIC dev switch can swap it for the older candidates. In the iOS app the home music starts as soon as its own file is ready, not after everything has loaded. Any track can have a `start` offset (in seconds) for fresh starts; `jungle.mp3` starts 35s in. A level keeps its playlist's track running unless the track is in its last 20 seconds, in which case a fresh one starts. The launch sting (`polyhome.mp3`) plays a little lower (`HOME_STING_RATE`) with a subtle delay echo. Music sits at -7 dB (`MUSIC_VOLUME`). From a ×8 chain the music swaps to a combo loop and the screen edges glow (`COMBO_SWAP_AT`). The page sets Now Playing (lock screen, Dynamic Island) to the game's name and icon.

The featured card has a gloss layer that follows device tilt on iPhone and pointer movement in a desktop browser. The special silver card uses a continuous GPU-transformed foil sweep without a pause between passes.

Three playable visual directions are included:

- `index.html?variant=A` — Layered terminal
- `index.html?variant=B` — Operator console
- `index.html?variant=C` — Glyph shrine

The deck is built from `../source/art/raw images/` (kept outside the app bundle; run `tools/make-card-images.sh` to rebuild the downsized `cards/thumb` and `cards/hero` copies the game loads). It keeps one portrait per look-alike group (two chimps), plus the Caulin plushie, two Monkey Patriots and the Joker Caulin. Boards repeat some cards as extra pairs to fill all 46 slots. Revealing or selecting a portrait updates the hero bar with the animal’s common name, scientific name, and a short species fact.

## Species database

`data/monkey-species.json` is the reusable knowledge and media-source database. It currently contains 30 primate profiles ingested from the chaptered transcript of Animal Insider’s “Weir Sound of Different Monkeys (Primates),” with scientific names, concise facts, source provenance, chapter ranges, and candidate animal-call windows. Clean narration-section stills are stored in `../source/art/raw images/video-stills/`; rough MP3 call selects, cut from the opening pre-narration windows with short edge fades, are stored in `audio/video-calls/`. The video narration is recorded as a discovery source and should not be treated as an authoritative taxonomic reference without independent verification.

Audio the game doesn't play is kept out of the app in `../source/audio-unused/` (old combo loops, unused pick sounds, and the species calls no card uses). The species database still lists those calls by their old `video-calls/` paths.

Use the floating switcher or the left/right arrow keys to compare them. Once a direction wins, record the decision below and replace this prototype with a production implementation.

## Verdict

Pending playtest.

## Release builds, ads, iCloud and Game Center

- **Dev mode follows the build:** Debug builds (Xcode, `/ship`) have dev mode on. Release builds (TestFlight, App Store) have it off, because the app tells the page which kind of build it is (`window.__monkeyDebugBuild`). In a browser, dev mode is on only on a local server or file://. Three taps on the home logo toggle dev mode in Debug and TestFlight builds and in a browser, but not in the App Store build (`window.__monkeyDevTaps`; App Review guideline 2.3.1 forbids hidden features).
- **Ads:** `ADS_LIVE` is off for 1.0. With it off, each reward (resume, shuffle, undo, Owl Eyes) is free once per level (`FREE_REWARDS_PER_LEVEL`) and the buttons say **(Free)**. The ad plumbing stays in place: `requestReward` → `adProvider.show()`. To add real ads, swap `mockAdProvider` for the SDK's rewarded-ad call and set `ADS_LIVE=true`; the buttons go back to **(Watch Ad)**. Dev mode always shows the **YOUR AD HERE** simulator.
- **iCloud save sync:** the save is stored on the phone and in the iCloud key-value store (`GameServices.swift`). At launch the page merges the two copies (`mergeSaves`): the furthest level, the best best-times, the most XP and the latest streak win. The leaderboard identity comes from the copy with more play. If another device moves the save on, it's folded in while the game runs.
- **Game Center:** the app signs the player in at launch and offers their Game Center nickname as the default name. Scores go to two leaderboards, which must exist in App Store Connect with these IDs: `monkeytrubble.rating` (the leaderboard score) and `monkeytrubble.level` (highest level cleared). The Game Center button sits bottom-left on the home screen.
- **App Store basics:** `PrivacyInfo.xcprivacy` (privacy manifest: no tracking; leaderboard ID, nickname and scores for app functionality; UserDefaults reason CA92.1), `MonkeyTrubbleIOS.entitlements` (Game Center, iCloud key-value store) and `ITSAppUsesNonExemptEncryption = NO` in `Info.plist`.

## Online leaderboard (Supabase)

1. In the Supabase dashboard, open **SQL Editor → New query**, paste `supabase/leaderboard.sql` and run it.
2. In **Project Settings → API**, copy the Project URL and the `anon` public key into `config.js`.
3. Rebuild the app. Until `config.js` has both values the leaderboard shows "not connected yet"; scores keep saving on the phone and post on the next launch after it's connected.

**Climb screen:** when a clear moves you past other players, tapping NEXT LEVEL first shows your row rising past each of them, with a haptic tick for each one. It shows at most every 5 levels (`CLIMB_EVERY`), plus at every chapter end and after a well-played level (a new record or a ×8 chain). It needs the `players_passed` function at the end of `supabase/leaderboard.sql`. Re-run the file once to add it; until then the climb screen just doesn't appear.

Players have no login: each install gets a random id and a private secret (stored in the save), and only the SQL functions can write scores.

**Names and moderation (App Store guideline 1.2):** offensive names are refused both on the phone (`nameAllowed`) and on the server (`name_ok`), using the same word list. Tapping another player's row on the board offers **REPORT NAME** and **HIDE PLAYER**. Hiding is per phone (`progress.hiddenPlayers`). A report also hides the player locally, and after three different players report a name it shows as "Monkey XXXX" for everyone until that player picks a new name. The climb screen's `players_passed` reads the previous score from the server's own records (`prev_score`), never from the phone.

## Halloween levels

Halloween is seasonal: from Oct 1 to Nov 2 (the player's local date, `halloweenSeason`), every other level from level 2 is a Halloween level. The rest of the year players get regular levels only. In dev mode the **SEASON** switch decides all year: HALLOWEEN (FULL), HALLOWEEN SKIN, EVERY OTHER, MIXED (about half, seeded by the level number so Retry deals the same set; odds in `HALLOWEEN_CHANCE`) or REGULAR (the off-season game).

A Halloween level deals only the haunted primates (`pack:'halloween'` in `CARD_DATA`), plus Kevin and the Joker. Card calls play about 5–6 semitones lower (`HORROR_RATE`) through a long, dark reverb, and the music switches to the `halloweenRelaxed` or `halloweenCompetitive` playlist that matches the Music Mode setting. The board, face-down cards and the hero card's shine (each card's `foil` gradient) take Halloween colors.

To add a Halloween card:
1. Put the art in `../source/art/halloween/`.
2. Add a `build` line for it in `tools/make-card-images.sh`, then run the script.
3. Add an `H##` entry to `CARD_DATA`, after the other `H` cards.

Halloween levels also swap some sounds through the `HALLOWEEN_SFX` map. Each entry maps a regular sound key to a list of Halloween sounds, and when a list has several files, each play picks one at random. The swapped sounds are card grabs, the locked-card buzz, level start, shuffle, game over and the Joker clear. Owl Eyes plays `hwOwl` (a howl). A Good Eye combo plays a scream (`hwScream`) instead of the usual sting, and its praise voiceover is pitched down (`PRAISE_HORROR_RATE`) into the horror reverb. The Joker shows as the Joker Howler, from the `halloween:{image,name,foil}` variant on its `CARD_DATA` entry. To add a sound, put the file in `audio/halloween/`, give it a key in `SOUND_FILES` and a loudness trim in `MIX_DB`, then add the key to the right `HALLOWEEN_SFX` list. On Halloween levels the Owl Eyes glow toxic green.

To add a Halloween music track, put it in `audio/music/halloween/` and add it to `MUSIC.halloweenRelaxed` or `MUSIC.halloweenCompetitive`. Use `trim` (in dB) to match it to -15.8 LUFS.

## Christmas

Christmas mode is off for players until it's finished. Turn it on with the **SEASON** dev switch, or for everyone by setting `CHRISTMAS_LIVE=true`, which runs it from Dec 1 to Jan 6. SEASON has two Christmas settings. **CHRISTMAS LEVELS** makes every level a Christmas level. **CHRISTMAS (FULL)** (which is what the live season uses) also makes the home screen Christmassy, with the Christmas home music, Settings music, background, falling snow and UI colours. The debug build resets SEASON to Every Other at each launch. While it's on, every level is a Christmas level:

- **Scene:** one of Paul's two Christmas backgrounds, alternating by level. `../source/art/chapters/split-layers.py christmas` gives them a snowy grade (shadows lifted into a cold white haze, lower contrast) and splits them into far, mid and near parallax layers like the chapters, plus `flat.jpg`, the whole graded picture, for the full-Christmas home screen. `tools/make-card-images.sh` copies them to `art/seasons/christmas/<n>/`. Snowflakes blow across the scene on a gusting wind.
- **UI:** a red, pine-green and gold UI theme (`christmas` in `tools/chapter-themes.py`).
- **Sparkles:** red, green, gold and white (`CHRISTMAS_DUST`).
- **Music:** Paul's tracks are in `audio/music/christmas/`, trimmed to -15.8 LUFS. In full Christmas, the home screen plays `xmasmonkey2best` (`CHRISTMAS_HOME`) and Settings plays `xmasmonkey2better` (`CHRISTMAS_SETTINGS`). On levels, Competitive plays only `xmasmonkey2best`, and Relaxed shuffles the other four. Long combos tighten the tone instead of switching to the jungle combo loop, so the Christmas music keeps playing.

Still to come from Paul:
- **Sounds:** add files to `SOUND_FILES` and map regular sounds to them in `CHRISTMAS_SFX`, the same way as `HALLOWEEN_SFX`.
- **Cards:** Christmas levels deal the regular cards for now. Christmas cards will need a deck and card-art hookup like the Halloween one.

## Chapter art and the Expedition set

The chapter guide is `../source/art/chapters/level-ref.png`: each of the 10 chapters features the species listed there, plus the great apes of its region (`featured` in `CHAPTERS`). Each chapter also deals one food card (`foods`).

- **Backgrounds:** `../source/art/chapters/split-layers.py` splits each `ch<n>_*.png` into far, mid and near parallax layers in `layers/<n>/`, and `tools/make-card-images.sh` copies them to `art/chapters/<n>/` (`far.jpg`, `mid.webp`, `near.webp`). A painted far layer turns off the placeholder SVG mid and near layers. A `water.png` alpha mask makes that area of the far layer ripple (chapters 3 and 7). Each chapter's layers load and decode as one set (under the loader or the level transition), so a level appears with its background already painted. The next chapter's art loads in the background. `parallax` in `CHAPTERS` scales a chapter's drift and tilt: The Bridge uses .3, because its rails run from near to far and tear apart at full parallax.
- **UI themes:** each chapter recolours the Jungle UI (`ui` in `CHAPTERS`; The Bridge and Enter the Jungle keep plain Jungle). The colours come from `tools/chapter-themes.py`, which sorts the Jungle theme's colours into panel, wood and accent families and shifts each to the chapter's hues; edit `CHAPTER_UI` there and re-run it. Halloween levels use the Halloween theme. The THEME dev switch can force CONSOLE, JUNGLE or HALLOWEEN everywhere; players no longer pick a theme.
- **Expedition cards:** `../source/art/expedition/` holds the 2:3 crops cut from `contact-sheet.png`, built to `cards/*/set2-*.jpg`. They're upscales of ~200px-wide cards, so they're softer than the other sets.
- **Species still missing art** are in `CARD_DATA` with `pending:true` and are skipped until it lands: Bornean and Sumatran orangutans, mountain and western lowland gorillas, chimpanzee, bonobo, siamang, mountain guenon, patas monkey, drill, sifaka and pig-tailed macaque. To add one, put its 2:3 art in `../source/art/expedition/`, add a `build` line in `tools/make-card-images.sh`, run it, and delete `pending:true`.
