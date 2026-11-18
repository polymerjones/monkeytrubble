# Usage: python3 tools/freeze-card.py <source.jpg> <out.jpg>  (made the Ice Age Joker from Poly's portrait, 2026-11-18; original kept as iceage-joker-original.jpg)
# Freezes a card portrait: cold grade, frost creeping from the edges, icicles along the top, falling snow, icy rim glow.
import sys, numpy as np
from PIL import Image, ImageFilter, ImageDraw
src, out = sys.argv[1], sys.argv[2]
rng = np.random.default_rng(11)
im = Image.open(src).convert('RGB'); W, H = im.size
a = np.asarray(im).astype(np.float32) / 255

def blur(x, r):  # gaussian blur of a float array 0..1
    return np.asarray(Image.fromarray((np.clip(x,0,1)*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r))).astype(np.float32)/255
def noise(scales):  # fractal noise
    n = np.zeros((H, W), np.float32); amp = 1; tot = 0
    for s in scales:
        small = rng.random((max(2,H//s), max(2,W//s))).astype(np.float32)
        n += amp*np.asarray(Image.fromarray((small*255).astype(np.uint8)).resize((W,H), Image.BICUBIC)).astype(np.float32)/255
        tot += amp; amp *= .55
    return n/tot

# 1. Cold grade: pull warm tones toward icy cyan-blue, keep the face readable.
lum = (a @ np.array([.299,.587,.114], np.float32))[...,None]
cold = np.concatenate([lum*.62+.02, lum*.86+.05, np.clip(lum*1.08+.16,0,1)], -1)
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
face = np.exp(-(((xx-W*.5)/(W*.30))**2 + ((yy-H*.42)/(H*.26))**2))[...,None]  # keep more original colour on the face
mix = .82 - .52*face
a = a*(1-mix) + cold*mix
a = np.clip((a-.5)*1.06+.52, 0, 1)

# 2. Frost from the edges: distance to the edge, broken up by noise, with crystal streaks.
d = np.minimum(np.minimum(xx, W-1-xx)/W, np.minimum(yy, H-1-yy)/H*1.5)
n = noise([3, 7, 18, 40])
frost = np.clip((0.115 - d + (n-.5)*.13)/0.07, 0, 1)
streak = blur(rng.random((H, W)).astype(np.float32) ** 18, 1.2)
streak = np.clip(streak*9, 0, 1) * np.clip(frost*1.6, 0, 1)
crystals = noise([2, 3]) * frost
frost_col = np.array([.88, .96, 1.0], np.float32)
fa = np.clip(frost*.62 + crystals*.3 + streak*.7, 0, .9)[...,None]
a = a*(1-fa) + frost_col*fa
# soft icy glow inside the frost line
glow = blur(frost, 30)[...,None]
a = np.clip(a + glow*np.array([.05,.12,.2],np.float32)*.9, 0, 1)

img = Image.fromarray((a*255).astype(np.uint8))

# 3. Icicles hanging from the top edge.
ice = Image.new('RGBA', (W, H), (0,0,0,0)); dr = ImageDraw.Draw(ice)
x = 0
while x < W:
    w = int(rng.integers(26, 64)); h = int(rng.integers(40, 190)) if rng.random() > .35 else int(rng.integers(20, 60))
    top = int(rng.integers(0, 18))
    for i in range(h):  # each icicle: a narrowing gradient wedge
        t = i/h; half = (w/2)*(1-t)**1.3; c = int(235 - 50*t); al = int(230*(1-t*.5))
        dr.line([(x+w/2-half, top+i), (x+w/2+half, top+i)], fill=(c, min(255,c+18), 255, al))
    dr.line([(x+w/2-w*.18, top), (x+w/2-w*.05, top+h*.8)], fill=(255,255,255,170), width=3)  # highlight
    x += w + int(rng.integers(-10, 18))
dr.rectangle([0, 0, W, 22], fill=(232, 246, 255, 235))
ice = ice.filter(ImageFilter.GaussianBlur(1.1))
img = Image.alpha_composite(img.convert('RGBA'), ice)

# 4. Snow: small sharp flakes plus a few big soft ones near the lens.
snow = Image.new('RGBA', (W, H), (0,0,0,0)); ds = ImageDraw.Draw(snow)
for _ in range(520):
    r = float(rng.choice([1.2, 1.8, 2.6, 3.4], p=[.45, .3, .17, .08])); px, py = rng.random()*W, rng.random()*H
    ds.ellipse([px-r, py-r, px+r, py+r], fill=(255, 255, 255, int(rng.integers(150, 245))))
snow = snow.filter(ImageFilter.GaussianBlur(.8))
big = Image.new('RGBA', (W, H), (0,0,0,0)); db = ImageDraw.Draw(big)
for _ in range(26):
    r = rng.uniform(7, 16); px, py = rng.random()*W, rng.random()*H
    if abs(px-W*.5) < W*.22 and abs(py-H*.42) < H*.2: continue  # keep big flakes off the face
    db.ellipse([px-r, py-r, px+r, py+r], fill=(255, 255, 255, int(rng.integers(90, 160))))
big = big.filter(ImageFilter.GaussianBlur(5))
img = Image.alpha_composite(Image.alpha_composite(img, snow), big)
img.convert('RGB').save(out, quality=94)
print('ok', out)
