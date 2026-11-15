"""Derive the Beijing subway route graph from the MTR2.8.0 SVG track geometry (v2).

Steps:
 1. Walk the SVG with CTM; collect paths whose stroke/fill is a line color.
 2. For each station, min distance to each line's sampled track -> cleaned
    membership (<=7 units, else closest line if <=15).
 3. Geometric edges: consecutive stations along each path, restricted to
    cleaned membership; drop "skip" edges (a same-line station lies between).
 4. Graft: per line, while the graph is fragmented, connect the two closest
    components (nearest station pair, < 600 units).
 5. Per-line chains (walk from an endpoint; loops walk around) for display;
    edges (with line labels) are the routing graph.
 6. Validate: coverage, connectivity, Dijkstra spot-checks.
Run on the dev machine only (needs svgpathtools); the Actions runner inlines
the committed routes.json.
"""
import xml.etree.ElementTree as ET
import json, math, re, heapq
from collections import Counter, defaultdict
from svgpathtools import parse_path

SVG = 'web/vendor/MTR2.8.0.svg'
STATIONS = 'web/stations.json'
OUT = 'web/routes_geo.json'

def local(t): return t.split('}')[-1]

def getstyle(e, key):
    style = e.get('style') or ''
    for part in style.split(';'):
        part = part.strip()
        if part.startswith(key + ':'):
            return part.split(':', 1)[1].strip()
    return ''

def parse_transform(s):
    m = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
    if not s: return m
    def mul(m1, m2):
        a1,b1,c1,d1,e1,f1 = m1; a2,b2,c2,d2,e2,f2 = m2
        return (a1*a2+c1*b2, b1*a2+d1*b2, a1*c2+c1*d2, b1*c2+d1*d2,
                a1*e2+c1*f2+e1, b1*e2+d1*f2+f1)
    for kind, args in re.findall(r'(\w+)\s*\(([^)]*)\)', s):
        nums = [float(x) for x in re.findall(r'-?[\d.]+(?:e-?\d+)?', args)]
        if kind == 'translate':
            t = (1,0,0,1, nums[0], nums[1] if len(nums)>1 else 0.0)
        elif kind == 'scale':
            t = (nums[0],0,0, nums[1] if len(nums)>1 else nums[0], 0,0)
        elif kind == 'rotate':
            a = math.radians(nums[0]); ca, sa = math.cos(a), math.sin(a)
            if len(nums) >= 3:
                cx, cy = nums[1], nums[2]
                t = mul((1,0,0,1,cx,cy), mul((ca,sa,-sa,ca,0,0), (1,0,0,1,-cx,-cy)))
            else:
                t = (ca,sa,-sa,ca,0,0)
        elif kind == 'matrix' and len(nums) == 6:
            t = tuple(nums)
        else:
            continue
        m = mul(m, t)
    return m

def apply(m, x, y):
    a,b,c,d,e,f = m
    return (a*x + c*y + e, b*x + d*y + f)

def dist(a, b):
    return math.hypot(a[0]-b[0], a[1]-b[1])

def main():
    line_colors = {}
    for line in open('web/vendor/colors.txt'):
        line = line.strip()
        if not line or line.startswith('#') or '----' not in line: continue
        lid, hexv = [x.strip() for x in line.split('----')]
        line_colors[hexv.upper()] = lid
    decor = {'STD1','STD2','ABC','ADC'}
    stations = json.load(open(STATIONS))
    pos = {s['n']: (s['x'], s['y']) for s in stations}

    tree = ET.parse(SVG)
    root = tree.getroot()
    colored = []
    def walk(elem, ctm):
        t = elem.get('transform')
        if t:
            m2 = parse_transform(t)
            a1,b1,c1,d1,e1,f1 = ctm; a2,b2,c2,d2,e2,f2 = m2
            ctm = (a1*a2+c1*b2, b1*a2+d1*b2, a1*c2+c1*d2, b1*c2+d1*d2,
                   a1*e2+c1*f2+e1, b1*e2+d1*f2+f1)
        if local(elem.tag) == 'path':
            st = (elem.get('stroke') or getstyle(elem, 'stroke') or '').lstrip('#').upper()
            fl = (elem.get('fill') or getstyle(elem, 'fill') or '').lstrip('#').upper()
            lid = None
            if st in line_colors and line_colors[st] not in decor: lid = line_colors[st]
            elif fl in line_colors and line_colors[fl] not in decor: lid = line_colors[fl]
            if lid:
                try:
                    p = parse_path(elem.get('d',''))
                    if len(p) > 0: colored.append((lid, p, ctm))
                except Exception: pass
        for child in elem:
            walk(child, ctm)
    walk(root, (1,0,0,1,0,0))
    print('colored paths:', len(colored))

    # sample all paths into viewBox coords, grouped by line
    line_samples = defaultdict(list)  # line -> list of (x,y)
    for (lid, p, ctm) in colored:
        try: L = p.length()
        except: continue
        if L <= 0: continue
        n = max(4, min(1500, int(L/5.0)+1))
        for i in range(n):
            pt = p.point(i/(n-1))
            line_samples[lid].append(apply(ctm, pt.real, pt.imag))

    # step 2: min distance per (station, line) -> cleaned membership
    station_lines = defaultdict(set)
    mind = {}  # (station, line) -> min dist
    for s in stations:
        p = pos[s['n']]
        best = None
        for lid, pts in line_samples.items():
            d = min((pt[0]-p[0])**2 + (pt[1]-p[1])**2 for pt in pts)
            d = math.sqrt(d)
            mind[(s['n'], lid)] = d
            if d <= 7:
                station_lines[s['n']].add(lid)
            if best is None or d < best[0]:
                best = (d, lid)
        if not station_lines[s['n']] and best and best[0] <= 15:
            station_lines[s['n']].add(best[1])
    uncovered = [s['n'] for s in stations if not station_lines[s['n']]]
    print('stations covered:', len(stations)-len(uncovered), 'of', len(stations), '| uncovered:', uncovered)
    print('interchanges:', sum(1 for v in station_lines.values() if len(v) >= 2))
    # distribution of min distances for the closest line (sanity)
    closest = [min(mind[(s['n'], l)] for l in line_samples) for s in stations]
    print('closest-line distance: max %.1f, p95 %.1f' % (max(closest), sorted(closest)[int(len(closest)*0.95)]))

    # step 3: geometric edges (per-path consecutive), restricted to membership
    # (recompute per-path stations with the tight rule, using samples)
    edges = set()
    for (lid, p, ctm) in colored:
        try: L = p.length()
        except: continue
        if L <= 0: continue
        n = max(4, min(1500, int(L/5.0)+1))
        samples = []
        for i in range(n):
            pt = p.point(i/(n-1))
            samples.append(apply(ctm, pt.real, pt.imag))
        found = {}
        for s in stations:
            if lid not in station_lines[s['n']]: continue
            x, y = pos[s['n']]
            best = None; bestd = 1e9
            for idx, (sx, sy) in enumerate(samples):
                d2 = (sx-x)**2 + (sy-y)**2
                if d2 < bestd: bestd = d2; best = idx
            if best is not None and bestd < 12*12:
                found[s['n']] = best
        ordered = [name for name, _ in sorted(found.items(), key=lambda kv: kv[1])]
        for a, b in zip(ordered, ordered[1:]):
            if a != b:
                edges.add((a, b, lid) if a < b else (b, a, lid))
    print('geometric edges:', len(edges))

    # drop skip edges: a same-line station lies between the endpoints
    def between(a, b, c, lid):
        # c on segment a-b (within 25 units) and strictly between
        ax, ay = pos[a]; bx, by = pos[b]; cx, cy = pos[c]
        ab = dist((ax,ay),(bx,by))
        ac = dist((ax,ay),(cx,cy)); bc = dist((bx,by),(cx,cy))
        if ac < 10 or bc < 10: return False
        # distance from c to line ab
        t = max(0.0, min(1.0, ((cx-ax)*(bx-ax)+(cy-ay)*(by-ay))/(ab*ab))) if ab > 0 else 0
        px, py = ax + t*(bx-ax), ay + t*(by-ay)
        return math.hypot(cx-px, cy-py) < 25 and abs(ac+bc-ab) < 30
    dropped = 0
    clean_edges = set()
    for (a, b, lid) in edges:
        skip = False
        for c in station_lines:
            if c in (a, b) or lid not in station_lines[c]: continue
            if between(a, b, c, lid):
                skip = True; break
        if skip: dropped += 1
        else: clean_edges.add((a, b, lid))
    print('dropped skip edges:', dropped, '| clean edges:', len(clean_edges))
    edges = clean_edges

    # step 4: graft per line until connected (nearest component pair < 600)
    line_nodes = defaultdict(set)
    for (a, b, lid) in edges:
        line_nodes[lid].add(a); line_nodes[lid].add(b)
    # also include stations that belong to a line but have no edge yet
    for s in stations:
        for lid in station_lines[s['n']]:
            line_nodes[lid].add(s['n'])
    grafts = []
    for lid in sorted(line_nodes):
        nodes = line_nodes[lid]
        adj = defaultdict(set)
        for (a, b, l2) in edges:
            if l2 == lid:
                adj[a].add(b); adj[b].add(a)
        def components():
            seen = set(); comps = []
            for n in nodes:
                if n in seen: continue
                stack = [n]; comp = set()
                while stack:
                    x = stack.pop()
                    if x in comp: continue
                    comp.add(x); seen.add(x); stack.extend(adj[x]-comp)
                comps.append(comp)
            return comps
        while True:
            comps = components()
            if len(comps) <= 1: break
            # nearest pair across different components
            best = None
            for i in range(len(comps)):
                for j in range(i+1, len(comps)):
                    for a in comps[i]:
                        for b in comps[j]:
                            d = dist(pos[a], pos[b])
                            if best is None or d < best[0]:
                                best = (d, a, b)
            if best is None or best[0] >= 600:
                print(f'line {lid}: cannot graft, {len(comps)} components remain, nearest gap {best[0]:.0f}' if best else f'line {lid}: {len(comps)} components, no pair')
                break
            d, a, b = best
            edges.add((a, b, lid) if a < b else (b, a, lid))
            adj[a].add(b); adj[b].add(a)
            grafts.append((lid, a, b, round(d)))
    print('graft edges added:', len(grafts))
    for g in grafts: print('  graft:', g)

    # step 5: per-line chains for display
    lines_out = {}
    for lid in sorted(line_nodes):
        adj = defaultdict(set)
        for (a, b, l2) in edges:
            if l2 == lid:
                adj[a].add(b); adj[b].add(a)
        nodes = line_nodes[lid]
        # walk chains: start at degree-1 nodes; loops handled by walking until back
        chains = []
        visited = set()
        ends = sorted([n for n in nodes if len(adj[n]) == 1])
        starts = ends if ends else ([sorted(nodes)[0]] if nodes else [])
        for st in starts:
            if st in visited: continue
            chain = [st]; visited.add(st)
            prev, cur = None, st
            while True:
                nxts = [x for x in adj[cur] if x != prev and x not in visited]
                if not nxts: break
                nxt = nxts[0]
                chain.append(nxt); visited.add(nxt)
                prev, cur = cur, nxt
            chains.append(chain)
        # leftover nodes (loops / branches): walk from any unvisited node
        for n in sorted(nodes):
            if n in visited: continue
            chain = [n]; visited.add(n)
            prev, cur = None, n
            while True:
                nxts = [x for x in adj[cur] if x != prev and x not in visited]
                if not nxts: break
                nxt = nxts[0]
                chain.append(nxt); visited.add(nxt)
                prev, cur = cur, nxt
            chains.append(chain)
        # main chain = longest; keep all chains
        chains.sort(key=len, reverse=True)
        color = [k for k, v in line_colors.items() if v == lid]
        lines_out[lid] = {'color': color[0] if color else '', 'chains': chains}
        print(f"line {lid}: {len(nodes)} stations, {len(chains)} chain(s), longest {len(chains[0]) if chains else 0}: {chains[0][:2]} ... {chains[0][-2:] if chains and len(chains[0])>1 else ''}")
    out = {'lines': lines_out, 'edges': sorted([list(e) for e in edges])}
    json.dump(out, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('wrote', OUT, '| total edges:', len(edges))

    # step 6: Dijkstra spot-checks (cost = 1/stop + 4/transfer)
    adj2 = defaultdict(list)
    for (a, b, lid) in edges:
        adj2[a].append((b, lid)); adj2[b].append((a, lid))
    def route(frm, to):
        # state (station, line); cost = stops + 4*transfers
        start = [(0, 0, frm, None, [])]  # cost, stops, station, line, path
        best = {}
        heapq.heapify(start)
        while start:
            cost, stops, st, ln, path = heapq.heappop(start)
            key = (st, ln)
            if key in best and best[key] <= cost: continue
            best[key] = cost
            if st == to:
                return cost, stops, path + [(st, ln)]
            for (nb, ll) in adj2[st]:
                nc = cost + 1 + (4 if (ln is not None and ll != ln) else 0)
                heapq.heappush(start, (nc, stops+1, nb, ll, path + [(st, ln)]))
        return None
    for (a, b) in [('苹果园','国贸'), ('天安门东','奥林匹克公园'), ('苹果园','北京南站'), ('西直门','宋家庄'), ('巴沟','国贸'), ('天通苑北','西单')]:
        r = route(a, b)
        if r:
            cost, stops, path = r
            # compress into segments
            segs = []
            cur = None
            for (st, ln) in path:
                if ln is None: continue
                if cur is None or cur[0] != ln:
                    cur = [ln, st, st, 1]; segs.append(cur)
                else:
                    cur[2] = st; cur[3] += 1
            print(f'ROUTE {a} -> {b}: {stops} stops, cost {cost}: ' + ' | '.join(f"{s[0]}线 {s[1]}-{s[2]}({s[3]}站)" for s in segs))
        else:
            print(f'ROUTE {a} -> {b}: NO ROUTE')

if __name__ == '__main__':
    main()
