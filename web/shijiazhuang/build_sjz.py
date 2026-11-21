#!/usr/bin/env python3
"""Build Shijiazhuang stations.json + routes.json + routes_geo.json for the
Subway tools app.

Sources:
  - rmp-gallery-shijiazhuang.json : RMP Gallery project JSON for
    Shijiazhuang (https://raw.githubusercontent.com/railmapgen/rmp-gallery/
    main/public/resources/real_world/shijiazhuang.json, gallery metadata
    public/resources/metadata/shijiazhuang.json, RMP version 56).
    Station x,y are the RMP node coordinates verbatim -- same convention
    as Shenzhen/Chengdu/Qingdao.
  - Official operating station lists (zh-Wikipedia station template
    Template:石家莊地鐵車站, crawled 2026-11-21; cross-checked against
    Amap's live Shijiazhuang network data and the zh/en Wikipedia line
    tables: 3 lines, 63 line-stations, 60 unique, 3 interchanges,
    76.5 km).

Operating network encoded here (63 line-stations, 60 unique):
  1: 26, 2: 15, 3: 22.
  63 - 3 interchange extras (新百广场 1/3, 北国商城 1/2, 石家庄站 2/3,
  each counted twice) = 60 unique. Matches the official figures.

Special cases (all verified, see NOTES.md):
  - The RMP graph also draws the UNOPENED Line 1 extensions: phase-2
    north section 福泽-东上泽-东洋 (opens ~end of 2026) and phase-3
    槐安路-上庄-西王 (under construction). 东上泽, 东洋, 槐安路, 上庄
    are station nodes touched by sjz1 edges but are NOT operating and
    are excluded; they also act as blockers so the station-level walk
    never routes through them.
  - Line 1's direct station-to-station edges are interrupted between
    朝晖桥 and 留村 (the drawn path passes through non-station
    waypoints), so neighbours are found by BFS through non-station
    nodes, exactly like the Qingdao build.
  - RMP draws Lines 4/5/6 (under construction) in grey ('other'); they
    are ignored entirely.
  - Line colours are the RMP palette tuples (city 'shijiazhuang'):
    sjz1 #E53E30, sjz2 #FEC30A, sjz3 #00A1E0. (A few sjz1 edges use a
    second red #FF0D33 for the unopened extension styling; the line
    colour is the main tuple colour #E53E30.)

Pinyin: pypinyin lazy_pinyin, no per-name fixes needed (checked:
洨 xiáo, 窠 kē, 冢 zhǒng, 乐乡 lè, 朝晖 zhāo all read correctly).

Outputs (same shapes as Qingdao / Beijing):
  - stations.json  : [{"n","py","ini","x","y"}] sorted by py
  - routes.json    : {"lines": {key: {"color","name","stations"}},
                      "edges": [[A,B,key],...]} edges in line order
  - routes_geo.json: {"lines": {key: {"color","chains": [[...]]}},
                      "edges": [[A,B,key],...]} (Beijing shape)

Run: python3 build_sjz.py   (needs pypinyin)
"""
import json, pathlib, re
from collections import defaultdict, deque
from pypinyin import lazy_pinyin

BASE = pathlib.Path(__file__).resolve().parent
RMP = json.load(open(BASE / 'rmp-gallery-shijiazhuang.json', encoding='utf-8'))

def py_ini(name):
    parts = lazy_pinyin(name)
    return ''.join(parts), ''.join(p[0] for p in parts if p)

# ------------------------------------------------------------- official data
# (line key, display name, colour hex no '#', stations in official order)
LINES = [
    ('1', '1号线', 'E53E30', [
        '西王', '时光街', '长城桥', '和平医院', '烈士陵园', '新百广场',
        '解放广场', '平安大街', '北国商城', '博物院', '体育场', '北宋',
        '谈固', '朝晖桥', '白佛', '留村', '火炬广场', '石家庄东站',
        '南村', '洨河大道', '西庄', '东庄', '会展中心', '商务中心',
        '园博园', '福泽']),
    ('2', '2号线', 'FEC30A', [
        '柳辛庄', '庄窠·铁道大学', '义堂', '建和桥', '长安公园',
        '北国商城', '裕华路', '槐中路', '欧韵公园', '元村', '石家庄站',
        '塔坛', '仓丰路留村', '南位', '嘉华路']),
    ('3', '3号线', '00A1E0', [
        '西三庄', '高柱', '柏林庄', '市庄', '市二中', '新百广场',
        '东里', '槐安桥', '西三教', '石家庄站', '汇通路', '孙村',
        '塔冢', '东王', '南王', '位同', '东二环南路', '西仰陵',
        '中仰陵', '南豆', '太行南大街', '乐乡']),
]
# Drawn in RMP on sjz1 but NOT operating (Line 1 phase-2 north + phase 3).
UNOPENED_L1 = {'东上泽', '东洋', '槐安路', '上庄'}

def clean_name(s):
    s = re.sub(r'[\s\u3000\xa0]+', '', s or '')
    return s.replace('(', '（').replace(')', '）')

# ---------------------------------------------------------------- RMP graph
nodes = {n['key']: n for n in RMP['graph']['nodes']}
edges = RMP['graph']['edges']

def stn_name(n):
    a = n.get('attributes', {})
    if a.get('type') == 'mtr':
        return clean_name(a['mtr']['names'][0])
    return None

stn_nodes = {}   # node key -> name (ALL RMP station nodes, any line)
for k, n in nodes.items():
    nm = stn_name(n)
    if nm is not None:
        stn_nodes[k] = nm
name_to_key = {}
for k, nm in stn_nodes.items():
    assert nm not in name_to_key, f'duplicate station node name {nm}'
    name_to_key[nm] = k

def edge_line(e):
    col = e['attributes'].get('single-color', {}).get('color')
    if col and col[0] == 'shijiazhuang' and re.fullmatch(r'sjz\d+', col[1]):
        return col[1][-1]
    return None

# per-line adjacency over ALL nodes (tracks pass through virtual waypoints)
line_adj = defaultdict(lambda: defaultdict(set))
for e in edges:
    lid = edge_line(e)
    if lid:
        line_adj[lid][e['source']].add(e['target'])
        line_adj[lid][e['target']].add(e['source'])

def station_neighbours(lid, start_key, official_keys):
    """Official stations reachable from start_key along lid edges without
    passing through another station node (any station node blocks,
    including unopened ones, so the walk can never route via them)."""
    adj = line_adj[lid]
    seen = {start_key}
    out = set()
    dq = deque([start_key])
    while dq:
        cur = dq.popleft()
        for nb in adj[cur]:
            if nb in seen:
                continue
            seen.add(nb)
            if nb in stn_nodes:
                if nb in official_keys:
                    out.add(nb)
                # any station node blocks further traversal
            else:
                dq.append(nb)
    return out

def walk_line(lid, official):
    keys = [name_to_key[nm] for nm in official]
    official_keys = set(keys)
    graph = {k: station_neighbours(lid, k, official_keys) for k in keys}
    deg1 = [k for k, ns in graph.items() if len(ns) == 1]
    assert len(deg1) == 2, f'line {lid}: expected 2 termini, got {len(deg1)}'
    order, prev, cur = [], None, deg1[0]
    while True:
        order.append(stn_nodes[cur])
        nxt = [x for x in graph[cur] if x != prev]
        if not nxt:
            break
        assert len(nxt) == 1, f'line {lid}: branch at {stn_nodes[cur]}'
        prev, cur = cur, nxt[0]
    assert len(order) == len(keys), f'line {lid}: walked {len(order)} of {len(keys)}'
    if order == official:
        return order
    if order == official[::-1]:
        return official
    raise AssertionError(f'line {lid}: walked order != official order\nwalked: {order}\nofficial: {official}')

# ------------------------------------------------------------------- build
lines_out = {}
geo_lines_out = {}
edges_out = []
all_names = []
for key, disp, color, official in LINES:
    walked = walk_line(key, official)
    lines_out[key] = {'color': color, 'name': disp, 'stations': walked}
    geo_lines_out[key] = {'color': color, 'chains': [walked]}
    all_names += walked
    for a, b in zip(walked, walked[1:]):
        edges_out.append([a, b, key])
    print(f'line {key}: {len(walked)} stations OK')

uniq = sorted(set(all_names))
print(f'line-stations: {len(all_names)}, unique: {len(uniq)}, edges: {len(edges_out)}')
assert len(uniq) == 60, f'unique station count {len(uniq)} != 60'
assert len(all_names) == 63
assert len(edges_out) == 60  # 63 - 3 lines

# RMP stations touched by sjz1/2/3 edges that are NOT operating must be
# exactly the known unopened Line 1 extension stations.
touched = set()
for lid in ('1', '2', '3'):
    for src, nbs in line_adj[lid].items():
        if src in stn_nodes:
            touched.add(stn_nodes[src])
extra = touched - set(uniq)
print('RMP sjz-line stations excluded as unopened:', sorted(extra))
assert extra == UNOPENED_L1, f'unexpected extra RMP stations: {sorted(extra)}'

stations_out = []
for nm in uniq:
    k = name_to_key[nm]
    a = nodes[k]['attributes']
    py, ini = py_ini(nm)
    stations_out.append({'n': nm, 'py': py, 'ini': ini,
                         'x': float(a['x']), 'y': float(a['y'])})
stations_out.sort(key=lambda s: (s['py'], s['n']))

with open(BASE / 'stations.json', 'w', encoding='utf-8') as f:
    json.dump(stations_out, f, ensure_ascii=False, indent=1)
with open(BASE / 'routes.json', 'w', encoding='utf-8') as f:
    json.dump({'lines': lines_out, 'edges': edges_out}, f, ensure_ascii=False, indent=1)
with open(BASE / 'routes_geo.json', 'w', encoding='utf-8') as f:
    json.dump({'lines': geo_lines_out, 'edges': edges_out}, f, ensure_ascii=False, indent=1)
print('WROTE stations.json + routes.json + routes_geo.json -- ALL CHECKS PASS')
