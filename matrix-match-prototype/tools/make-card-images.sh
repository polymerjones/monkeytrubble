#!/bin/sh
# Builds the downsized card artwork the game loads (cards/thumb, cards/hero) from ../matrix-match-source/raw images.
# IMG_*.JPG portraits keep their names; the named sources below are written under a slug.
set -e
cd "$(dirname "$0")/.."
RAW="../matrix-match-source/raw images"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p cards/thumb cards/hero
build() {
  sips -s format jpeg -s formatOptions 72 -z 480 320 "$1" --out "cards/thumb/$2.jpg" >/dev/null
  sips -s format jpeg -s formatOptions 76 -z 768 512 "$1" --out "cards/hero/$2.jpg" >/dev/null
}
# Crops a centred 2:3 portrait out of a square or landscape source before resizing.
build_portrait() {
  h=$(sips -g pixelHeight "$1" | awk '/pixelHeight/{print $2}')
  w=$((h * 2 / 3))
  sips -s format jpeg -c "$h" "$w" "$1" --out "$TMP/$2.jpg" >/dev/null
  build "$TMP/$2.jpg" "$2"
}
for src in "$RAW"/IMG_*.JPG; do
  build "$src" "$(basename "$src" .JPG)"
done
build_portrait "$RAW/caulin doll 2.png" caulin-plush
build_portrait "$RAW/caulin bono.jpg" caulin-joker
build_portrait "$RAW/monkey patriot 1.jpg" patriot-1
build_portrait "$RAW/monkey patriot 3.jpg" patriot-3
# Kevin Kelly: flat 2:3 Grok render (1152x1728), so a plain resize.
build "$RAW/kevin kelly.jpg" kevin-kelly
echo "thumb: $(ls cards/thumb | wc -l | tr -d ' ')  hero: $(ls cards/hero | wc -l | tr -d ' ')"
