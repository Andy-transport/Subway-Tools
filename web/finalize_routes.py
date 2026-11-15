"""Final route graph for Beijing subway motion: explicit line orders, verified
against the MTR2.8.0 diagram geometry (stations.json positions + track edges)
and the real network. The geometric derivation (gen_routes.py) got the order
~90% right; the remaining errors (wrong-line snaps at dense interchanges,
missing termini, a branched T1) are fixed here by hand. Deterministic: no
dependence on the geometric chain walk, whose splits vary between runs.
Writes web/routes.json: {lines: {id: {color, name, stations, loop}},
edges: [[a,b,line], ...]}. Run on the dev machine; Actions inlines routes.json.

Notes:
- 潞阳 is labelled in the diagram but Line 22 is not drawn in it, so 潞阳 has
  no line and no routes (searchable + locatable only).
- 金融街 / 堤上村 / 香河园 are not labelled in the SVG, so they are
  absent from stations.json and from routing. 3号航站楼 / 2号航站楼 ARE
  labelled (font-size 3.52778) but were missed by gen_stations.py because
  its is_cjk() rejects names starting with a digit; they were added by
  hand with the same transform-aware nearest-marker snap
  (3号航站楼 (2786,1684), 2号航站楼 (2693,1546)).
- T1 branches at 荣京东街: main line to 屈庄, spur to 荣昌东街 (YZ interchange).
"""
import json, math, heapq
from collections import defaultdict

STATIONS = 'web/stations.json'
OUT = 'web/routes.json'

NAMES = {
    '1': '1号线', '2': '2号线', '3': '3号线', '4': '4号线', '5': '5号线',
    '6': '6号线', '7': '7号线', '8': '8号线', '9': '9号线', '10': '10号线',
    '11': '11号线', '12': '12号线', '13': '13号线', '13X': '13A线',
    '14': '14号线', '15': '15号线', '16': '16号线', '17': '17号线',
    '19': '19号线', 'S1': 'S1线', 'XJ': '西郊线', 'YZ': '亦庄线',
    'T1': '亦庄T1线', 'CP': '昌平线', 'FS': '房山线', 'DAX': '大兴机场线',
    'AP': '首都机场线',
}
COLORS = {
    '1': 'BE3631', '2': '0F6192', '3': 'C8102E', '4': '008994', '5': 'A5237A',
    '6': 'D29404', '7': 'F9C374', '8': '009263', '9': '96BE0B', '10': '009ABA',
    '11': 'ED796B', '12': '9B5A1A', '13': 'F8E114', '13X': '5654A2',
    '14': 'D4A7A1', '15': '6B3777', '16': '7C9E21', '17': '00A9A9',
    '19': 'D6ABC1', 'S1': 'B0561F', 'XJ': 'E20621', 'YZ': 'E20072',
    'T1': 'E6081B', 'CP': 'DD83B0', 'FS': 'E15C28', 'DAX': '004E9B',
    'AP': 'A09AB8',
}
LOOPS = {'2', '10'}
# T1 spur: 荣昌东街 branches off 荣京东街 (not on the main chain)
T1_SPUR = ('荣京东街', '荣昌东街')
# AP note: trains run 北新桥-东直门-三元桥-3号航站楼-2号航站楼-三元桥-
# 东直门-北新桥, so 2号航站楼 DOES connect back to 三元桥 directly (the
# return leg does not stop at 3号航站楼). That edge is deliberately NOT in
# the graph: Dijkstra treats edges as undirected, so it would let outbound
# routes shortcut 三元桥 -> 2号航站楼 past 3号航站楼 (管庄->2号航站楼 would
# show 14站 instead of the correct 15站). AP is therefore a plain linear
# line; inbound T2 -> city costs +1 stop (via 3号航站楼) instead of the
# direct return leg.

LINES = {
'1': ['福寿岭','苹果园','古城','八角游乐园','八宝山','玉泉路','五棵松','万寿路','军事博物馆','木樨地','南礼士路','复兴门','西单','天安门西','天安门东','王府井','东单','建国门','永安里','国贸','大望路','四惠','四惠东','高碑店','传媒大学','双桥','管庄','八里桥','通州北苑','果园','九棵树','梨园','临河里','土桥','花庄','环球度假区'],
'2': ['西直门','车公庄','阜成门','复兴门','长椿街','宣武门','和平门','前门','崇文门','北京站','建国门','朝阳门','东四十条','东直门','雍和宫','安定门','鼓楼大街','积水潭'],
'3': ['东四十条','工人体育场','团结湖','朝阳公园','石佛营','朝阳站','姚家园','东坝南','东坝','东坝北'],
'4': ['安河桥北','北宫门','西苑','圆明园','北京大学东门','中关村','人民大学','魏公村','国家图书馆','动物园','西直门','新街口','平安里','西四','灵境胡同','西单','宣武门','菜市口','陶然亭','北京南站','马家堡','角门西','公益西桥','新宫','西红门','高米店北','高米店南','枣园','清源路','黄村西大街','黄村火车站','义和庄','生物医药基地','天宫院'],
'5': ['天通苑北','天通苑','天通苑南','立水桥','立水桥南','北苑路北','大屯路东','惠新西街北口','惠新西街南口','和平西桥','和平里北街','雍和宫','北新桥','张自忠路','东四','灯市口','东单','崇文门','磁器口','天坛东门','蒲黄榆','刘家窑','宋家庄'],
'6': ['金安桥','苹果园','杨庄','西黄村','廖公庄','田村','海淀五路居','慈寿寺','花园桥','白石桥南','二里沟','车公庄西','车公庄','平安里','北海北','南锣鼓巷','东四','朝阳门','东大桥','呼家楼','金台路','红庙','十里堡','青年路','褡裢坡','黄渠','常营','草房','物资学院路','通州北关','通运门','北运河西','北运河东','郝家府','东夏园','潞城'],
'7': ['北京西站','湾子','达官营','广安门内','菜市口','虎坊桥','珠市口','桥湾','磁器口','广渠门内','广渠门外','双井','九龙山','大郊亭','百子湾','化工','南楼梓庄','欢乐谷景区','垡头','双合','焦化厂','黄厂','郎辛庄','黑庄户','万盛西','万盛东','群芳','高楼金','环球度假区'],
'8': ['朱辛庄','育知路','平西府','回龙观东大街','霍营','育新','西小口','永泰庄','林萃桥','森林公园南门','奥林匹克公园','奥体中心','北土城','安贞门','安华桥','安德里北街','鼓楼大街','什刹海','南锣鼓巷','中国美术馆','金鱼胡同','王府井','前门','珠市口','天桥','永定门外','木樨园','海户屯','大红门','大红门南','和义','东高地','火箭万源','五福堂','德茂','瀛海'],
'9': ['国家图书馆','白石桥南','白堆子','军事博物馆','北京西站','六里桥东','六里桥','七里庄','丰台东大街','科怡路','丰台南路','丰台科技园','郭公庄'],
'10': ['巴沟','苏州街','海淀黄庄','知春里','知春路','西土城','牡丹园','健德门','北土城','安贞门','惠新西街南口','芍药居','太阳宫','三元桥','亮马桥','农业展览馆','团结湖','呼家楼','金台夕照','国贸','双井','劲松','潘家园','十里河','分钟寺','成寿寺','宋家庄','石榴庄','大红门','角门东','角门西','草桥','纪家庙','首经贸','丰台站','泥洼','六里桥','莲花桥','公主坟','西钓鱼台','慈寿寺','车道沟','长春桥','火器营'],
'11': ['模式口','金安桥','北辛安','新首钢'],
'12': ['四季青桥','蓝靛厂','长春桥','苏州桥','人民大学','大钟寺','蓟门桥','北太平庄','马甸桥','安华桥','安贞桥','和平西桥','光熙门','三元桥','将台西','高家园','驼房营','东坝西','东坝北'],
'13': ['西直门','大钟寺','知春路','五道口','上地','清河站','西二旗','龙泽','龙泽西','回龙观','霍营','立水桥','北苑','望京西','芍药居','光熙门','柳芳','东直门'],
'13X': ['马连洼','回龙观西大街','文华路','回龙观东大街','霍营东','天通苑','太平庄','天通苑东'],
'14': ['张郭庄','园博园','大瓦窑','郭庄子','大井','七里庄','西局','东管头','丽泽商务区','菜户营','西铁营','景风门','北京南站','陶然桥','永定门外','景泰','蒲黄榆','方庄','十里河','北工大西门','平乐园','九龙山','大望路','金台路','朝阳公园','枣营','东风北桥','将台','望京南','阜通','望京','东湖渠','来广营','善各庄'],
'15': ['清华东路西口','六道口','北沙滩','奥林匹克公园','安立路','大屯路东','关庄','望京西','望京','望京东','崔各庄','马泉营','孙河','国展','花梨坎','后沙峪','南法信','石门','顺义','俸伯'],
'16': ['北安河','温阳路','稻香湖路','屯佃','永丰','永丰南','西北旺','马连洼','农大南路','西苑','万泉河桥','苏州街','苏州桥','万寿寺','国家图书馆','二里沟','甘家口','玉渊潭东门','木樨地','达官营','红莲南路','丽泽商务区','东管头南','丰台站','丰台南路','富丰桥','看丹','榆树庄','洪泰庄','宛平城'],
'17': ['未来科学城北','未来科学城','天通苑东','清河营','红军营','望京西','太阳宫','西坝河','左家庄','工人体育场','东大桥','永安里','广渠门外','潘家园西','十里河','周家庄','十八里店','北神树','次渠北','次渠','嘉会湖'],
'19': ['牡丹园','北太平庄','积水潭','平安里','太平桥','牛街','景风门','草桥','新发地','新宫'],
'S1': ['苹果园','模式口','四道桥','桥户营','栗园庄','小园','石厂'],
'XJ': ['巴沟','颐和园西门','茶棚','国家植物园','香山'],
'YZ': ['宋家庄','肖村','小红门','旧宫','亦庄桥','亦庄文化园','万源街','荣京东街','荣昌东街','同济南路','经海路','次渠南','次渠','亦庄火车站'],
'T1': ['定海园','经海路','定海园西','经海一路','亦创会展中心','同济南路','荣京东街','荣昌东街','亦庄同仁','鹿圈东','泰河路','四海庄','太和桥北','瑞合庄','融兴街','屈庄'],
'CP': ['昌平西山口','十三陵景区','昌平','昌平东关','北邵洼','南邵','沙河高教园','沙河','巩华城','朱辛庄','生命科学园','西二旗','清河站','朱房北','清河小营桥','学知园','六道口','学院桥','西土城','蓟门桥'],
'FS': ['燕山','房山城关','饶乐府','马各庄','大石河东','星城','阎村','紫草坞','阎村东','苏庄','良乡南关','良乡大学城西','良乡大学城','良乡大学城北','广阳城','篱笆房','长阳','稻田','大葆台','郭公庄','白盆窑','花乡东桥','首经贸','东管头南'],
'DAX': ['草桥','大兴新城','大兴机场'],
'AP': ['北新桥','东直门','三元桥','3号航站楼','2号航站楼'],
}

def main():
    stations = {s['n']: (s['x'], s['y']) for s in json.load(open(STATIONS, encoding='utf-8'))}
    # edges from consecutive pairs; loops close; T1 spur handled separately
    edges = set()
    for lid, sts in LINES.items():
        if lid == 'T1':
            main = [s for s in sts if s != '荣昌东街']
            for a, b in zip(main, main[1:]):
                edges.add((a, b, lid) if a < b else (b, a, lid))
            a, b = T1_SPUR
            edges.add((a, b, lid) if a < b else (b, a, lid))
            continue
        for a, b in zip(sts, sts[1:]):
            edges.add((a, b, lid) if a < b else (b, a, lid))
        if lid in LOOPS and len(sts) > 2:
            a, b = sts[-1], sts[0]
            edges.add((a, b, lid) if a < b else (b, a, lid))
    print('lines:', {lid: len(v) for lid, v in sorted(LINES.items())})
    print('total edges:', len(edges))

    # validation
    covered = set()
    for sts in LINES.values(): covered.update(sts)
    print('names not in stations.json:', [n for sts in LINES.values() for n in sts if n not in stations])
    print('orphans (in no line):', [s for s in stations if s not in covered])
    for lid, sts in LINES.items():
        if len(sts) != len(set(sts)):
            print(f'  DUP in line {lid}:', [n for n in sts if sts.count(n) > 1])
    def dist(a, b):
        return math.hypot(stations[a][0]-stations[b][0], stations[a][1]-stations[b][1])
    for lid, sts in LINES.items():
        pairs = list(zip(sts, sts[1:]))
        if lid in LOOPS: pairs.append((sts[-1], sts[0]))
        if lid == 'T1':
            pairs = [(a, b) for a, b in pairs if not (a == '荣昌东街' or b == '荣昌东街')]
            pairs.append(T1_SPUR)
        for a, b in pairs:
            d = dist(a, b)
            if d > 450:
                print(f'  LONG edge {lid}: {a}-{b} {d:.0f}')
    # skip check (tighter: 15 units, path diff < 20)
    for lid, sts in LINES.items():
        sset = set(sts)
        pairs = list(zip(sts, sts[1:]))
        if lid in LOOPS: pairs.append((sts[-1], sts[0]))
        if lid == 'T1':
            pairs = [(a, b) for a, b in pairs if not (a == '荣昌东街' or b == '荣昌东街')]
            pairs.append(T1_SPUR)
        for a, b in pairs:
            ax, ay = stations[a]; bx, by = stations[b]
            ab = dist(a, b)
            for c in sset - {a, b}:
                cx, cy = stations[c]
                ac = dist(a, c); bc = dist(b, c)
                if ac < 10 or bc < 10: continue
                t = max(0.0, min(1.0, ((cx-ax)*(bx-ax)+(cy-ay)*(by-ay))/(ab*ab))) if ab > 0 else 0
                px, py = ax + t*(bx-ax), ay + t*(by-ay)
                if math.hypot(cx-px, cy-py) < 15 and abs(ac+bc-ab) < 20:
                    print(f'  SKIP? {lid}: {a}-{b} passes near {c}')

    out = {'lines': {lid: {'color': COLORS[lid], 'name': NAMES[lid],
                            'stations': sts, 'loop': lid in LOOPS}
                      for lid, sts in LINES.items()},
           'edges': sorted([list(e) for e in edges])}
    json.dump(out, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('wrote', OUT)

    # Dijkstra spot-checks (state = station+line; cost = stops + 4/transfer)
    adj = defaultdict(list)
    for (a, b, lid) in edges:
        adj[a].append((b, lid)); adj[b].append((a, lid))
    def route_segs(frm, to):
        heap = [(0, 0, frm, None, [(frm, None)])]
        best = {}
        while heap:
            cost, stops, st, ln, path = heapq.heappop(heap)
            key = (st, ln)
            if key in best and best[key] <= cost: continue
            best[key] = cost
            if st == to:
                segs = []
                idx = 0
                for (s, l) in path[1:]:
                    if segs and segs[-1]['line'] == l:
                        segs[-1]['to'] = s
                        segs[-1]['stops'] += 1
                    else:
                        segs.append({'line': l, 'from': path[idx][0], 'to': s, 'stops': 1})
                    idx += 1
                return stops, segs
            for (nb, ll) in adj[st]:
                nc = cost + 1 + (4 if (ln is not None and ll != ln) else 0)
                heapq.heappush(heap, (nc, stops+1, nb, ll, path + [(nb, ll)]))
        return None
    for (a, b) in [('苹果园','国贸'), ('天安门东','奥林匹克公园'), ('苹果园','北京南站'),
                   ('西直门','宋家庄'), ('巴沟','国贸'), ('天通苑北','西单'),
                   ('草桥','大兴机场'), ('石厂','国贸'), ('俸伯','西单'), ('昌平西山口','国贸'),
                   ('定海园','屈庄'), ('荣昌东街','次渠'), ('昌平西山口','大兴机场'),
                   ('管庄','2号航站楼'), ('2号航站楼','北新桥'), ('东直门','3号航站楼')]:
        r = route_segs(a, b)
        if r:
            stops, segs = r
            print(f"ROUTE {a} -> {b}: {stops}站: " + " | ".join(
                f"{NAMES[s['line']]} {s['from']}→{s['to']} ({s['stops']}站)" for s in segs))
        else:
            print(f'ROUTE {a} -> {b}: NO ROUTE')

if __name__ == '__main__':
    main()
