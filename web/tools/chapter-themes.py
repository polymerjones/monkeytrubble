#!/usr/bin/env python3
"""Per-chapter UI themes, generated from the Jungle theme.

The Jungle theme's colours are CSS variables (--jc-0, --jc-1, ...) defined in the "jungle-colors" block of index.html.
Each chapter in CHAPTER_UI (and the Christmas season) gets a block html[data-theme="jungle"][data-ui="<key>"]{...} that redefines those variables:
every Jungle colour is sorted into a family by its hue and lightness (panel greens, wood browns, gold accents; cream text,
reds, blues and greys stay as they are) and moved to the chapter's hue for that family, keeping its lightness so contrast
holds. index.html picks the block from CHAPTERS[].ui.

The first run also converts the Jungle rules' colour literals into the variables. Run from web/: python3 tools/chapter-themes.py
"""
import colorsys
import re
from pathlib import Path

HTML = Path(__file__).resolve().parent.parent / 'index.html'
JUNGLE_RULE = re.compile(r'html\[data-theme="jungle"\][^{]*\{[^}]*\}')
COLOR = re.compile(r'#[0-9a-fA-F]{8}\b|#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{4}\b|#[0-9a-fA-F]{3}\b')
DEFAULTS_START, DEFAULTS_END = '/* jungle-colors:start (tools/chapter-themes.py) */', '/* jungle-colors:end */'
THEMES_START, THEMES_END = '/* chapter-themes:start (tools/chapter-themes.py) */', '/* chapter-themes:end */'

# Per family: (hue in degrees, saturation multiplier, lightness multiplier). A family left out keeps the Jungle colour.
CHAPTER_UI = {
    'swamp':   {'panel': (168, .75, .95), 'wood': (62, .55, .9),  'accent': (78, .8, 1)},
    'cloud':   {'panel': (150, .35, 1.08), 'wood': (205, .22, 1.12), 'accent': (188, .55, 1.05)},
    'savannah': {'panel': (24, .6, .95), 'wood': (16, 1.05, 1),  'accent': (40, 1, 1)},
    'deep':    {'panel': (142, 1.15, .8), 'wood': (24, .75, .85), 'accent': (62, .85, 1)},
    'frozen':  {'panel': (206, .7, 1),   'wood': (212, .3, 1.15), 'accent': (194, .85, 1.05)},
    'island':  {'panel': (182, .9, 1),   'wood': (36, .55, 1.15), 'accent': (46, 1, 1)},
    'temple':  {'panel': (42, .22, 1.05), 'wood': (30, .35, 1.05), 'accent': (45, 1.1, 1)},
    'canopy':  {'panel': (156, 1.05, .95), 'wood': (32, .95, 1),  'accent': (48, 1.15, 1)},
    # Ice Age (chapter 11): glacier-blue panels, pale steel frames, a silver-white accent instead of gold.
    'iceage':  {'panel': (200, .55, .95), 'wood': (215, .12, 1.2), 'accent': (205, .18, 1.12)},
    # Not a chapter: Christmas levels (CHRISTMAS in index.html). Pine-green panels, candy-red frames, gold.
    'christmas': {'panel': (146, 1.0, .9), 'wood': (356, 1.25, 1), 'accent': (46, 1.15, 1)},
}


def parse(c):
    h = c[1:]
    if len(h) in (3, 4):
        h = ''.join(ch * 2 for ch in h)
    rgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    alpha = h[6:8] if len(h) == 8 else ''
    return rgb, alpha


def family(rgb):
    hue, light, sat = colorsys.rgb_to_hls(*rgb)
    hue *= 360
    if sat < .15 or light > .86 or light < .02:
        return None
    if 80 <= hue <= 170:
        return 'panel'
    if 15 <= hue <= 50 and light < .55:
        return 'wood'
    if 35 <= hue <= 60 and light >= .55 and sat > .4:
        return 'accent'
    return None


def recolor(c, spec):
    rgb, alpha = parse(c)
    fam = family(rgb)
    if not fam or fam not in spec:
        return c
    hue, sat_k, light_k = spec[fam]
    _, light, sat = colorsys.rgb_to_hls(*rgb)
    r, g, b = colorsys.hls_to_rgb(hue / 360, min(1, light * light_k), min(1, sat * sat_k))
    return '#' + ''.join(f'{round(v * 255):02x}' for v in (r, g, b)) + alpha


def main():
    s = HTML.read_text()
    if DEFAULTS_START not in s:
        # First run: every colour literal in the Jungle rules becomes a variable.
        colors = []
        def var(m):
            c = m.group(0).lower()
            if c not in colors:
                colors.append(c)
            return f'var(--jc-{colors.index(c)})'
        first = JUNGLE_RULE.search(s).start()
        s = JUNGLE_RULE.sub(lambda m: COLOR.sub(var, m.group(0)), s)
        block = DEFAULTS_START + 'html[data-theme="jungle"]{' + ';'.join(f'--jc-{i}:{c}' for i, c in enumerate(colors)) + '}' + DEFAULTS_END + '\n    '
        s = s[:first] + block + s[first:]
    defaults = s[s.index(DEFAULTS_START):s.index(DEFAULTS_END)]
    colors = dict(re.findall(r'(--jc-\d+):(#[0-9a-fA-F]+)', defaults))
    blocks = []
    for key, spec in CHAPTER_UI.items():
        changed = {k: recolor(c, spec) for k, c in colors.items()}
        body = ';'.join(f'{k}:{v}' for k, v in changed.items() if v != colors[k])
        blocks.append(f'html[data-theme="jungle"][data-ui="{key}"]{{{body}}}')
    themes = THEMES_START + ''.join(blocks) + THEMES_END
    if THEMES_START in s:
        s = s[:s.index(THEMES_START)] + themes + s[s.index(THEMES_END) + len(THEMES_END):]
    else:
        end = s.index(DEFAULTS_END) + len(DEFAULTS_END)
        s = s[:end] + themes + s[end:]
    HTML.write_text(s)
    print(f'{len(colors)} jungle colours, {len(blocks)} chapter themes')


if __name__ == '__main__':
    main()
