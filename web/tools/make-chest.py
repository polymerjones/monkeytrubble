#!/usr/bin/env python3
# Reward chest flipbook from Paul's After Effects render (source/art/chest/chestanimatev1.mov: ProRes 4444 with alpha, 32 frames at
# 12 fps, the chest locked in place). Frames are cropped to the union of their opaque areas, scaled to WIDTH and written as WebP with
# alpha to web/art/chest/cNN.webp, with chest.json ({frames, fps, w, h}) for the game.
#   usage: python3 web/tools/make-chest.py [source.mov]
import json, pathlib, subprocess, sys, tempfile
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / 'source/art/chest/chestanimatev1.mov'
OUT = ROOT / 'art' / 'chest'
WIDTH, PAD, FPS = 560, 8, 12

with tempfile.TemporaryDirectory() as tmp:
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(SRC), '-pix_fmt', 'rgba', f'{tmp}/f%02d.png'], check=True)
    frames = [Image.open(p).convert('RGBA') for p in sorted(pathlib.Path(tmp).glob('f*.png'))]
    boxes = [f.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox() for f in frames]
    W, H = frames[0].size
    L, T = max(0, min(b[0] for b in boxes if b) - PAD), max(0, min(b[1] for b in boxes if b) - PAD)
    R, B = min(W, max(b[2] for b in boxes if b) + PAD), min(H, max(b[3] for b in boxes if b) + PAD)
    size = (WIDTH, round((B - T) * WIDTH / (R - L)))
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob('c*.webp'):
        old.unlink()
    for i, f in enumerate(frames):
        f.crop((L, T, R, B)).resize(size, Image.LANCZOS).save(OUT / f'c{i:02d}.webp', 'WEBP', quality=80, method=6)

(OUT / 'chest.json').write_text(json.dumps({'frames': len(frames), 'fps': FPS, 'w': size[0], 'h': size[1]}))
total = sum(p.stat().st_size for p in OUT.glob('c*.webp'))
print(f'{len(frames)} frames at {size[0]}x{size[1]}, {total / 1e6:.2f} MB -> {OUT}')
