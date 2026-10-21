# Monkey calls per card

Picked by Paul on 2026-10-21 with the call picker (~/monkeytrubble_macmini/picker-tools). Calls are listed primary first; the game plays the primary most often (weights 4:3:2:1) and never repeats a card's last call. New calls live in `web/audio/calls/` (Paul's own clipped and EQ'd files, levelled to the -10.5 LUFS call target in MIX_DB).

| Card | Calls (primary first) |
|---|---|
| White-faced Capuchin (`R1_CAPUCHIN`) | callCapuchin, callSmallMonkeyAlt (small monkey alt.mp3), callHuhu, callMonkeys (monkeys.wav) |
| Geoffroy's Spider Monkey (`R1_SPIDER`) | callAnotherSmallMonkey (another small monkey.mp3), callGibbon09Small (gibbon_09 small.mp3), callAnotherAnotherCapuchin (another another capuchin.mp3) |
| Mantled Howler (`R1_HOWLER`) | callHowler, callBarbary, callAgile, callSmallMonkeyAlt (small monkey alt.mp3) |
| Central American Squirrel Monkey (`R1_SQUIRREL`) | callNotherCapuchin (nother capuchin.wav), callCapuchin, callBarbary |
| Geoffroy's Tamarin (`R1_TAMARIN`) | callSmallMonkeyGrunt (small monkey grunt.mp3) |
| Red Howler (`R2_HOWLER`) | callHowler, callLongHowl (long howl.mp3), callGibbon12 (gibbon-compilation_clips/gibbon_12.wav) |
| Emperor Tamarin (`R2_EMPEROR`) | callBaby |
| Pygmy Marmoset (`R2_MARMOSET`) | callBaby |
| Bald Uakari (`R2_UAKARI`) | callYell |
| Woolly Monkey (`R2_WOOLLY`) | callMonkeys (monkeys.wav) |
| Golden Lion Tamarin (`S1_TAMARIN`) | callCapuchin, callBaby |
| Black Howler Monkey (`S2_HOWLER`) | callHowler, callNotherHowl (nother howl.mp3), callMedHowl (med howl.mp3), callNotherHowl2 (nother howl 2.mp3) |
| Heliconia (`F_HELICONIA`) | callSmallmonkey (smallmonkey.wav) |
| Long-tailed Macaque (`S2_LTMACAQUE`) | callBarbary, callSmallMonkeyAlt (small monkey alt.mp3), callBaby |
| Silvered Langur (`S2_SILVERED`) | callMonkeys (monkeys.wav), callMonkeyyell (monkeyyell.wav), callGibbon09Small (gibbon_09 small.mp3), callAnotherSmallMonkey (another small monkey.mp3) |
| Bornean Orangutan (`APE_ORANGUTAN`) | callOranatang (oranatang.mp3) |
| Proboscis Monkey (`S1_PROBOSCIS`) | callLemur3, callHuhu, callLemur1 |
| Yellow-cheeked Gibbon (`S1_YCGIBBON`) | callGibbon09Small (gibbon_09 small.mp3), callAnotherSmallMonkey (another small monkey.mp3), callLilHowl2 (lil howl2.mp3), callNotherHowl (nother howl.mp3) |
| Vervet Monkey (`S1_VERVET`) | callSmallApe |
| Yunnan Snub-nosed Monkey (`S1_SNUBNOSED`) | callMonkeys (monkeys.wav), callYell |
| Squirrel Monkey (`S2_SQUIRREL`) | callMonkeyyell (monkeyyell.wav), callNotherCapuchin (nother capuchin.wav) |
| White-handed Gibbon (`S2_GIBBON`) | callAgile, callHowl (howl.mp3) |
| Golden Snub-nosed Monkey (`S2_GOLDENSNUB`) | callSmallmonkey (smallmonkey.wav) |
| Sumatran Orangutan (`APE_SUMATRAN`) | callOranatang (oranatang.mp3) |
| Siamang (`APE_SIAMANG`) | callDeBrazza, callHowl (howl.mp3), callGibbon12 (gibbon-compilation_clips/gibbon_12.wav), callLongHowl (long howl.mp3) |

## New call files

| Key | Source file in ~/monkeytrubble_macmini | Loudness | Trim |
|---|---|---|---|
| callSmallMonkeyAlt | small monkey alt.mp3 | -13.3 LUFS | +2.8 dB |
| callMonkeys | monkeys.wav | -21.5 LUFS | +11.0 dB |
| callAnotherSmallMonkey | another small monkey.mp3 | -13.5 LUFS | +3.0 dB |
| callGibbon09Small | gibbon_09 small.mp3 | -12.3 LUFS | +1.8 dB |
| callAnotherAnotherCapuchin | another another capuchin.mp3 | -11.7 LUFS | +1.2 dB |
| callNotherCapuchin | nother capuchin.wav | -13.7 LUFS | +3.2 dB |
| callSmallMonkeyGrunt | small monkey grunt.mp3 | -12.5 LUFS | +2.0 dB |
| callLongHowl | long howl.mp3 | -13.4 LUFS | +2.9 dB |
| callGibbon12 | gibbon-compilation_clips/gibbon_12.wav | -12.8 LUFS | +2.3 dB |
| callNotherHowl | nother howl.mp3 | -11.6 LUFS | +1.1 dB |
| callMedHowl | med howl.mp3 | -12.3 LUFS | +1.8 dB |
| callNotherHowl2 | nother howl 2.mp3 | -11.2 LUFS | +0.7 dB |
| callSmallmonkey | smallmonkey.wav | -14.2 LUFS | +3.7 dB |
| callMonkeyyell | monkeyyell.wav | -10.7 LUFS | +0.2 dB |
| callOranatang | oranatang.mp3 | -11.6 LUFS | +1.1 dB |
| callLilHowl2 | lil howl2.mp3 | -13.2 LUFS | +2.7 dB |
| callHowl | howl.mp3 | -11.9 LUFS | +1.4 dB |

Still to cover: cards with no pick keep their old call. monkeys.wav is very quiet (-21.5 LUFS, +11 dB trim); a louder export would sound cleaner.
