# Assembles cards from a card background plus symbol images saved over a fake transparency checkerboard (Grok/GPT exports).
# The checkerboard is grey/white (no colour) and the symbols are coloured, so alpha comes from each pixel's chroma
# (max-min of RGB), and the checker's grey is removed from anti-aliased edges so they don't keep a white fringe.
# The symbol is then pressed into the card like gold foil: thin cream detail lines become grooves showing the card,
# big cream areas (faces) stay, and a bevel plus a soft drop shadow give it depth.
# Run: python3 web/tools/assemble-cards.py <folder>   (folder holds bg.jpg and the symbol images)
# Writes <folder>/cutouts/<name>.png (transparent symbol) and <folder>/cards/<name>.jpg (symbol centred on bg).
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

LO, HI = 10, 32      # chroma at or below LO is checkerboard (fully clear); at or above HI is fully symbol
FILL = .74           # symbol's share of the card's inner frame (width or height, whichever binds first)
INNER = (.075, .055, .925, .945)  # inside of the bg frame as fractions of width/height: left, top, right, bottom
KEEP_CREAM = False  # see cutout()
GROOVE = 25          # cream strokes thinner than this (px, source scale) become grooves; wider cream areas stay


def blur(a, r):
    return np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r))).astype(np.float32) / 255


def morph(a, size, op):
    im = Image.fromarray((a * 255).astype(np.uint8))
    return np.asarray(im.filter(op(size))).astype(np.float32) / 255


def cutout(path):
    rgb = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    chroma = rgb.max(2) - rgb.min(2)
    a = np.clip((chroma - LO) / (HI - LO), 0, 1)
    # Light speckle in the checker (JPEG noise) can pass LO; a small open removes isolated specks.
    a = np.minimum(a, morph(morph(a, 3, ImageFilter.MinFilter), 3, ImageFilter.MaxFilter))
    # Edge pixels are a*fg + (1-a)*bg with bg the checker's grey; solve for fg using the local grey level.
    bg = rgb.min(2, keepdims=True).clip(200, 255)
    a3 = a[..., None]
    fg = np.where(a3 > .02, (rgb - (1 - a3) * bg) / np.maximum(a3, .02), rgb).clip(0, 255)
    # Cream detail: light, low-blue-deficit pixels inside the symbol. Thin strokes of it are cut out as grooves.
    cream = np.clip((fg[..., 2] - 110) / 30, 0, 1) * (a > .5)
    cream = blur(cream, 1.2)
    # Wide = cream that is still mostly cream after a round blur the size of a groove, grown back to its outline.
    # KEEP_CREAM False cuts all cream (papercut look: faces read as gold outlines on the card).
    core = np.clip((blur(cream, GROOVE / 2) - .7) * 6, 0, 1)
    wide = np.clip(blur(core, GROOVE / 2) * 2.5, 0, 1) * cream * KEEP_CREAM
    a = a * (1 - np.clip((cream - wide) * 1.6, 0, 1))
    # The cream areas that stay are evened out to one pale gold, so JPEG blotches don't show through the bevel.
    k = (wide * cream)[..., None]
    fg = fg * (1 - k) + np.array([246, 218, 150]) * k
    out = Image.fromarray(np.dstack([fg, a * 255]).astype(np.uint8))
    return out.crop(out.getbbox())


def press(card, sym, x, y):
    """Composite sym (RGBA) onto card at x,y as embossed gold foil with a soft shadow."""
    w, h = sym.size
    pad = 24
    rgba = np.zeros((h + 2 * pad, w + 2 * pad, 4), np.float32)
    rgba[pad:pad + h, pad:pad + w] = np.asarray(sym).astype(np.float32)
    a = rgba[..., 3] / 255
    col = rgba[..., :3]
    # Bevel: light from the top left on a height map made from the blurred alpha.
    hgt = blur(a, 2.5)
    gy, gx = np.gradient(hgt)
    shade = np.clip((-gx - gy) * 9, -1, 1)
    col = col * (1 + .45 * shade[..., None]) + 60 * np.clip(shade, 0, 1)[..., None] ** 2
    # Slightly darker toward the inside edges so the foil reads as pressed, brighter in the middle of wide areas.
    inner = blur(a, 6)
    col = col * (.82 + .22 * inner[..., None])
    col = col.clip(0, 255)
    # Shadow: dark green, below right, soft.
    sh = np.roll(np.roll(blur(a, 5), 5, 0), 3, 1) * .6
    region = np.asarray(card.crop((x - pad, y - pad, x - pad + w + 2 * pad, y - pad + h + 2 * pad))).astype(np.float32)
    region = region * (1 - sh[..., None]) + np.array([4, 18, 10]) * sh[..., None]
    region = region * (1 - a[..., None]) + col * a[..., None]
    card.paste(Image.fromarray(region.clip(0, 255).astype(np.uint8)), (x - pad, y - pad))


def assemble(folder):
    folder = Path(folder)
    bg = Image.open(folder / 'bg.jpg').convert('RGB')
    W, H = bg.size
    l, t, r, b = INNER[0] * W, INNER[1] * H, INNER[2] * W, INNER[3] * H
    (folder / 'cutouts').mkdir(exist_ok=True)
    (folder / 'cards').mkdir(exist_ok=True)
    for f in sorted([*folder.glob('*.jp*g'), *folder.glob('*.png')]):
        if f.stem == 'bg':
            continue
        sym = cutout(f)
        sym.save(folder / 'cutouts' / f'{f.stem}.png')
        s = min((r - l) * FILL / sym.width, (b - t) * FILL / sym.height)
        sym = sym.resize((round(sym.width * s), round(sym.height * s)), Image.LANCZOS)
        card = bg.copy()
        press(card, sym, round((l + r - sym.width) / 2), round((t + b - sym.height) / 2))
        card.save(folder / 'cards' / f'{f.stem}.jpg', quality=92)
        print(f.stem, sym.size)


if __name__ == '__main__':
    assemble(sys.argv[1] if len(sys.argv) > 1 else '.')
