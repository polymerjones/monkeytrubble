#!/bin/sh
# Builds the jigsaw puzzle paintings (art/puzzles/chN.jpg, 720x1280) from the full chapter paintings in ../source/art/chapters.
# Chapter 11's painting is 2:3, so a centred 9:16 window is cut out of it first.
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
