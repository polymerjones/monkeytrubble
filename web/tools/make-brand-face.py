#!/usr/bin/env python3
"""Cut the app icon's monkey face out of its slate background -> web/art/brand-face.png (the puzzle picture watermark).
The bright green rim and the light hair line are a wall (thickened a little to close gaps); the background is flood-filled in from
the edges up to that wall. Everything inside stays solid; outside, the green glow is kept as soft green with alpha from how much
greener than the slate each pixel is, so it fades out over anything. Run from the repo root: python3 web/tools/make-brand-face.py"""
from collections import deque
from PIL import Image, ImageFilter
SRC='MonkeyTrubbleIOS/MonkeyTrubbleIOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
OUT='web/art/brand-face.png'
GLOW=(40,245,110)
im=Image.open(SRC).convert('RGB');W,H=im.size;px=im.load()
wall=Image.new('L',(W,H),0);wp=wall.load()
for y in range(H):
    for x in range(W):
        r,g,b=px[x,y]
        if g>150 or (r+g+b)/3>105:wp[x,y]=255
wall=wall.filter(ImageFilter.MaxFilter(7));wp=wall.load()
out=bytearray(W*H);q=deque((x,y) for x in range(W) for y in (0,H-1))
q.extend((x,y) for y in range(H) for x in (0,W-1))
while q:
    x,y=q.popleft();i=y*W+x
    if out[i] or wp[x,y]:continue
    out[i]=1
    for nx,ny in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
        if 0<=nx<W and 0<=ny<H and not out[ny*W+nx]:q.append((nx,ny))
# Only the face itself stays solid: the background's bright specks were walls too, so keep just the inside piece the centre is in.
inside=bytearray(W*H);q=deque([(W//2,H//2)])
while q:
    x,y=q.popleft();i=y*W+x
    if inside[i] or out[i]:continue
    inside[i]=1
    for nx,ny in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
        if 0<=nx<W and 0<=ny<H:q.append((nx,ny))
for i in range(W*H):out[i]=0 if inside[i] else 1
res=Image.new('RGBA',(W,H));rp=res.load()
for y in range(H):
    for x in range(W):
        r,g,b=px[x,y]
        if not out[y*W+x]:rp[x,y]=(r,g,b,255);continue
        e=g-(r+b)/2-8;a=max(0,min(255,int(e*4)))
        rp[x,y]=(*GLOW,a)
# Soften the seam between the solid face and the glow.
a=res.getchannel('A').filter(ImageFilter.GaussianBlur(.8));res.putalpha(a)
box=a.point(lambda v:255 if v>10 else 0).getbbox();res=res.crop(box)
s=512/max(res.size);res=res.resize((round(res.width*s),round(res.height*s)),Image.LANCZOS)
res.save(OUT,optimize=True);print(OUT,res.size)
