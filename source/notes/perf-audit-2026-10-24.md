# Monkey Trubble: performance, memory and battery audit (2026-10-24)

Three sources:
1. Paul's iPhone battery screen.
2. A real-device test on the iPhone 14 Pro Max, recorded with Apple's Instruments (`xctrace`) while Paul played.
3. A fresh-eyes code audit by a separate AI agent, measured in headless Chrome. This is the "Astra playtest".

All tests used **Debug builds**. Release/TestFlight builds will be a little lighter, but the problems below are real in both.

---

## TL;DR

- **The game is crashing from memory.** At 3:35 pm iOS killed the game's web process (`com.apple.WebKit.WebContent`) at **1.8 GB**, its per-process limit. Paul saw this as the game "rebooting" after beating Halloween level 3.
- **Memory climbs as you play**: ~550 MB on the home screen, 945 MB after player cards and Pick Your Monkey, 1.5 GB on a Halloween level, then the kill.
- **The game itself isn't leaking objects.** Page elements, script memory, canvases and images stay flat in the browser. The memory is WebKit's drawing layers on iPhone. At 3× resolution every full-screen layer is ~14 MB, and the game has several huge layers that are always animating.
- **The home screen burns ~30% CPU while sitting still**, because ~28 animations never stop, even behind other screens.
- **The background is fine.** In another app the game used 0% CPU and released memory. The "7 min background" on the battery screen most likely comes from the debug setup: Xcode installs and relaunches, plus the grace period right after leaving the app.

**Priority before the next iOS/Android builds:** fix the memory growth (it crashes), then the idle CPU (battery).

---

## 1. iPhone battery screen (Paul's screenshot)

| App | On screen | Background | Battery |
|---|---|---|---|
| Monkey Trubble | 45 min | 7 min | **28%** |
| Notes | 1 h 10 min | 14 min | 13% |
| ChatGPT | 21 min | 4 min | 5% |

Monkey Trubble used about twice the battery of Notes in about 60% of the screen time.

---

## 2. Real-device test (iPhone 14 Pro Max, iOS 27.2, Debug build)

**Recorded with:**
- tool: `xcrun xctrace record --template "Activity Monitor" --instrument Hitches --instrument "Thermal State" --all-processes`
- all processes recorded, because the game's drawing and scripts run in WebKit's separate processes, which iOS bills to the app

**Traces and parser:** `scratchpad/device/` (`*.trace`, `parse.py`).

### Memory and CPU by scene: the game's web process (WebContent, pid 2769)

| # | Scene | Length | Memory | CPU at end |
|---|---|---|---|---|
| 1 | Home screen, untouched | 60 s | 547 MB → 547 MB | **~31%** |
| 2 | Playing levels 38–39 | 90 s | 928 → 699 MB | ~0–10% |
| 3 | In the background (Messages) | 120 s | 642 → **379 MB** | **0%** |
| 4 | Leaderboard player cards + Pick Your Monkey | 75 s | 379 → **945 MB** | ~17% |
| 5 | Halloween level 3 (POLY party) | 90 s | 840 MB → **1.51 GB** → killed | ~27% |

After the crash the reloaded web process (pid 2981) started at **553 MB** and reached **794 MB within ~20 s**.

Other processes:
- WebKit GPU process: 30–87 MB.
- The app process itself (Swift): ~22–24 MB, ~8–10% CPU. That's the motion sensor, haptics and message bridge.

### Crash logs on the phone (JetsamEvent = iOS killed a process for memory)

| Time | Largest process | Killed | Game's web process |
|---|---|---|---|
| 2026-10-24 13:10 | WebContent | healthappd | **625 MB** (largest on the phone) |
| **2026-10-24 15:35** | **WebContent** | **WebContent, "highwater", 1,827 MB** | the game, killed |

The other memory events today and yesterday killed system daemons, not the game.

### Background

- Over 2 min in Messages: CPU 0%, memory released (642 → 379 MB). Audio and timers sleep as designed.
- There are no `UIBackgroundModes` in the app, and the audio session is `.ambient`, so iOS can't legally keep the game running in the background.
- Most likely sources of the 7 background minutes:
  - Xcode installs and relaunches during testing
  - the ~30 s grace period after each switch away, which the WebKit processes, AdMob's ad WebViews, iCloud key-value sync and Game Center can all use
  - Debug launches attached to the debugger, which aren't suspended

---

## 3. Fresh-eyes code audit (headless Chrome, iOS code path)

**Method:**
- Chrome over CDP at 430×900, 3× scale, faking the iOS message handlers so the page takes its iPhone code path.
- Counted animation frames, timers and canvas drawing per second, plus main-thread time per second.
- Headless can't show GPU, layer or filter cost; where the report says "GPU", that cost is inferred from the CSS.

**Results:** `scratchpad/audit/` (`all-results.jsonl`, `audit.mjs`).

### Ranked findings

1. **The screen never turns off by itself.**
   - Evidence: `isIdleTimerDisabled = true` is always set (MonkeyTrubbleApp.swift:8); Android uses `FLAG_KEEP_SCREEN_ON` (MainActivity.kt:49).
   - Impact: **High**. A game left open on home, the win screen or a menu keeps the screen at full brightness forever, with #2's animations running.
   - Fix: keep the screen awake only during a live level, plus ~2 min after the last touch.

2. **The home screen's infinite animations never rest, even behind other screens.**
   - Measured: home idle costs **112 ms of main-thread work per second**, with 60 style recalculations a second and **28 infinite animations**:
     - the ticker scroll, plus ~20 spinning 3D ticker cards with shadows
     - the PLAY pulse, the byline glow and the piece nudge
   - They kept running under the streak scene (135 ms/s), the POLY lightbox (168 ms/s) and the leaderboard (87 ms/s). They only pause when home itself is hidden.
   - The byline glow animates `box-shadow`, which means a repaint every frame. The ticker keeps ~20 3D layers alive.
   - On the device: **~31% CPU while idle on home**.
   - Fix:
     - pause them when the scenery rests and whenever anything covers home
     - make the byline glow opacity-only
     - add a perf switch `homeRest`

3. **The lightbox (cards and player cards) runs at full frame rate forever.**
   - Measured: **127–133 ms/s even after 30 s untouched**. Two 60 fps loops (card sway, sparkles), with ~1,450 sparkle draws per second on a **full-screen** canvas and a spawn timer every 160 ms.
   - Inferred GPU cost: a backdrop blur over moving content, and the foil layers' `mix-blend-mode` on a card that sways every frame.
   - Fix:
     - after ~8 s idle, stop new sparkles, freeze the sway and the holo
     - run the sparkles at 30 fps
     - add a perf switch

4. **During play, the scenery redraws at ~60 Hz, not the intended 30.**
   - Measured right after a tap: 90 ms/s, 60 timer callbacks a second, 110 animation frames a second, ~240 ambient-canvas draws a second.
   - Drift and ambient each run their own "30 fps" loop. The two loops are out of step, so together they redraw up to ~60 times a second.
   - Players tap more often than every 8 s, so the scenery is effectively always awake during play.
   - Fix: one shared clock that drives every scenery layer in a single frame, maybe 20–24 fps for drift. No visible change.

5. **The win-screen rays rotate forever on a huge masked layer.**
   - `.win-rays` is 160vmax square: **~4,300 px at 3×, about 70 MB as a layer**, plus its mask. It has a conic gradient and mask and rotates for 60 s, forever.
   - Measured: 38–42 ms/s idle on the win screen.
   - The streak scene's rays and flame flicker also run until OK is tapped.
   - Fix: stop after one or two turns, shrink to ~110vmax, remove when off screen.

6. **The tips loop never sleeps.**
   - About 10 frames/s plus 3.5 timers/s at rest on a level; it polls once a second everywhere, even at home and while hidden.
   - Fix: stop it when the scenery rests and once every tip has been seen.

7. **Small timers that are always on:** the clock (4 Hz, even when hidden), the owl blink (13 s) and the tips poll.
   - Fix: run them only during a live level.

8. **The audio engine runs during silence** as long as sound is on.
   - Fix: suspend it after ~10 s with no sound when music is off, and resume on the next sound.

### Confirmed working

- **Resting and sleeping:** idle rest (a level at rest costs ~3 ms/s), the motion gate (tilt off at rest), audio sleep when hidden, water sleep.
- **Light by design:** the iOS canvases draw at 1×. Halloween level 3 at rest costs 12 ms/s and its fog stops at rest.

### Background and native

- **iOS:** on `didEnterBackground`, also call `webView.setAllMediaPlaybackSuspended(true)` and `AVAudioSession.setActive(false)`, and stop motion. Undo all three on `didBecomeActive`.
  - To confirm on the phone: Console.app filtered to `runningboardd` and MonkeyTrubble, to see which assertions are held after leaving the app. Also compare with a Release/TestFlight build.
- **Android:** `onPause` only calls `webView.onPause()` (MainActivity.kt:117). Add `webView.pauseTimers()` in `onPause` and `resumeTimers()` in `onResume`, so the game's timers stop in the background.

---

## 4. Memory investigation (follow-up in headless Chrome)

We replayed the scenes that grew memory on the phone: 6 player cards, then levels 3 → 4 → 3 → 7 → 3 → 8 with auto-pairs and instant wins, collecting garbage before each count.

| After | Page elements | JS heap | Animations | Canvases (pixels) | Images |
|---|---|---|---|---|---|
| Home | 1,453 | 4 MB | 28 | 8 (2.1 M) | 55 |
| 6 player cards | 1,499 | 4 MB | 28 | 8 (2.1 M) | 56 |
| Level 3 | 1,567 | 9 MB | 5 | 9 (3.7 M) | 37 |
| … through level 8 | ~1,600 | 9 MB | ~10 | 9 (3.7 M) | 13–38 |

- **No leak of game objects.** Elements, heap, canvases and images stay flat. Decoded images plus canvases come to only ~60 MB.
- **Small leak to fix anyway:** event listeners grow by ~60–70 per level (340 → 755 over 6 levels).
- **So the 0.5–1.8 GB is WebKit's native drawing memory on iPhone.** That means layer backing stores at 3× (a full-screen layer ≈ 14 MB), masked and rotating layers, and 3D layers. It matches the big always-animating layers in findings 2, 3 and 5:
  - win rays ~70 MB plus mask
  - POLY and streak rays
  - the full-screen sparkle canvas
  - the 20 3D ticker cards

---

## 5. Proposed fix round (not started; waiting for Paul's go)

Every change gets a dev perf switch, so old and new can be compared on the phone.

**A. Memory (crash fix, first)**
1. Win, streak and POLY rays: stop after 1–2 turns; shrink (win rays 160vmax → ~110vmax); remove from the page once their scene closes.
2. Lightbox sparkles: 30 fps, stop after ~8 s idle; a smaller canvas, or released when the lightbox closes.
3. Home ticker: pause and release its 3D cards whenever home is covered or the scenery rests.
4. Fix the event-listener growth per level.
5. Re-test on the phone: memory should stay flat (target under ~400 MB) through player cards, Pick Your Monkey and several levels.

**B. Battery**
1. Home and lightbox idle rest; the byline glow as opacity only.
2. One shared scenery clock at ~30 fps (or lower for drift).
3. The screen-awake lock only during play plus 2 min idle (iOS and Android).
4. Clock, owl and tips timers only during a live level; the tips loop stops once every tip has been seen.
5. Audio engine sleeps after silence.
6. Android: `pauseTimers()` / `resumeTimers()`. iOS: suspend media and deactivate the audio session in the background.

**C. Re-test** with the same 5 device recordings (below) and compare before and after.

---

## 6. How to repeat the device test

Phone plugged in and unlocked; Debug build installed (`/ship`).

```sh
# list devices
xcrun xctrace list devices
# one recording (repeat per scene; change the name and time)
xcrun xctrace record --device 00008120-000C291E1E78C01E --template "Activity Monitor" \
  --instrument Hitches --instrument "Thermal State" --all-processes --time-limit 60s --output 1-home.trace
# per-process CPU and memory table
xcrun xctrace export --input 1-home.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="activity-monitor-process-live"]' > am-1.xml
# crash logs on the phone
xcrun devicectl device info files --device A73156EF-387D-5EEE-A590-A7CD391914B7 --domain-type systemCrashLogs
```

**Scenes:**
1. home idle 60 s
2. a normal level 90 s
3. another app 120 s
4. player cards plus Pick Your Monkey 75 s
5. a Halloween level 90 s

Watch `com.apple.WebKit.WebContent` (the game's web process). Its "Memory" column is what iOS kills on, at about 1.8 GB on this phone.

Note: the `Power Profiler` template can't record all processes at once, so recordings use Activity Monitor; CPU time stands in for power.

---

## 7. Fix round and re-test (2026-10-24, evening)

**Built**, each behind a dev perf switch under PERFORMANCE:
- **`raysLite`:** win and POLY rays are a 512 px image that rotates, instead of 3,000–4,300 px gradient layers with masks. Win rays are 110vmax, not 160, and stop after two turns.
- **`homeRest`:** home animations pause at rest or when home is covered, and the ticker is hidden while covered. This includes the board piece's nudge behind home. The byline glow is a scale swell only.
- **`lightboxRest`:** the card view stops its sparkles, sway and holo after 8 s untouched; a touch wakes it.
- **`sceneShared`:** drift and ambient share one ~30 fps tick.
- **Clock:** it ticks only while a level's clock runs.
- **Screen-awake lock:** on only during a level touched in the last 2 min, on iOS (`screen` message → `isIdleTimerDisabled`) and Android (`FLAG_KEEP_SCREEN_ON` added and cleared).
- **iOS background:** `setAllMediaPlaybackSuspended(true)` plus `AVAudioSession.setActive(false)`, both undone when the app becomes active again.
- **Android:** `pauseTimers()` and `resumeTimers()`.

**Browser main-thread cost (ms per second), old → new:** home idle 58 → ~20 (the test's floor); leaderboard 67 → 21; card left 8 s or more 108 → 31.

**Device re-test (same Activity Monitor recordings):**

| Scene | Before | After |
|---|---|---|
| Home idle, game's web process CPU | 32% | **12.7%** |
| Player cards and Pick Your Monkey, memory | 380 → 945 MB, stayed up | rises to 0.9–1.06 GB while open, **falls back** to 760 MB |
| Halloween level 3 to the win | 840 MB → 1.55 GB, **killed** | swings 440–1,116 MB, ends at 700 MB, **no crash** |

**Found during the re-test and fixed:**
- **Audio after ads.** The "sound after ads" fix restarted a working audio engine after every ad. Its clock check, taken mid-restart, then re-triggered restarts on later taps, so the sound cut out and stuttered (Paul: an ad reward and a puzzle piece at the same time). Now a working engine is left alone, and a truly stalled one is restarted once.
- **Avatar tap-through.** Choosing an avatar closed the picker as the finger lifted, and the phone's follow-up click flipped DIFFICULTY to Easy in Settings. The next click within 0.5 s of a pick is now swallowed.

**Still open:**
- **Memory peaks.** Each open card or player card temporarily costs ~150–250 MB (likely the lightbox card's 3D layers at 3×: face, foil, foil texture, back, glare).
- **Baseline.** ~550–590 MB on a fresh launch.
- **Smaller items:** the card-view sparkles at 30 fps, the audio engine sleeping after silence, the tips loop resting.

---

## 8. Second memory round and final device test (2026-10-24, night)

**Built**, behind the `memLite` perf switch unless noted:
- **Hidden screens:** the level's scenery (3 layers ~17 MB each at 3×, plus the slat and ambient canvases) is off the page while home is up. Home is off the page once its fade-out ends.
- **Card view:** the lightbox card's back face exists only while the card is turned past edge-on, and its holo band is narrower.
- **Sounds:** the Halloween-only sounds (~10 MB decoded) load when a Halloween level is coming.
- **Small battery items:** sparkles at 30 fps; the audio engine naps after 10 s of silence when no music plays (it wakes on a sound or when music starts); the tips loop rests with the scenery.
- **Puzzles:** the painting hint is visible again (14%), with no "goes here" outline; the page turn is now one fluid two-board slide.
- **Win rays:** tapping the win screen no longer stops the rays' turn.

**Final device test** (fresh launch, game's web process):

| Scene | Start of day | Final |
|---|---|---|
| Home idle: memory | 547–585 MB | **510 MB** |
| Home idle: CPU | 32% | **13.9%** |
| Player cards: peak memory | 945–1,065 MB (stayed up) | **783 MB**, settles ~700 MB |
| Halloween level with ads, to the win | climbed to 1.55 GB, **killed** | 380–1,020 MB swings, **ends 575 MB**, no crash |

**Still worth doing later:**
- The peaks during a level (~1 GB) come from the transitions and scenes: the win screen, the POLY show, the streak scene.
- ~72 MB of decoded sounds load at launch; calls could load per chapter.
- Remaining idle CPU on home (~14%) is mostly WebKit compositing the home art and the ticker strip with its edge-fade mask.

---

## 9. Idle hunt and third round (2026-10-24, late)

**Fixes:**
- **Sounds load on demand.** Monkey calls load per level, voice lines only for the current language (the other loads on a switch), and Halloween sounds before Halloween levels. Decoded audio at launch: **72 → 39 MB**.
- **Cage warning.** It no longer runs on the home screen. In a level left alone, it escalates for ~30 s, then gives up until a touch (Paul's "pick up your phone, buddy" idea).
- **Hidden loading screen (the big CPU win).** A Time Profiler run with the 27.2 symbols showed WebKit resolving CSS animations every frame on a resting home screen. A dev FPS-meter diagnostic (running animations by name) found the cause: **the loading screen's `loaderShimmer`**. The loader was only made invisible after launch, so it repainted forever. It now leaves the page. Home idle web CPU: **13% → 2%**.
- **Paused vs removed animations.** iOS's compositor (backboardd) stayed at ~48% because paused CSS animations still keep it busy. At rest, every CSS animation is now frozen in place (values held inline) and removed, then resumed at the same `currentTime` on the next touch. backboardd at home idle: **48% → ~6%**.
- **Puzzle piece position.** The piece is now one step under its card and peeks out below the card's bottom edge, positioned from the card's drawn rectangle.
- **Lighter scenes.** The POLY jackpot glow is a pre-drawn gradient fade, not an inset box-shadow, and the level-end spiral uses 16 cards with no big shadows.
- **Game Center.** The button hides while home rests. This didn't change backboardd, but it does no harm.

**Device timeline with POLY show and streak preview:** home 395 MB → level 581 MB → POLY peak 778 MB → streak peak 704 MB → end 476 MB. No ~1 GB peaks.

**Final home idle on device:** web process ~2%, app ~1%, backboardd ~6%. This morning it was 32% / 9% / 48%.
