#!/bin/sh
# Builds the jigsaw puzzle paintings (art/puzzles/<img>.jpg, 720x1280): the chapter paintings from ../source/art/chapters and the extra
# puzzles from ../source/art/puzzles (PUZZLES in index.html). 2:3 paintings (chapter 11, the POLY pair) get a centred 9:16 window cut first.
# Also bakes announce-bw.jpg, a small black-and-white painting for the puzzles welcome card (no CSS filter at run time).
set -e
cd "$(dirname "$0")/.."
SRC="../source/art/chapters"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p art/puzzles
build() { sips -s format jpeg -s formatOptions 58 -z 1280 720 "$1" --out "art/puzzles/$2.jpg" >/dev/null; }
build "$SRC/ch1_thebridgebg.png" ch1
build "$SRC/ch2_enterjungle.png" ch2
build "$SRC/ch3_theswamp.png" ch3
build "$SRC/ch4_thecloudforest.png" ch4
build "$SRC/ch5_thesavannah.png" ch5
build "$SRC/ch6_deepjungle.png" ch6
build "$SRC/ch7_frozenmountains.png" ch7
build "$SRC/ch8_forgottenisland.png" ch8
build "$SRC/ch9_thelosttemple.png" ch9
build "$SRC/ch10_kingdomofthecanopy.png" ch10
sips -s format jpeg -c 1728 972 "$SRC/ch11_iceage.png" --out "$TMP/ch11.jpg" >/dev/null
build "$TMP/ch11.jpg" ch11
# Extra puzzles (Paul 2026-10-30): the 9:16 home backgrounds as they are, the 512x768 POLY paintings cut to 432x768 and scaled up.
EXTRA="../source/art/puzzles"
for n in bg-3 bg-4 bg-B bg-E; do build "$EXTRA/$n.jpg" "$n"; done
for n in poly poly-christmas; do sips -s format jpeg -c 768 432 "$EXTRA/$n.jpg" --out "$TMP/$n.jpg" >/dev/null; build "$TMP/$n.jpg" "$n"; done
# The welcome card's black-and-white painting.
sips -s format jpeg -s formatOptions 60 -z 640 360 -m "/System/Library/ColorSync/Profiles/Generic Gray Profile.icc" "$SRC/ch1_thebridgebg.png" --out art/puzzles/announce-bw.jpg >/dev/null
