"""Splits each painted chapter background into far / mid / near parallax layers and softens them.

Run from this folder with a Python that has torch, transformers, opencv-python-headless and Pillow:
    python split-layers.py            # every chapter
    python split-layers.py 3 7        # just these chapters
Reads ch<n>_*.png here and writes layers/<n>/far.jpg, mid.webp, near.webp (and water.png for chapters with
animated water). web/tools/make-card-images.sh copies layers/<n>/ into web/art/chapters/<n>/.

How it works: Depth Anything V2 estimates each pixel's distance. The nearest ~18% of the picture becomes the
near layer and the next band the mid layer. Every layer behind another gets scenery filled in (by the LaMa model if present, see
LAMA_PATH, else mirrored from beside it) wherever the nearer layer covers it: the far layer behind the mid and near objects, the mid layer behind the near
ones. So when the phone tilts and a nearer layer slides, it reveals that fill rather than a ghost copy of the
object. Water (water.png) stays real on the far layer, where the game animates it. Then every layer gets lower
contrast and a little blur, the far layer the most (atmospheric haze).
"""
import sys, re, glob, os
import numpy as np, cv2
from PIL import Image, ImageFilter

# ground: fraction of the height where the water starts (water chapters only).
# water: 'rows' = everything below the ground line is water; 'color' = only the blue water pixels below it.
# mid_min: overrides MID_MIN for one chapter.
CHAPTERS = {
    1: {}, 2: {}, 3: dict(ground=.60, water='rows', mid_min=.16), 4: {}, 5: {}, 6: {},
    7: dict(ground=.52, water='color'), 8: {}, 9: {}, 10: {},
}
MID_PCT, NEAR_PCT = 40, 82          # depth percentiles where the mid and near bands start
MID_MIN, NEAR_MIN = .2, .5          # ...but never closer to the far end than this (depth is 0 far to 1 near)
_pipe = None

def depth(img):
    global _pipe
    if _pipe is None:
        from transformers import pipeline
        import torch
        _pipe = pipeline('depth-estimation', model='depth-anything/Depth-Anything-V2-Small-hf',
                         device='mps' if torch.backends.mps.is_available() else 'cpu')
    d = _pipe(img)['predicted_depth'].squeeze().cpu().numpy()
    d = np.array(Image.fromarray(d.astype('float32')).resize(img.size, Image.BICUBIC))
    return (d - d.min()) / (d.max() - d.min())

def ramp(x, a, w=.05):
    return np.clip((x - (a - w)) / (2 * w), 0, 1)

def soften(rgb, contrast, blur, lift):
    rgb = rgb.astype('float32'); mean = rgb.mean(axis=(0, 1))
    rgb = (rgb - mean) * contrast + mean
    rgb = rgb * (1 - lift) + (mean * .5 + 235 * .5) * lift          # lift toward a light version of the scene's own colour
    return np.array(Image.fromarray(rgb.clip(0, 255).astype('uint8')).filter(ImageFilter.GaussianBlur(blur)))

def water_mask(img, H, W, cfg):
    g = int(H * cfg['ground'])
    rows = np.clip((np.arange(H) - g) / 40, 0, 1)[:, None] * np.ones((1, W))
    if cfg['water'] == 'rows':
        return rows.astype('float32')
    hsv = cv2.cvtColor(img, cv2.COLOR_RGB2HSV).astype('float32')
    h, s, v = hsv[..., 0], hsv[..., 1] / 255, hsv[..., 2] / 255
    blue = ((h > 80) & (h < 130) & (s > .16) & (v < .97)).astype('uint8') * 255   # OpenCV hue is 0-180
    blue = cv2.morphologyEx(blue, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
    blue = cv2.morphologyEx(blue, cv2.MORPH_OPEN, np.ones((9, 9), np.uint8))
    return (cv2.GaussianBlur(blue.astype('float32') / 255, (0, 0), 6) * rows).astype('float32')

def mirror_fill(img, hole):
    """Fills each row's hole runs by mirroring the real pixels just beside them (from whichever side is nearer).
    The strip a tilt uncovers is always next to an edge, so it gets genuine texture there instead of a colour smear."""
    out = img.copy(); H, W = hole.shape; h = hole > 127
    for y in range(H):
        row = h[y]
        if not row.any(): continue
        d = np.diff(np.concatenate([[0], row.astype('int8'), [0]]))
        for a, b in zip(np.flatnonzero(d == 1), np.flatnonzero(d == -1)):
            x = np.arange(a, b)
            lx = 2 * a - 1 - x; rx = 2 * b - 1 - x          # mirror images of x about the left and right edges
            use_left = (x - a < b - x) & (lx >= 0) | (rx >= W)
            src = np.clip(np.where(use_left, lx, rx), 0, W - 1)
            out[y, a:b] = img[y, src]
    return out

# Optional LaMa inpainting model (big-lama.pt, TorchScript): paints believable scenery into the fills instead of mirroring.
# Looked for at $LAMA_MODEL, then ~/models/big-lama.pt. Without it the script uses mirror_fill.
LAMA_PATH = os.environ.get('LAMA_MODEL') or os.path.expanduser('~/models/big-lama.pt')
_lama = None

def lama_fill(img, hole):
    global _lama
    import torch
    if _lama is None:
        _lama = torch.jit.load(LAMA_PATH, map_location='cpu').eval()
    H, W = hole.shape; ph, pw = (8 - H % 8) % 8, (8 - W % 8) % 8      # the model wants sides divisible by 8
    im = np.pad(img, ((0, ph), (0, pw), (0, 0)), mode='reflect').astype('float32') / 255
    mk = np.pad((hole > 127).astype('float32'), ((0, ph), (0, pw)), mode='reflect')
    with torch.inference_mode():
        out = _lama(torch.from_numpy(im).permute(2, 0, 1)[None], torch.from_numpy(mk)[None, None])
    return (out[0].permute(1, 2, 0).numpy()[:H, :W] * 255).clip(0, 255).astype('uint8')

def inpaint(img, hole):
    """Paints over hole (uint8 mask) with LaMa when available, else with mirrored nearby texture (softened so the
    mirroring doesn't read as a pattern), and blends the fill in softly."""
    fill = lama_fill(img, hole) if os.path.exists(LAMA_PATH) else cv2.GaussianBlur(mirror_fill(img, hole), (0, 0), 1.5)
    m = cv2.GaussianBlur(hole.astype('float32') / 255, (0, 0), 2)[..., None]
    return (img * (1 - m) + fill * m).astype('float32')

def split(n):
    src = glob.glob(f'ch{n}_*.png')[0]; cfg = CHAPTERS[n]
    img = np.array(Image.open(src).convert('RGB')); H, W = img.shape[:2]
    v = cv2.GaussianBlur(depth(Image.fromarray(img)).astype('float32'), (0, 0), 3)
    # Percentile bands, with a floor so open scenes (distant mountains, sky) stay on the far layer.
    t1, t2 = max(np.percentile(v, MID_PCT), cfg.get('mid_min', MID_MIN)), max(np.percentile(v, NEAR_PCT), NEAR_MIN)
    # Narrow ramps keep the layer edges crisp, so little of the layer behind shows through a half-transparent rim.
    near = ramp(v, t2, .025); front = ramp(v, t1, .025)      # front = everything nearer than the far layer
    wm = water_mask(img, H, W, cfg) if cfg.get('water') else None
    if wm is not None:                       # the water plane lives on the far layer, where it is animated
        front *= 1 - wm; near *= 1 - wm
    mid = front * (1 - near)                 # reported coverage only; the mid layer itself is opaque behind the near layer
    # Each back layer gets plausible scenery painted in wherever a nearer layer covers it, so when the nearer layer slides
    # aside it reveals that fill instead of a second copy of the object (ghosting). Far: behind mid and near. Mid: behind near.
    far_hole = cv2.dilate(((front > .5) * 255).astype('uint8'), np.ones((9, 9), np.uint8))
    if wm is not None: far_hole[wm > .5] = 0
    far = inpaint(img, far_hole)
    far = np.array(Image.fromarray(far.astype('uint8')).filter(ImageFilter.GaussianBlur(1.6))).astype('float32')
    far = far * .88 + (far.mean(axis=(0, 1)) * .5 + 235 * .5) * .12
    mid_rgb = inpaint(img, cv2.dilate(((near > .5) * 255).astype('uint8'), np.ones((9, 9), np.uint8)))
    out = f'layers/{n}'; os.makedirs(out, exist_ok=True)
    for f in ('near.webp', 'water.png'):
        if os.path.exists(f'{out}/{f}'): os.remove(f'{out}/{f}')
    Image.fromarray(soften(far.clip(0, 255), .72, 1.4, .08)).save(f'{out}/far.jpg', quality=82)
    for name, rgb, a, c, b in (('mid', mid_rgb, front, .80, .9), ('near', img, near, .86, .6)):
        if (a > .5).mean() < .01: continue   # nothing in this band
        rgba = np.dstack([soften(rgb, c, b, .03), (a * 255).astype('uint8')])
        Image.fromarray(rgba, 'RGBA').save(f'{out}/{name}.webp', quality=84, method=6)
    if wm is not None:                       # alpha mask of the water, for the ripple canvas
        Image.fromarray(np.dstack([np.full((H, W), 255, 'uint8'), (wm * 255).astype('uint8')]), 'LA').save(f'{out}/water.png', optimize=True)
    print(f'ch{n}: mid {100 * (mid > .5).mean():.0f}%  near {100 * (near > .5).mean():.0f}%' + ('  water' if wm is not None else ''))

if __name__ == '__main__':
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    for n in [int(a) for a in sys.argv[1:]] or sorted(CHAPTERS):
        split(n)
