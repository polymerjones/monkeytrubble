# Monkey Trubble development backlog

The persistent backlog, kept by Claude (Master Development Directive, 2026-11-26). Newest first within each section.

**Labels:**
- `[sim]`: verified in headless Chrome or mock only.
- `[device]`: verified on Paul's iPhone.
- `[code]`: implemented, not yet verified.

## Release target: 1.1.3 (iOS build 21 / Android vc 30)
Status: in progress. Plan: `~/.claude/plans/hi-there-good-morning-cozy-journal-of-58c48a0f-09f7-459d-8caf-82b77ed768f0.md`

## Bugs and root causes
| Bug (reported) | Root cause | Status |
|---|---|---|
| Chapter puzzles 6–11 (Ice Age Battle) missing, badge stuck (11-25) | `chapterFor().number` restarts every 55-level lap; `puzzlesOpen` used it | Fixed `[device]` |
| Can't start a new shared puzzle after finishing (11-25) | `duo.state` and `pz.duo` stale after finishing; only a relaunch reloaded them | Fixed `[sim]`, old code reproduced the bug |
| Few shared pieces (11-25) | stale `duoList()` skipped the server call; a piece found after skipping the win screen was dropped | Fixed `[sim]`, chance 40% → 60% |
| Power-ups show 1 instead of 40s (11-25) | Display only: the badge showed free uses only | Fixed `[sim]` (shows free + bank) |
| Card stuck big over the board (11-25, L135) | Second finger on a lifted card re-lifted it; the first drag ghost was orphaned with its rAF loop still running | Fixed `[sim]`, reproduced on old code |
| Possible: shared puzzle never finishes | `duo_place` count race without a lock | SQL ready, **Paul runs it** |
| Christmas boards show a non-Christmas Joker | JOKER has no `christmas` art; `packVariant` falls through to chapter art | Needs Paul (art) |

## Fixed this cycle (1.1.3)
See git log from 93b9021.

## Testing owed (needs Paul's device)
- Drag ghost on a real device: second finger mid-drag, Notification Center and swipe-home mid-drag.
- Shared puzzle with a real friend: finish, then start a new one with the same friend, no relaunch.

## Needs Paul
- **Run SQL:** `web/supabase/migrations/2026-11-26-duo-place-lock.sql` (instructions in the file).
- **Ice Age crops:** approve `~/Downloads/MonkeyTrubble-IceAge-Review/`.
- **Christmas Joker:** paint one, or reuse Santa POLY?

## Pending art
- Christmas Joker (see above).
- More puzzle paintings for long-term progression.
- From memory/pending-content: Madagascar, Savannah and Frozen rosters, seasonal POLY, Spanish lines.

## Proposals (separate projects, not in 1.1.3)
- **Real push notifications** (APNs + FCM, device tokens, Supabase trigger). Next project after 1.1.3, and a prerequisite for tournaments. `docs/proposals/push-notifications.md`.
- **Troop Tournaments:** `docs/proposals/friend-tournaments.md`.
- **Long-term puzzle progression:** a new painting per lap, seasonal sets, golden re-builds.
- **Staging Supabase project** for real integration and concurrency tests. Paul creates it.

## Tech debt
- **iCloud booster merge** uses `Math.max` per bank key, so spent boosters can come back. Deferred: it needs a design that never loses earned boosters (see memory no-inventory-loss).
- **The public web build** (monkeytrubble.app) allows `?dev` and three taps for dev mode. Store builds are locked.
- **iOS 1.1 build 17** clients ignore shared puzzles, but `duo_invite` can still target them.
- **The tests** extract functions from index.html by text, so renames break them.

## Release checklist (each store build)
- [ ] `node tools/check-deals.mjs` (baseline: 24 problems at 300 levels), `check-tutorial`, `check-scoring`, `check-puzzles`, `check-social`, `check-drag`
- [ ] `node tools/perf-check.mjs` (no regression)
- [ ] Display Zoom layouts 320×693 and 614×320, iPad landscape
- [ ] RELEASE_NOTES version = MARKETING_VERSION = versionName; every line has Spanish
- [ ] `sw.js` CACHE bumped
- [ ] Release config: no dev tools (`__monkeyDevTaps=false`)
- [ ] Pending SQL run by Paul, and older clients still work
- [ ] Ship to PolyiPhonePro and Paul plays; Android emulator smoke test
- [ ] Paul authorizes push and store submission
