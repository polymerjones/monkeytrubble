#!/bin/sh
# Builds the downsized card artwork the game loads (cards/thumb, cards/hero) from ../source/art/raw images.
# IMG_*.JPG portraits keep their names; the named sources below are written under a slug.
set -e
cd "$(dirname "$0")/.."
RAW="../source/art/raw images"
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
# Crops an h x w (2:3) window at offset y,x out of a source before resizing, to frame a subject that sits small in the shot.
build_crop() {
  sips -s format jpeg -c "$3" "$4" --cropOffset "$5" "$6" "$1" --out "$TMP/$2.jpg" >/dev/null
  build "$TMP/$2.jpg" "$2"
}
for src in "$RAW"/IMG_*.JPG; do
  build "$src" "$(basename "$src" .JPG)"
done
build_portrait "$RAW/caulin doll 2.png" caulin-plush
build_portrait "$RAW/caulin bono.jpg" caulin-joker
build_portrait "$RAW/monkey patriot 1.jpg" patriot-1
build_portrait "$RAW/monkey patriot 3.jpg" patriot-3
# Halloween pack (haunted primates, ../source/art/halloween): ids follow Monkey_Trubble_Haunted_Primate_Prompts.md.
HW="../source/art/halloween"
build "$HW/IMG_7758.JPG" halloween-01-howler
build "$HW/IMG_7753.JPG" halloween-02-capuchin
build "$HW/IMG_7754.JPG" halloween-03-lemur
build "$HW/IMG_7757.JPG" halloween-04-mandrill
build "$HW/IMG_7756.JPG" halloween-05-spider
build "$HW/IMG_7755.JPG" halloween-06-gorilla
build "$HW/IMG_7759.JPG" halloween-07-proboscis
build "$HW/IMG_7761.JPG" halloween-08-tamarin
build "$HW/IMG_7765.JPG" halloween-09-aye-aye
build "$HW/snub.jpg" halloween-10-snub
build_portrait "$HW/tarsier.png" halloween-13-tarsier
build_portrait "$HW/redrufflemur.png" halloween-14-ruffed-lemur
build "$HW/IMG_7750.JPG" halloween-01b-midnight-howler
build_portrait "$HW/whitefacesaki.png" halloween-15-saki
build_portrait "$HW/balduakari.png" halloween-16-uakari
build_portrait "$HW/pigmymarmoset.png" halloween-17-marmoset
build_portrait "$HW/Sulawesi Crested Black Macaque Macaca nigra.png" halloween-18-crested-macaque
build_portrait "$HW/orangatuang.png" halloween-19-orangutan
build_portrait "$HW/whitehandgibbon.png" halloween-20-gibbon
# Halloween Joker (replaces Caulin on Halloween levels): the framed render is the official card art.
build_portrait "$HW/jokerhowler-real.png" halloween-joker
# Kevin Kelly: flat 2:3 Grok render (1152x1728), so a plain resize.
build "$RAW/kevin kelly.jpg" kevin-kelly
echo "thumb: $(ls cards/thumb | wc -l | tr -d ' ')  hero: $(ls cards/hero | wc -l | tr -d ' ')"
