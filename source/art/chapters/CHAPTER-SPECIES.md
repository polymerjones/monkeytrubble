# Chapter species and art plan

Working list for the next round of card and background art. Each chapter is tied to one real region, so every card in a chapter can share a look and the species are where they actually live. It replaces the mixed-continent picks in `level-ref.png`.

## Species per chapter

| Chapter | Region | Monkeys | Apes |
|---|---|---|---|
| 1 The Bridge | Central America | White-faced capuchin, Geoffroy's spider monkey, mantled howler, squirrel monkey, Geoffroy's tamarin | none |
| 2 Enter the Jungle | Amazon | Red howler, emperor tamarin, pygmy marmoset, bald uakari, white-faced saki, woolly monkey | none |
| 3 The Swamp | Borneo peat swamps and mangroves | Proboscis monkey, long-tailed macaque, silvered langur | Bornean orangutan, Bornean gibbon |
| 4 The Cloud Forest | Rwanda and Uganda volcano forests | Golden monkey, L'Hoest's monkey, Rwenzori colobus | Mountain gorilla, eastern chimpanzee |
| 5 The Savannah | East and West African savanna | Olive baboon, yellow baboon, vervet, patas monkey | Savanna chimpanzee (Senegal) |
| 6 The Deep Jungle | Congo Basin | Mandrill, drill, red colobus, mangabey, De Brazza's monkey | Western lowland gorilla, chimpanzee, bonobo |
| 7 The Frozen Mountains | Snowy Asian and North African mountains | Japanese macaque, golden snub-nosed, Yunnan snub-nosed, Tibetan macaque, Barbary macaque | none |
| 8 The Forgotten Island | Madagascar | Ring-tailed lemur, sifaka, indri, ruffed lemurs | none |
| 9 The Lost Temple | Angkor and Indian temples | Long-tailed macaque, pig-tailed macaque, gray langur, rhesus macaque, dusky leaf monkey | Pileated gibbon (reintroduced at Angkor) |
| 10 Kingdom of the Canopy | Sumatra | Thomas's langur, Sumatran surili | Sumatran orangutan, siamang, white-handed gibbon |

Great apes live wild only in Africa and on Borneo and Sumatra, so chapters 1, 2, 7 and 8 have none. The snub-nosed monkeys sit in chapter 7 so that chapter 4 can be the mountain gorilla's chapter.

## Card art

- **One look per chapter.** Write one prompt template per chapter and reuse it for every card in it: same light, palette, backdrop and framing. Only the animal changes.
- **Avoid the plastic AI look.** Ask for painterly, soft fur, muted midtones, and no HDR or oversharpening.
- **Size:** 2:3 portrait, at least 1024×1536, with no text or border. The game builds its own smaller copies.

## Backgrounds

- **Build depth from layers.** Each chapter takes three layers that move at different speeds as the phone tilts:
  - `far.jpg`: sky and distant hills in haze
  - `mid.png`: trees, with a transparent background
  - `near.png`: foliage framing the edges, with a transparent background
- **Soften the distance.** Ask for atmospheric haze and depth of field instead of everything sharp.
- **Size:** portrait, at least 941×1672 (the size of the current backgrounds). The layers are drawn about 36% larger than the board so they can move, so keep important detail away from the edges.

## Adding art to the game

- **Card source files:** `source/art/expedition/`. Add a `build` line in `web/tools/make-card-images.sh` and run it.
- **Background source files:** `source/art/chapters/ch<n>_*.png`. The script builds `web/art/chapters/<n>/far.jpg`. For now, put `mid.png` and `near.png` straight into `web/art/chapters/<n>/`; the build script doesn't handle them yet.
- **Featured species:** set in `CHAPTERS` in `web/index.html`. Species waiting for art are in `CARD_DATA` with `pending:true`; delete that flag once the art is built.
- **Full steps:** "Chapter art and the Expedition set" in `web/README.md`.

Chapter assignments in `web/index.html` still follow `level-ref.png` and need updating to this table once the new art is in.
