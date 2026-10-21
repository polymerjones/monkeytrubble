# Monkey calls per card

Picked by Paul on 2026-10-21 with the call picker (~/monkeytrubble_macmini/picker-tools), two rounds. Calls are listed primary first; the game plays the primary most often (weights 4:3:2:1, `pickCall`) and never repeats a card's last call. Paul's own clipped and EQ'd calls live in `web/audio/calls/`, levelled to the -10.5 LUFS call target in MIX_DB (trim = -10.5 - measured LUFS; clips under 0.4 s are matched by mean level instead).

| Card | Calls (primary first) |
|---|---|
| White-faced Capuchin (`R1_CAPUCHIN`) | callCapuchin, callSmallMonkeyAlt, callHuhu, callMonkeys |
| Geoffroy's Spider Monkey (`R1_SPIDER`) | callGeofry, callSpider5, callAnotherAnotherCapuchin |
| Mantled Howler (`R1_HOWLER`) | callHowler, callBarbary, callAgile, callSmallMonkeyAlt |
| Central American Squirrel Monkey (`R1_SQUIRREL`) | callNotherCapuchin, callCapuchin, callBarbary, callSpider1 |
| Geoffroy's Tamarin (`R1_TAMARIN`) | callSmallMonkeyGrunt, callSpider2, callSpider5 |
| Red Howler (`R2_HOWLER`) | callHowler, callLongHowl, callGibbon12 |
| Emperor Tamarin (`R2_EMPEROR`) | callGeofry, callBaby, callAnotherAnotherCapuchin |
| Pygmy Marmoset (`R2_MARMOSET`) | callSpider2, callSpider4, callBaby |
| Bald Uakari (`R2_UAKARI`) | callYell, callLilHowl2 |
| White-faced Saki (`R2_SAKI`) | callGuereza, callMoreGibbonYell |
| Woolly Monkey (`R2_WOOLLY`) | callMonkeys, callMonkeyyell, callMoreGibbonYell |
| Golden Lion Tamarin (`S1_TAMARIN`) | callCapuchin, callSpider1, callBaby, callSpider4 |
| Golden Lion Tamarin (`S2_TAMARIN`) | callYetNotherSmallMonkey, callBaby, callSmallmonkey, callSpider3 |
| Black Howler Monkey (`S2_HOWLER`) | callHowler, callNotherHowl, callMedHowl, callNotherHowl2 |
| Heliconia (`F_HELICONIA`) | callSmallmonkey |
| Banana (`F_BANANA`) | callGibbon12, callMonkeys |
| Proboscis Monkey (`S2_PROBOSCIS`) | callLemur2, callLemur1 |
| Long-tailed Macaque (`S2_LTMACAQUE`) | callBarbary, callSmallMonkeyAlt, callBaby, callMonkeys |
| Silvered Langur (`S2_SILVERED`) | callMonkeys, callMonkeyyell, callGibbon09Small, callAnotherSmallMonkey |
| Bornean Orangutan (`APE_ORANGUTAN`) | callOranatang |
| Squirrel Monkey (`S1_SQUIRREL`) | callMonkeysqueak3, callMonkeysqueak2, callMonkeySqueak |
| Proboscis Monkey (`S1_PROBOSCIS`) | callLemur3, callLemur2, callLemur1 |
| Spider Monkey (`S1_SPIDER`) | callBaby, callYell |
| Silvery Gibbon (`S1_SILVERY`) | callGibbonSqueal1, callGibbonYell, callGibbonSqueal2 |
| Yellow-cheeked Gibbon (`S1_YCGIBBON`) | callGibbon09Small, callAnotherSmallMonkey, callLilHowl2, callNotherHowl |
| Vervet Monkey (`S1_VERVET`) | callSmallApe, callAnotherSmallMonkey, callNotherCapuchin |
| Mangabey (`S1_MANGABEY`) | callGuereza, callHowler, callSmallmonkey |
| Yunnan Snub-nosed Monkey (`S1_SNUBNOSED`) | callMonkeys, callYell, callSmallmonkey |
| Squirrel Monkey (`S2_SQUIRREL`) | callSpider4, callSpider1, callSpider2, callNotherCapuchin |
| White-handed Gibbon (`S2_GIBBON`) | callAgile, callHowl |
| Golden Snub-nosed Monkey (`S2_GOLDENSNUB`) | callSmallmonkey, callLilHowl2, callAgile |
| Sumatran Orangutan (`APE_SUMATRAN`) | callOranatang |
| Siamang (`APE_SIAMANG`) | callDeBrazza, callHowl, callGibbon12, callLongHowl |

## Call files in web/audio/calls

| Key | Source in ~/monkeytrubble_macmini | Trim (dB) |
|---|---|---|
| callAnotherAnotherCapuchin | another another capuchin.mp3 | 1.2 |
| callAnotherSmallMonkey | another small monkey.mp3 | 3.0 |
| callGeofry | geofry.mp3 | 8.2 |
| callGibbon09Small | gibbon_09 small.mp3 | 1.8 |
| callGibbon12 | gibbon-compilation_clips/gibbon_12.wav | 2.3 |
| callGibbonSqueal1 | gibbon squeal 1.mp3 | 0.8 |
| callGibbonSqueal2 | gibbon squeal 2.mp3 | 1.4 |
| callGibbonYell | gibbon yell.mp3 | 2.6 |
| callHowl | howl.mp3 | 1.4 |
| callLilHowl2 | lil howl2.mp3 | 2.7 |
| callLongHowl | long howl.mp3 | 2.9 |
| callMedHowl | med howl.mp3 | 1.8 |
| callMonkeySqueak | monkey squeak.mp3 | 5.6 |
| callMonkeys | monkeys.mp3 | 8.6 |
| callMonkeysqueak2 | monkeysqueak2.mp3 | 6.6 |
| callMonkeysqueak3 | monkeysqueak3.mp3 | 5.1 |
| callMonkeyyell | monkeyyell.mp3 | 0.2 |
| callMoreGibbonYell | more gibbon yell.mp3 | -1.7 |
| callNotherCapuchin | nother capuchin.mp3 | 3.2 |
| callNotherHowl | nother howl.mp3 | 1.1 |
| callNotherHowl2 | nother howl 2.mp3 | 0.7 |
| callOranatang | oranatang.mp3 | 1.1 |
| callSmallMonkeyAlt | small monkey alt.mp3 | 2.8 |
| callSmallMonkeyGrunt | small monkey grunt.mp3 | 2.0 |
| callSmallmonkey | smallmonkey.mp3 | 3.7 |
| callSpider1 | spider1.mp3 | 8.8 |
| callSpider2 | spider2.mp3 | 6.6 |
| callSpider3 | spider3.mp3 | 4.1 |
| callSpider4 | spider4.mp3 | 6.6 |
| callSpider5 | spider5.mp3 | 5.4 |
| callYetNotherSmallMonkey | yet nother small monkey.mp3 | 2.5 |

Cards not listed keep their earlier calls. If any call is clipped from a Creative Commons recording (see ~/monkeytrubble_macmini/freesound/CREDITS.txt), the game must credit its author.
