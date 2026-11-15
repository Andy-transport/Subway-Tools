# Generate web/stations.json: the searchable station index for the app.
# Parses the production map SVG (MTR2.8.0.svg), takes the station label
# <text> elements (font-size 3.52778/3.52777), drops non-station labels,
# snaps each station to its nearest track marker rect (the 9x2/1.5/1.0
# rects are station ticks) for an accurate tap-to-locate point, dedupes
# by name (keeping the occurrence nearest a marker), and adds pinyin +
# initials via pypinyin for search.
#
# Run on the dev machine (needs pypinyin: pip install pypinyin), NOT on
# the Actions runner: build_offline.py inlines the committed stations.json.
# Regenerate when the map version changes (new SVG).
import json, math, pathlib, re
import xml.etree.ElementTree as ET
from pypinyin import lazy_pinyin

BASE = pathlib.Path(__file__).resolve().parent
SVG = BASE / "vendor" / "MTR2.8.0.svg"
if not SVG.exists():
    SVG = pathlib.Path('/home/hatch/workspace/metro-app/vendor/MTR2.8.0.svg')
NS = '{http://www.w3.org/2000/svg}'
# Labels that look like stations but are not (legend / area / place names).
DENY = {'图例', '图例东', '图例桥西', '上地软件园', '万安', '上岸', '九号村', '东北旺'}

def parse_transform(s):
    m = (1, 0, 0, 1, 0, 0)
    if not s:
        return m
    for name, args in re.findall(r'(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)', s):
        v = [float(x) for x in re.split(r'[,\s]+', args.strip()) if x]
        if name == 'matrix' and len(v) == 6:
            t = tuple(v)
        elif name == 'translate':
            t = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0)
        elif name == 'scale':
            t = (v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif name == 'rotate':
            a = math.radians(v[0]); ca, sa = math.cos(a), math.sin(a)
            t = (ca, sa, -sa, ca, 0, 0) if len(v) == 1 else \
                (ca, sa, -sa, ca, v[1] - ca * v[1] + sa * v[2], v[2] - sa * v[1] - ca * v[2])
        elif name == 'skewX':
            t = (1, 0, math.tan(math.radians(v[0])), 1, 0, 0)
        elif name == 'skewY':
            t = (1, math.tan(math.radians(v[0])), 0, 1, 0, 0)
        else:
            continue
        a, b, c, d, e, f = m; a2, b2, c2, d2, e2, f2 = t
        m = (a * a2 + b * c2, a * b2 + b * d2, c * a2 + d * c2,
             c * b2 + d * d2, e * a2 + f * c2 + e2, e * b2 + f * d2 + f2)
    return m

def apply(m, x, y):
    a, b, c, d, e, f = m
    return (a * x + c * y + e, b * x + d * y + f)

tree = ET.parse(SVG)
root = tree.getroot()
texts, rects = [], []

def walk(el, m):
    m2 = parse_transform(el.get('transform', ''))
    a, b, c, d, e, f = m; a2, b2, c2, d2, e2, f2 = m2
    mm = (a * a2 + b * c2, a * b2 + b * d2, c * a2 + d * c2,
          c * b2 + d * d2, e * a2 + f * c2 + e2, e * b2 + f * d2 + f2)
    if el.tag == NS + 'text':
        txt = ''.join(el.itertext()).strip()
        style = el.get('style', '')
        fs = re.search(r'font-size:\s*([\d.]+)', style)
        ex, ey = apply(mm, float(el.get('x', '0')), float(el.get('y', '0')))
        texts.append({'x': ex, 'y': ey, 'fs': fs.group(1) if fs else '?', 'txt': txt})
    elif el.tag == NS + 'rect':
        try:
            w, h = float(el.get('width', 0)), float(el.get('height', 0))
        except ValueError:
            w = h = 0
        if (round(w, 1), round(h, 1)) in ((9.0, 2.0), (9.0, 1.5), (9.0, 1.0)):
            ex, ey = apply(mm, float(el.get('x', '0')), float(el.get('y', '0')))
            rects.append((ex + w / 2, ey + h / 2))
    for ch in el:
        walk(ch, mm)

walk(root, (1, 0, 0, 1, 0, 0))

def is_cjk(s):
    return re.fullmatch(r'[\u4e00-\u9fff·、]+', s) is not None

sta = [t for t in texts if t['fs'] in ('3.52778', '3.52777')
       and is_cjk(t['txt']) and t['txt'] not in DENY]

def nearest_marker(x, y):
    best, bd = None, 1e9
    for rx, ry in rects:
        d = math.hypot(x - rx, y - ry)
        if d < bd:
            bd, best = d, (rx, ry)
    return best, bd

best = {}
for t in sta:
    (mx, my), d = nearest_marker(t['x'], t['y'])
    if d > 150:
        print('WARN far from marker:', t['txt'], round(d))
        continue
    if t['txt'] not in best or d < best[t['txt']][2]:
        best[t['txt']] = (mx, my, d)

out = []
for name, (mx, my, _d) in best.items():
    py = ''.join(lazy_pinyin(name))
    ini = ''.join(p[0] for p in lazy_pinyin(name))
    out.append({'n': name, 'py': py, 'ini': ini, 'x': round(mx), 'y': round(my)})
out.sort(key=lambda s: s['py'])

json.dump(out, open(BASE / 'stations.json', 'w', encoding='utf-8'), ensure_ascii=False)
print('stations.json written:', len(out), 'entries')
