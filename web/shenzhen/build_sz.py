#!/usr/bin/env python3
"""Build Shenzhen stations.json + routes.json for the Subway tools app.

Sources (both already verified by hand):
  - network.json            : canonical line order / colours / station lists (Phase 1 research)
  - rmp-gallery-shenzhen.json : RMP Gallery project JSON for Shenzhen
    (https://raw.githubusercontent.com/railmapgen/rmp-gallery/main/public/resources/real_world/shenzhen.json,
     gallery metadata public/resources/metadata/shenzhen.json, last update 2026-06-28)
    Station x,y are the RMP node coordinates verbatim -- the same convention as the
    other 8 cities (proven for Shanghai: stations.json x,y == RMP JSON node x,y exactly).

Matching rules (all verified, see asserts / diagnostics below):
  - RMP names are stripped of surrounding whitespace incl. U+3000 ideographic space.
  - '机场(T3)' is Line 11's 机场 station (RMP disambiguates it from 机场东).
  - Three interchange stations have EMPTY names in the RMP nodes and are identified
    by their line set + neighbours: 大运 {3,14,16}, 布吉 {3,5,14}, 深圳北站 {4,5,6}.
  - Three out-of-station transfer pairs have TWO dots in the RMP artwork and one
    stations.json entry at their midpoint: 湖贝 (2/5), 红岭南 (9/11), 福田口岸 (4/10).
    (福田口岸's Line 4 dot is the unnamed node at (-425,330); its Line 10 dot is
    the named node at (-405,330).)
  - Lines 2 and 8 through-run: RMP colours ALL 2/8 edges 'sz2' (no 'sz8' exists),
    so the 2/8 adjacency check walks the combined 赤湾..莲塘..溪涌 chain.
  - Duplicated names that are NOT the metro station (tram inset, 云巴, HK East Rail,
    not-in-service bar, legend) are excluded by line-set: e.g. the second 清湖 /
    罗湖 / 坪山中心 dots carry no 'sz*' line (or the wrong one).

Outputs (same shape as the other cities):
  - stations.json : [{"n","py","ini","x","y"}] sorted by py, one entry per unique station
  - routes.json   : {"lines": {key: {"color","name","stations"}}, "edges": [[A,B,key],...]}
    edges in line order (same as Shanghai's routes.json).

Run: python3 build_sz.py   (needs pypinyin)
"""
import json, math, pathlib, re, sys
from collections import defaultdict, deque
from pypinyin import lazy_pinyin

BASE = pathlib.Path(__file__).resolve().parent
NET = json.load(open(BASE / 'network.json', encoding='utf-8'))
RMP = json.load(open(BASE / 'rmp-gallery-shenzhen.json', encoding='utf-8'))

# Per-character pinyin corrections. pypinyin's phrase dictionary gets these
# Shenzhen place-name readings wrong; the corrections are verified against
# the stations' official English names (en-Wikipedia station pages and the
# RMP Gallery's own English labels, which agree):
#   长 -> chang in 长湖/长圳/长岭陂 (not zhang)
#   陂 -> pi in 长岭陂 (official: Changlingpi, pinyin Changlingpi)
#   壆 -> bo in 沙壆 (official: Shabo, pinyin Shabo)
#   乐 -> le in 民乐 (official: Minle)
#   厦 -> xia in 岗厦/岗厦北/石厦/松元厦/湾厦 (official: Gangxia/Shixia/...)
#   涌 -> chong in 溪涌/步涌 (official: Xichong/Buchong, Cantonese place-name reading)
#   茜 -> xi in 茜坑 (official: Xikeng)
# ini is the first letter of each corrected syllable, so compute py+ini together.
CHAR_FIX = {
    '长湖': {0: 'chang'}, '长圳': {0: 'chang'},
    '长岭陂': {0: 'chang', 2: 'pi'},
    '沙壆': {1: 'bo'},
    '民乐': {1: 'le'},
    '岗厦': {1: 'xia'}, '岗厦北': {1: 'xia'},
    '石厦': {1: 'xia'}, '松元厦': {2: 'xia'}, '湾厦': {1: 'xia'},
    '溪涌': {1: 'chong'}, '步涌': {1: 'chong'},
    '茜坑': {0: 'xi'},
}

def py_ini(name):
    parts = lazy_pinyin(name)
    for idx, syl in CHAR_FIX.get(name, {}).items():
        parts[idx] = syl
    return ''.join(parts), ''.join(p[0] for p in parts)

# ---------------------------------------------------------------- RMP graph
nodes = {n['key']: n for n in RMP['graph']['nodes']}
edges = RMP['graph']['edges']

def stn_attrs(n):
    a = n.get('attributes', {})
    t = a.get('type', '')
    if t in ('suzhourt-basic', 'suzhourt-int'):
        return a, t
    return None, None

def clean_name(s):
    # strip ASCII + full-width + ideographic spaces
    return re.sub(r'^[\s\u3000\xa0]+|[\s\u3000\xa0]+$', '', s or '')

# line id from an edge's single-color colour tuple ["shenzhen","sz1","#00B140","#fff"]
def edge_line(e):
    sc = e['attributes'].get('single-color', {}).get('color')
    if not sc:
        return None
    lid = sc[1]
    if lid == 'sz6b':
        return '6B'
    if re.fullmatch(r'sz\d+', lid):
        return lid[2:]
    return None  # 'other' etc.

# node key -> set of line keys serving it (metro lines only)
node_lines = defaultdict(set)
adj = defaultdict(list)  # key -> [(neighbour key, line or None)]
for e in edges:
    lid = edge_line(e)
    s, t = e['source'], e['target']
    adj[s].append((t, lid))
    adj[t].append((s, lid))
    if lid:
        node_lines[s].add(lid)
        node_lines[t].add(lid)

# station nodes: key -> (name, x, y, type)
stn_nodes = {}
for k, n in nodes.items():
    a, t = stn_attrs(n)
    if a is None:
        continue
    nm = clean_name(a.get(t, {}).get('names', ['', ''])[0])
    stn_nodes[k] = (nm, float(a.get('x')), float(a.get('y')), t)

by_name = defaultdict(list)
for k, (nm, x, y, t) in stn_nodes.items():
    by_name[nm].append(k)

# network station -> set of lines
net_lines = defaultdict(set)
line_order = []  # (key, name, color, stations)
for ln in NET['lines']:
    line_order.append((ln['key'], ln['name'], ln['color'], ln['stations']))
    for s in ln['stations']:
        net_lines[s].add(ln['key'])
want = sorted(net_lines)
print('network unique stations:', len(want), '| line entries:', sum(len(s) for _, _, _, s in line_order))

# ------------------------------------------------------- identify unnamed nodes
unnamed = [k for k, (nm, *_r) in stn_nodes.items() if not nm]
print('unnamed station nodes:', len(unnamed))
UNNAMED_IDS = {}  # line-set frozenset -> station name
for k in unnamed:
    ls = frozenset(node_lines.get(k, ()))
    print('  unnamed', (stn_nodes[k][1], stn_nodes[k][2]), 'lines:', sorted(ls),
          'nbrs:', [(stn_nodes[nk][0] or '?', l) for nk, l in adj[k] if nk in stn_nodes][:8])
    UNNAMED_IDS.setdefault(ls, []).append(k)
# the three real unnamed interchanges, each unique by line set
EXPECT_UNNAMED = {
    frozenset({'3', '14', '16'}): '大运',
    frozenset({'3', '5', '14'}): '布吉',
    frozenset({'4', '5', '6'}): '深圳北站',
}
for ls, name in EXPECT_UNNAMED.items():
    assert len(UNNAMED_IDS.get(ls, [])) == 1, (name, UNNAMED_IDS.get(ls))
    UNNAMED_IDS[ls] = UNNAMED_IDS[ls][0]
# every other unnamed node must be a legend sample (y >= 680) or the 福田口岸 L4 dot
for k in unnamed:
    ls = frozenset(node_lines.get(k, ()))
    x, y = stn_nodes[k][1], stn_nodes[k][2]
    if ls in EXPECT_UNNAMED:
        continue
    if (x, y) == (-425.0, 330.0) and ls == frozenset({'4'}):
        continue  # 福田口岸 Line 4 dot (pair member, handled below)
    assert y >= 680, ('unexpected unnamed node', k, (x, y), sorted(ls))
print('unnamed nodes classified OK')

# ------------------------------------------------------------- pair stations
# out-of-station pairs: two dots, one stations.json entry at the midpoint
PAIRS = {
    '湖贝': {'lines': ({'2'}, {'5'})},
    '红岭南': {'lines': ({'9'}, {'11'})},
    '福田口岸': {'lines': ({'4'}, {'10'})},
}

def node_xy(k):
    _, x, y, _t = stn_nodes[k]
    return x, y

matched = {}   # station name -> (x, y)
used = {}      # node key -> station name
problems = []

def claim(name, key, why):
    if key in used:
        problems.append(f'{name}: node {key} already used by {used[key]} ({why})')
        return
    used[key] = name
    matched[name] = node_xy(key)

for name in want:
    nlines = net_lines[name]
    if name in PAIRS:
        # find the two dots: one per line in the pair
        dots = {}
        for k, (nm, x, y, t) in stn_nodes.items():
            ls = node_lines.get(k, set())
            if nm == name or (not nm and name == '福田口岸' and (x, y) == (-425.0, 330.0)):
                for want_ls in PAIRS[name]['lines']:
                    if ls == want_ls:
                        dots[frozenset(want_ls)] = k
        if len(dots) != 2:
            problems.append(f'{name}: pair dots found {len(dots)} (want 2): {dots}')
            continue
        for k in dots.values():
            used[k] = name
        (x1, y1), (x2, y2) = (node_xy(k) for k in dots.values())
        matched[name] = ((x1 + x2) / 2.0, (y1 + y2) / 2.0)
        print(f'PAIR {name}: dots {sorted(dots.values())} -> midpoint {matched[name]}')
        continue
    if name in ('大运', '布吉', '深圳北站'):
        ls = frozenset(nlines)
        k = UNNAMED_IDS[ls]
        claim(name, k, 'unnamed interchange')
        continue
    cands = by_name.get(name, [])
    if name == '机场':
        cands = by_name.get('机场(T3)', [])
    if not cands:
        problems.append(f'{name}: NO RMP node')
        continue
    if len(cands) == 1:
        claim(name, cands[0], 'unique')
        continue
    # disambiguate duplicates by line set (metro lines only)
    scored = []
    for k in cands:
        ls = node_lines.get(k, set())
        overlap = ls & nlines
        scored.append((len(overlap), len(ls), k))
    scored.sort(reverse=True)
    best = scored[0]
    # the metro dot must serve at least one of the station's lines; others serve none
    if best[0] == 0:
        problems.append('%s: %d dups, none on its lines %s: %s' % (
            name, len(cands), sorted(nlines),
            [(k, sorted(node_lines.get(k, ()))) for k in cands]))
        continue
    if len(scored) > 1 and scored[1][0] == best[0] and scored[1][1] == best[1]:
        problems.append(f'{name}: ambiguous dups {scored}')
        continue
    claim(name, best[2], f'dup disambiguated by lines {sorted(node_lines.get(best[2], ()))} vs {sorted(nlines)}')

print('matched:', len(matched), '/', len(want))
if problems:
    print('PROBLEMS:')
    for p in problems:
        print('  -', p)

# ------------------------------------------------- verify per-line adjacency
# For each consecutive pair on a line, the two stations must be connected in the
# RMP graph by a path using only edges of that line's colour, passing through
# virtual nodes only (no other station in between). Lines 2/8 share colour sz2.
def line_color_id(key):
    return 'sz6b' if key == '6B' else 'sz' + key

def connected_via(a_key, b_key, line_key):
    # BFS from a_key over edges of this metro line (adj stores mapped line keys),
    # through virtual nodes AND through unmatched station nodes (e.g. unopened
    # 西丽高铁站 drawn between 高新北 and 石鼓 on Line 13). Matched stations
    # other than the target are blockers: passing one would mean a skipped stop.
    seen = {a_key}
    dq = deque([a_key])
    while dq:
        cur = dq.popleft()
        for nb, elid in adj[cur]:
            if elid != line_key or nb in seen:
                continue
            if nb == b_key:
                return True
            if nb not in used:  # virtual node or unmatched (unopened) station
                seen.add(nb)
                dq.append(nb)
    return False

# station name -> node key, per line: pair stations have one dot per line,
# normal stations have one node (fall back to it when the line is not in the
# node's edge colours, e.g. 莲塘 on Line 8 whose RMP edges are all sz2).
name_to_keys = defaultdict(list)
for k, nm_ in used.items():
    name_to_keys[nm_].append(k)
name_line_key = {}
for nm_ in want:
    keys = name_to_keys[nm_]
    for ln in net_lines[nm_]:
        dots = [k for k in keys if ln in node_lines.get(k, set())]
        name_line_key[(nm_, ln)] = dots[0] if dots else keys[0]
name_to_key = {nm_: keys[0] for nm_, keys in name_to_keys.items()}
adj_fail = []
for key, _nm, _col, sts in line_order:
    # adj stores mapped line keys; lines 2/8 share RMP colour sz2 -> key '2'
    lid = '2' if key in ('2', '8') else key
    for a, b in zip(sts, sts[1:]):
        ka, kb = name_line_key.get((a, key)), name_line_key.get((b, key))
        if ka is None or kb is None:
            adj_fail.append((key, a, b, 'unmatched endpoint'))
        elif not connected_via(ka, kb, lid):
            adj_fail.append((key, a, b, 'no %s-line path in RMP' % lid))
print('adjacency pairs checked:', sum(len(s) - 1 for _, _, _, s in line_order),
      '| failures:', len(adj_fail))
for f in adj_fail[:20]:
    print('  ADJ-FAIL', f)

# ------------------------------------------------- leftover RMP station nodes
leftover = []
for k, (nm, x, y, t) in stn_nodes.items():
    if k in used:
        continue
    ls = sorted(node_lines.get(k, ()))
    leftover.append((nm or '(unnamed)', (x, y), ls))
print('unmatched RMP station nodes:', len(leftover))
for nm, xy, ls in sorted(leftover, key=lambda r: (r[2], r[0])):
    print('  leftover:', repr(nm), xy, 'lines:', ls)

# ------------------------------------------------------------- write outputs
assert len(matched) == 351, f'unique count {len(matched)} != 351'
assert not problems and not adj_fail, 'matching/adjacency problems remain'

stations = []
for name in want:
    x, y = matched[name]
    py, ini = py_ini(name)
    stations.append({'n': name, 'py': py, 'ini': ini,
                     'x': float(x), 'y': float(y)})
stations.sort(key=lambda s: s['py'])
json.dump(stations, open(BASE / 'stations.json', 'w', encoding='utf-8'),
          ensure_ascii=False, indent=1)
print('stations.json written:', len(stations))

lines_out = {}
edges_out = []
for key, nm, col, sts in line_order:
    lines_out[key] = {'color': col, 'name': nm, 'stations': list(sts)}
    edges_out += [[a, b, key] for a, b in zip(sts, sts[1:])]
routes = {'lines': lines_out, 'edges': edges_out}
json.dump(routes, open(BASE / 'routes.json', 'w', encoding='utf-8'),
          ensure_ascii=False, indent=1)
print('routes.json written: lines', len(lines_out), 'edges', len(edges_out))

# final self-checks on the written files
st = json.load(open(BASE / 'stations.json', encoding='utf-8'))
rt = json.load(open(BASE / 'routes.json', encoding='utf-8'))
sns = {s['n'] for s in st}
assert len(st) == 351 and len(sns) == 351
assert all(isinstance(s['x'], float) and isinstance(s['y'], float) for s in st)
assert sum(len(v['stations']) for v in rt['lines'].values()) == 433
assert all(a in sns and b in sns for a, b, _k in rt['edges'])
assert len(rt['edges']) == 433 - 17
# NB: 东角头 / 机场东 / 白石洲 / 黄阁坑 also name unopened future stations, but
# they already operate on Lines 2 / 1 / 1 / 16, so they must NOT be excluded by name.
UNOPENED = ['歌剧院', '潮汐公园', '西丽高铁站', '文体公园', '福邻',
            '黄江南', '宝安公园', '前海石', '龙平路',
            '交椅湾', '海洋新城', '比亚迪北', '坪山高铁站']
assert not any(u in sns for u in UNOPENED), 'unopened station leaked in'
assert '坪山云巴1号线' not in json.dumps(rt, ensure_ascii=False)
print('ALL CHECKS PASS: 351 unique, 433 line entries,',
      len(rt['edges']), 'edges, no unopened stations')
