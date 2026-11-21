# 石家庄（sjz）数据包 NOTES — 2026-11-21

第 13 个城市。研究+数据准备完成；**未动** template.html / build_offline.py /
AppDelegate.swift / build.sh / trains.json（接线由主会话做，清单见文末）。

## 已核实事实（来源）

- **线网（2026 年 11 月）**：3 条运营线路、**60 座车站（去重）**、63 个线路站次、
  **换乘站 3 座**、运营里程 76.5 km。
  来源：中文维基百科「石家庄地铁车站」模板（2026-11-04 版）逐线站序、高德线网
  实时数据（maps.amap.com/ssr/subway/shijiazhuang-1301）、中/英文维基百科
  「石家庄地铁」线路表三方交叉一致；63 − 3（换乘站各多计 1 次）= 60 ✓。
- **未开通、已排除**：1 号线二期北段 **东上泽、东洋**（福泽以北，预计 2026 年底
  开通）；1 号线三期 **上庄、槐安路**（西王以西，在建）；4、5、6 号线全线（在建）。
  这 4 站在 RMP 图上有 sjz1 颜色的站节点，build 脚本断言排除集合恰好为此 4 站。
  注意二期其余 6 站（洨河大道以东：西庄、东庄、会展中心、商务中心、园博园、
  福泽）已于 2019-06-26 开通，**在**数据内；洨河大道本身是一期终点（2017 开通）。
- **SierraQin/metro 不覆盖石家庄**：该仓库是北京市轨道交通线路配置图
  （2026-11-21 查 GitHub API，默认分支 master，文件树无石家庄内容），
  本包数据来自 RMP + 维基百科/高德，与深圳/成都/青岛先例一致。

## 线路表（颜色取自 RMP 官方配色元组 city=shijiazhuang）

| key | 线路 | 颜色 | 站数 | 起讫 |
|---|---|---|---|---|
| 1 | 1号线 | E53E30 | 26 | 西王 – 福泽（34.3 km）|
| 2 | 2号线 | FEC30A | 15 | 柳辛庄 – 嘉华路（15.5 km）|
| 3 | 3号线 | 00A1E0 | 22 | 西三庄 – 乐乡（26.7 km）|

换乘站 3 座：新百广场（1/3）、北国商城（1/2）、石家庄站（2/3）。

站名核对要点：2 号线是**塔坛**（非塔谈）；3 号线是**塔冢**，与塔坛为两站；
**庄窠·铁道大学**的间隔号按官方名保留（py/ini 同青岛全角括号先例保留符号：
zhuangke·tiedaodaxue / zk·tddx）；**洨河大道**读 xiáo（xiaohedadao）；
**乐乡**读 lè（lexiang）。拼音由 pypinyin 生成，逐项核对无误，无 CHAR_FIX。

## 票价（已核实，官方政策）

里程分段计价，依据《关于石家庄市轨道交通票价政策的通知》（石家庄市价格
主管部门；中文维基百科「石家庄地铁·票务政策」与石家庄本地宝转载的政策
原文一致）：

- 0–6 km ¥2｜6–20 km 每增加 7 km 加 ¥1｜20–36 km 每增加 8 km 加 ¥1｜
  36–54 km 每增加 9 km 加 ¥1｜54 km 以上每增加 10 km 加 ¥1
- 公式：`km<=6:2; <=20:2+ceil((km-6)/7); <=36:4+ceil((km-20)/8);
  <=54:6+ceil((km-36)/9); else 8+ceil((km-54)/10)`
- 现行全线网最高票价 ¥7（维基百科）。无逐站里程表入库：app 侧需 px→km
  标定（同青岛待办）。注：石家庄自 2021-12 起有「2 元畅享地铁」惠民活动
  （指定票种不限里程 2 元），属优惠活动非常规定价，app 票价按上述正式
  票制计算即可，活动信息供参考。

## 时刻表状态：官方逐站时刻存在，但本包未建成（不要臆造）

- 石家庄地铁官方发布各线现执行运行图首末班车时间（官网 sjzmetro.cn，
  英文维基百科引用其 2019-06-26 版「1、3号线现执行运行图首末班车时间」；
  官方 App 石慧行亦有逐站时刻）。
- **未建成 `web/timetable/sjz.json`**：官网从本机网络不可达
  （www.sjzmetro.cn 跳转至 :8191 端口后超时，https 亦超时，2026-11-21
  实测，同成都/青岛官网情况）。**逐站真实时刻需后续从官网/官方 App
  采集，不要按估算填充。**

## 官方 App

- **石慧行**，App Store **id 6444716093**，卖家 Shijiazhuang Metro
  Co.,Ltd（石家庄市轨道交通集团有限责任公司），bundleId
  `com.bwton.sjzmetro`，v1.12.0。运营方官方 App（扫码/人脸乘车、站点
  查询、逐站时刻）——与深圳/青岛用运营方官方 App 的先例一致，推荐作
  「打开石家庄地铁」跳转目标。
- 另一个官方背景 App：**石家庄轨道交通** id 1449805507（一卡通科技，
  com.bwton.msx.sjz）。如主会话更倾向一卡通版可替换，id 一并记录。
- URL scheme：**未查到公开 scheme，不要臆造**；跳转用 App Store 链接
  （同其他城市先例）。App 图标（App Store artwork）未取，接线时按
  既有做法下载 512 图裁 120×120。

## 主题色推荐

- **#E53E30（1 号线红）**：按任务口径取 1 号线官方色（RMP 配色元组）。
  深色变体（选中态/文字）按金华先例 ×0.79 推导为 **#B53126**。

## 车型（china-emu.cn 石家庄页，2026-11-21；共 5 条）

按 trains.json 既有 schema 记录，接线时并入 web/trains.json 的 sjz 条目：

| model | maker | line | spec |
|---|---|---|---|
| 暂无型号 | 中车唐山机车车辆有限公司 | 1号线 | 90 km/h · 6A · 4M2T · GoA2 · 2016-2017造 |
| 暂无型号 | 中车唐山机车车辆有限公司 | 1号线 | 90 km/h · 6A · 4M2T · GoA2 · 2018-2019造 |
| SFM7x | 中车青岛四方机车车辆股份有限公司 | 2号线 | 90 km/h · 6A · 4M2T · GoA2 · 2019-2020造 |
| SFM39 | 中车青岛四方机车车辆股份有限公司 | 3号线 | 90 km/h · 6A · 4M2T · GoA2 · 20组 · 2016-2017造 |
| SFM85？ | 中车青岛四方机车车辆股份有限公司 | 3号线 | 90 km/h · 6A · 4M2T · GoA2 · 2020-2021造 |

- 两条唐山「暂无型号」的年份按 china-emu 石家庄页列表顺序与型号页
  （M-879-T / M-878-T）文档顺序对应绑定；两页本身均为「暂无型号、
  唐山、1 号线、6A、4M2T、90 km/h」，已逐页核对。
- SFM39 的 20 组与中文维基「青岛四方 SFM 系列列表」（石家庄地铁3号线
  SFM39型 20列 2016~2017）互证。其余各条数量 china-emu 标注未知，
  spec 按既有先例省略数量段，不臆造。

## 经纬度

- **`web/latlng/latlng-sjz.json` 60/60 全覆盖**。来源：Wikidata
  SPARQL（P81 连接线路 = 1/2/3 号线条目 Q30326155 / Q85776743 /
  Q30326157，取 P625），WGS84，与青岛先例一致。换乘站两线条目坐标
  一致，无一站为估算。

## 产出文件

- `web/shijiazhuang/rmp-gallery-shijiazhuang.json` — RMP Gallery 石家庄
  源数据（railmapgen/rmp-gallery GitHub raw，version 56，117 节点/
  110 边）；`rmp-metadata-shijiazhuang.json` 同目录（其 reference 指向
  官网 sjzmetro.cn 的官方线网图图片）。
- `web/shijiazhuang/stations.json` — 60 站 {n, py, ini, x, y}，x/y 为
  RMP 原始坐标（同深圳/成都/青岛做法，build 时按 viewBox 归一化）。
- `web/shijiazhuang/routes.json` — {lines: {key: {color, name,
  stations[]}}, edges: [[a, b, lineKey], …]}，顶层 edges 共 60 条。
- `web/shijiazhuang/routes_geo.json` — 北京同款形状 {lines: {key:
  {color, chains: [[站序]]}}, edges}，chains 与 routes.json 站序一致。
- `web/shijiazhuang/build_sjz.py` — 可复现构建脚本：沿 RMP 图逐线走链
  （含非站节点 BFS 穿越），与官方运营站序断言全等（集合+顺序），并断言
  被排除的 RMP 站恰好为 4 座未开通站。
- `web/latlng/latlng-sjz.json` — 60 站经纬度。
- `web/shijiazhuang/MAP_EXPORT.md` — map.svg 浏览器导出步骤。

## 缺口 / 待办（主会话接线时注意）

1. **map.svg 需浏览器导出**：RMP 无直链 SVG（同深圳/青岛），步骤见
   MAP_EXPORT.md。数据侧已齐（stations 的 x/y 与导出图同一坐标系）。
2. **时刻表未采集**：见上，不要估算填充；如需先行上线，可按成都先例
   整体标注 ESTIMATED 或暂不上时刻。
3. **logo 未备**：石家庄地铁 logo 需按既有做法取官方原图（不要重绘）。
4. **启动图已在目录内**（非本数据包产出）：`splash.b64` / `splash-dark.b64`
   / `splash-orig.b64` 已由主会话放入（1170×2532 JPEG，用户新启动图
   系列），接线时按既有命名接 SplashSJZ 即可。
5. **票价 px→km 标定**：RMP 示意图无里程，fare 计算需标定（同青岛
   待办）；逐线实际长度 L1 34.3 / L2 15.5 / L3 26.7 km 可作标定参考。
6. **虚拟换乘未备**：石家庄 3 座换乘站均为同名站内换乘，无出站换乘
   对，暂不需要 transfers 数据（同青岛上线初期状态）。
7. RMP 数据 version 56 较旧，但站集与现行运营线网逐站断言一致
   （build 全绿），可用；日后 RMP 更新版本时重跑 build_sjz.py 即可。

## 接线清单（照青岛 WIRING 模式，供主会话）

- 城市顺序末尾加 `sjz`；城市名 石家庄/石家莊/Shijiazhuang；主题色
  E53E30（深色 B53126）。
- build_offline.py：SJZ 数据（stations/routes/latlng/timetable 占位）、
  SJZ 地图 viewBox（导出 map.svg 后填）、SJZ_SPLASH/SJZ_LOGO 占位。
- build.sh：SplashSJZ.jpg / ShijiazhuangLogo.png 行（素材就位后）。
- 58 城目录：石家庄由「即将开通」灰行改为已支持（CAMET 目录口径主
  会话核对）。
- trains.json：新增 sjz 条目（车型表见上，name 石家庄，name_en
  Shijiazhuang）。
- 原生侧：accent 搜索按钮色、transit 跳转（石慧行 6444716093）、
  SplashSJZ 命名（PreviewCardView.refreshPoster 的 city switch 加
  "sjz" → "SplashSJZ"）。
