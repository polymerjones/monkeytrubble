"""Splits each painted chapter background into far / mid / near parallax layers and softens them.

Run from this folder with a Python that has torch, transformers, opencv-python-headless and Pillow:
    python split-layers.py            # every chapter
    python split-layers.py 3 7        # just these chapters
Reads ch<n>_*.png here and writes layers/<n>/far.jpg, mid.webp, near.webp (and water.png for chapters with
animated water). web/tools/make-card-images.sh copies layers/<n>/ into web/art/chapters/<n>/.

How it works: Depth Anything V2 estimates each pixel's distance. The nearest ~18% of the picture becomes the
near layer, the next band the mid layer, and the far layer is the whole picture with the mid/near objects above
the ground line painted out where those layers fully cover it (OpenCV inpaint), so the parallax never reveals a hole. Below the ground line the
far layer keeps the real pixels: ground and water are flat planes, and a slightly shifted copy of them reads
fine. Then every layer gets lower contrast and a little blur, the far layer the most (atmospheric haze).
"""
import sys, re, glob, os
import numpy as np, cv2
from PIL import Image, ImageFilter

# ground: fraction of the height where the ground (or water) plane starts.
# water: 'rows' = everything below the ground line is water; 'color' = only the blue water pixels below it.
# mid_min: overrides MID_MIN for one chapter.
CHAPTERS = {
    1: dict(ground=.55), 2: dict(ground=.75), 3: dict(ground=.60, water='rows', mid_min=.16), 4: dict(ground=.80),
    5: dict(ground=.55), 6: dict(ground=.75), 7: dict(ground=.52, water='color'), 8: dict(ground=.68),
    9: dict(ground=.75), 10: dict(ground=.85),
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

def split(n):
    src = glob.glob(f'ch{n}_*.png')[0]; cfg = CHAPTERS[n]
    img = np.array(Image.open(src).convert('RGB')); H, W = img.shape[:2]
    v = cv2.GaussianBlur(depth(Image.fromarray(img)).astype('float32'), (0, 0), 3)
    # Percentile bands, with a floor so open scenes (distant mountains, sky) stay on the far layer.
    t1, t2 = max(np.percentile(v, MID_PCT), cfg.get('mid_min', MID_MIN)), max(np.percentile(v, NEAR_PCT), NEAR_MIN)
    near = ramp(v, t2); mid = ramp(v, t1) * (1 - near)
    wm = water_mask(img, H, W, cfg) if cfg.get('water') else None
    if wm is not None:                       # the water plane lives on the far layer, where it is animated
        mid *= 1 - wm; near *= 1 - wm
    # Far: paint out the mid/near objects above the ground line (half size gives smoother fills).
    g = int(H * cfg['ground'])
    # Only where the front layers are fully opaque: anywhere they are partly see-through, the fill would show as a smear.
    hole = (((mid + near) > .97) * 255).astype('uint8'); hole = cv2.erode(hole, np.ones((5, 5), np.uint8))
    hole = (hole * np.clip((g - np.arange(H)) / 40, 0, 1)[:, None]).astype('uint8')
    small = lambda a: cv2.resize(a, (W // 2, H // 2), interpolation=cv2.INTER_AREA)
    fill = cv2.inpaint(cv2.cvtColor(small(img), cv2.COLOR_RGB2BGR), (small(hole) > 127).astype('uint8') * 255, 15, cv2.INPAINT_TELEA)
    fill = cv2.cvtColor(cv2.resize(fill, (W, H), interpolation=cv2.INTER_CUBIC), cv2.COLOR_BGR2RGB)
    m = cv2.GaussianBlur(hole.astype('float32') / 255, (0, 0), 2)[..., None]
    far = img * (1 - m) + fill * m
    far = np.array(Image.fromarray(far.astype('uint8')).filter(ImageFilter.GaussianBlur(1.6))).astype('float32')
    far = far * .88 + (far.mean(axis=(0, 1)) * .5 + 235 * .5) * .12
    out = f'layers/{n}'; os.makedirs(out, exist_ok=True)
    for f in ('near.webp', 'water.png'):
        if os.path.exists(f'{out}/{f}'): os.remove(f'{out}/{f}')
    Image.fromarray(soften(far.clip(0, 255), .72, 1.4, .08)).save(f'{out}/far.jpg', quality=82)
    for name, a, c, b in (('mid', mid, .80, .9), ('near', near, .86, .6)):
        if (a > .5).mean() < .01: continue   # nothing in this band
        rgba = np.dstack([soften(img, c, b, .03), (a * 255).astype('uint8')])
        Image.fromarray(rgba, 'RGBA').save(f'{out}/{name}.webp', quality=84, method=6)
    if wm is not None:                       # alpha mask of the water, for the ripple canvas
        Image.fromarray(np.dstack([np.full((H, W), 255, 'uint8'), (wm * 255).astype('uint8')]), 'LA').save(f'{out}/water.png', optimize=True)
    print(f'ch{n}: mid {100 * (mid > .5).mean():.0f}%  near {100 * (near > .5).mean():.0f}%' + ('  water' if wm is not None else ''))

if __name__ == '__main__':
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    for n in [int(a) for a in sys.argv[1:]] or sorted(CHAPTERS):
        split(n)
