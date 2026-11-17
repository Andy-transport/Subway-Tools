# Subway tools（地铁配线图 iOS 应用）

北京市轨道交通线路配置图，做成 iPhone 应用。中文名：地铁交路；英文名：Beijing Subway motion，版本 1.0.2（配线图数据 2.8.0；新增沈阳地铁，6 条已开通线路 1/2/3/4/9/10、144 个车站，点顶部的城市名可在北京 / 沈阳之间切换）。应用图标为蓝底黑 A。

- 地图来源：[SierraQin/metro](https://github.com/SierraQin/metro)（CC0 1.0 协议），正式版 2.8.0（2026-07-14）
- 应用：一个 WKWebView 壳，里面是完全离线的地图网页——地图 SVG、PDF 和 JS 库都打在包里，不用联网、不用 VPN
- 功能：整张配线图，捏合缩放、拖动；城市切换（点顶部城市名在北京 / 沈阳之间切换；沈阳地图为用户提供的 2026-06 线网图，6 条线 144 站 15 个换乘站，可搜索、可换乘；沈阳站暂无坐标，点站名不定位到图上）；原生 UITabBar 底栏（iOS 27 SDK；换乘 / 配线图 / 搜索 / 设置，SF Symbols 图标，选中地铁蓝 #003380；点底栏或在底栏上滑动切换，网页底栏已隐藏）；换乘页搜索按钮为液态玻璃（半透明蓝 + 磨砂 + 高光）；适配 iPhone Duo 折叠屏（窗口尺寸变化时地图自动重新适配，当前缩放/平移保持不变）；构建时优先选用最新的 iOS SDK 27.x（27.3/27.2/27.1/27.0），没有则用默认 Xcode；换乘页可选用时最少 / 换乘最少，并显示预计用时和到达时间（每站约 2 分钟，每次换乘约 5 分钟）；开屏为北京配线查询设计图；应用名 Beijing Subway motion，版本 1.0.2；车站搜索（中文、拼音、首字母，点车站定位到图上，北京 420 个车站，来自地图 SVG 本身；沈阳 144 个车站，来自维基百科线路表）；换乘（出发/到达可直接输入站名联想选站，点“出发/到达”可打开全部车站列表，北京 26 条线、508 条边，沈阳 6 条线、153 条边，算最优路线，点一段在图上查看；搜索按钮蓝色）；深色模式（跟随系统，更多里可切浅色/深色）；横竖屏都全覆盖显示；底栏可点可左右滑动切换

## 打包

GitHub Actions（macOS）跑 `bash build.sh`：先把离线网页拼出来，再用 `swiftc` 编译 Swift 壳（不签名），打包成未签名的 IPA，侧载安装时用自己的 Apple ID 重新签名。

## 说明

原作者在 README 里注明：本图由互联网公开资料结合作者乘车经历整理推测而成，不保证内容真实性和准确性；仅表示线路和车站之间的逻辑关系，并非按真实比例绘制，不应被作为规划出行的依据。


## Build 20 (v1.0.2) — 数据修正 + 虚拟换乘 + 液态玻璃
- 数据修正：16号线补上二里沟站（6<->16换乘，2023-03-18开通），19号线补上牛街站（10站），7号线去掉错误的牛街站。边数 508 -> 509。十里堡->花乡东桥：用时模式 16站/3换乘/47分；换乘最少 20站/2换乘/50分。
- 虚拟换乘：路线里换乘站是虚拟换乘（需出站）时，显示步行小人图标 + “虚拟换乘 · 出站步行约XXX米”。目前已确认：木樨地（1<->16，约700米）、大钟寺（12<->13，约300米）；复兴门<->太平桥、广安门内<->牛街暂不可达（不同站名，无换乘边），仅作数据備註。
- 液态玻璃：地图页顶部的北京城市 pill 和搜车站 pill 改成和搜索按钮一样的蓝色液态玻璃（白字）。
- 换乘距离：仅虚拟换乘标注大概步行距离；站内换乘不标（站内步行短，无全网数据）。


## Build 21 (v1.0.2) — 票价标注
- 路线下方加一行票价标注（钱包图标）：无虚拟换乘时显示“票价连续计费”；有虚拟换乘时显示“票价不连续计费（虚拟换乘需出站）”（琥珀色）。单程票在虚拟换乘站出站后需另购票。
- 其余与 Build 20 相同（数据修正、虚拟换乘距离、液态玻璃顶栏）。


## Build 22 (v1.0.2) — 沈阳图标
- 沈阳城市图标换成用户新发的沈阳地铁标志（红底白字的圆形 S 形标志），白底：原图四角是青色，处理成纯白底，只保留红色标志。
- 其余与 Build 21 相同。


## Build 23 (v1.0.2) — 顶栏液态玻璃改 Apple 原生
- 顶部北京/搜车站两个小条去掉蓝色液态玻璃，改用中性 .glass（Apple 原生 Liquid Glass：透明底 + 模糊 + 高光 + 白边），文字恢复深蓝色 #003380；深色模式用深色玻璃 + 浅蓝字。之前蓝底白字的版本不是 Apple 原生效果。
- 其余与 Build 22 相同（沈阳新图标白底）。


## Build 24 (v1.0.2) — 应用改名
- 应用名由 Beijing Subway motion 改为 Subway motion（Info.plist 显示名 + 网页标题；因为已不只北京，沈阳也进来了）。内部包名 Metro、安装包文件名 Beijing-Subway-motion-1.0.2-unsigned.ipa 未改。
- 其余与 Build 23 相同（顶栏 Apple 原生液态玻璃、沈阳新图标白底）。


## Build 25 (v1.0.2) — 首都机场线
- 首都机场线进来了：北新桥—东直门—三元桥—3号航站楼—2号航站楼（5 站，标识色 Pantone 666C 紫灰 #A09AB8）。3号/2号航站楼在配线图里其实有标注，是之前提取站名时漏掉的（站名以数字开头，提取规则只认纯汉字）；坐标按图里标注的位置取（3号航站楼 2786,1684；2号航站楼 2693,1546）。管庄→2号航站楼现在能算了：15 站 2 换乘 40 分钟。
- 注意：机场线实际是三角运行（2号航站楼回三元桥不经 3号航站楼），但本应用的算路把边当双向，为避免去机场时抄近道跳过 3号航站楼，这里按直线算；回程（2号航站楼→市区）会多算 1 站。
- 其余与 Build 24 相同（应用名 Subway motion、顶栏 Apple 原生液态玻璃、沈阳新图标白底）。


## Build 26 (v1.0.2) — 沈阳启用图
- 沈阳的启用图换成用户新发的沈阳设计（沈阳 / 配线查询 / SHENYANG SUBWAY · TRACK LAYOUT LOOKUP，红线配线图）；北京的启用图不变（北京 / 配线查询）。
- 实现：启动图不能只靠 iOS 原生 LaunchScreen（它是静态单图），所以在网页里加了一层全屏启动图遮罩（#splashOverlay），按当前城市显示对应图片，打开时显示约 0.7 秒后淡出，切城市时显示新城市的图约 0.5 秒后淡出。北京图复用 app/splash.b64，沈阳图存为 web/shenyang/splash.b64，两张都内联进页面（BJ_SPLASH / SY_SPLASH）。
- 其余与 Build 25 相同（首都机场线、应用名 Subway motion、顶栏 Apple 原生液态玻璃、沈阳新图标白底）。


## Build 27 (v1.0.2) — 顶栏改回 Apple 官方液态玻璃
- 上一版的 .glass 底太透，saturate(180%) 还把地图的红色放大，沈阳那个小条看起来发粉，不是 Apple 官方液态玻璃。这次两个顶栏小条不用 .glass，单独做了 Apple 官方液态玻璃：磨砂近不透明白底（0.72/0.55，不再透出地图的红）、模糊加强到 28px、饱和度只提到 140%、无蓝色 tint、亮白边框 + 顶部高光（玻璃边缘反光）。深色模式用深色磨砂玻璃 + 浅蓝字。
- 其余与 Build 26 相同（沈阳启用图、首都机场线、应用名 Subway motion、沈阳新图标白底）。


## Build 28 (v1.0.2) — 预计票价 + 机场线不连续计费
- 机场线确实是出站换乘：首都机场线、大兴机场线都是单独票制，进出站要重新购票，所以票价不连续。之前只把虚拟换乘算成不连续，漏了机场线，现在补上：路线里有首都机场线或大兴机场线，票价行显示“票价不连续计费（机场线需单独购票）”。
- 票价行现在还显示预计金额，格式“预计 ¥X · 票价连续计费 / 票价不连续计费（原因）”。金额是估算：按北京计程票价（6公里内3元，6-12公里4元，12-22公里5元，22-32公里6元，32公里以上每20公里加1元），里程用配线图的示意坐标估算（55个单位约1公里，机场线段按实测距离校准过）；首都机场线单加25元，大兴机场线到大兴机场35元、到大兴新城25元；虚拟换乘分段计价。沈阳站没有坐标，暂不显示金额，只显示连续/不连续。
- 其余与 Build 27 相同（顶栏 Apple 官方液态玻璃、沈阳启用图、首都机场线、应用名 Subway motion、沈阳新图标白底）。


## Build 29 (v1.0.2) — 点城市小条弹出 Apple 原生二级菜单
- 之前点城市小条（北京/沈阳）是直接来回切换，没有菜单。现在点它会弹出 Apple 原生的底部菜单（UIAlertController action sheet，SDK 26.5 编译）：标题“切换城市”，列出“北京”“沈阳”（当前城市前面有 ✓），下面是“取消”。选一个就切过去并短暂显示该城市的启用图。实现是原生端：网页把当前城市发给原生（webkit.messageHandlers.cityMenu），原生弹出菜单，选中后调回网页的 switchCity。离线网页在浏览器里打开时没有原生端，会自动退回原来的直接切换。
- 其余与 Build 28 相同（预计票价、机场线不连续计费、顶栏 Apple 官方液态玻璃、沈阳启用图、首都机场线、应用名 Subway motion、沈阳新图标白底）。

## Build 30 (v1.0.2) — 原生液态玻璃顶栏 + 左上角城市菜单 + 沈阳票价/金色主题
- 两个顶栏 pill 改为原生 UIButton + 真正的 Apple Liquid Glass
  (UIButton.Configuration.glass(), iOS 26+；低版本用磨砂 fallback)，
  网页里的 #brandChip / #searchPill 在原生 app 里隐藏（nativeApp 检测）。
  北京保持蓝色 #003380，沈阳用用户指定的金色 #D4B686（香槟金）。
- 点城市 pill 弹出原生 UIMenu，锚定在左上角 pill 下方，不再居中；
  换乘页的城市行也调出原生菜单（UIAlertController popover，锚定 pill）。
- 沈阳预估票价：沈阳站无坐标，改用站数估算里程（每站约 1.4 km），
  按沈阳票价表计价：0-6km ¥2、6-10 ¥3、10-14 ¥4、14-21 ¥5、21-28 ¥6、
  28km 以上每 10km 加 ¥1，最高 ¥7 封顶。例：东大营街→沈阳南站 20 站约 28km → ¥6。
- 沈阳搜索点站：无坐标无法定位到图上，改为切到配线图并提示该站所属线路。
- 沈阳主题色改为金色 #D4B686（搜索按钮、偏好选中态等）；北京全部保持蓝色不变。

## Build 37 (v1.0.3) — 本地完成，待推送打包

- 上海跳转跳 Metro大都会：换乘页的跳转行按城市分三种（北京一卡通 1071038870 / 沈阳盛京通 1441271928 / 上海 Metro大都会 1202750238），都是 App Store 页面（没有确认过的 URL scheme，不猜）。
- 跳转行改成图标 + 文字：每个 App 用自己的 App Store 图标（120x120 PNG，圆角透明底，web/yikatong-icon.b64、shengjingtong-icon.b64、metrodaduhui-icon.b64）。上海跳转行是红色（.sh-theme .tr-transit #A8000C），不是北京蓝。
- iPad 适配：Info.plist 加 UIDeviceFamily 1 + 2（iPhone + iPad）；宽屏 >= 700px 时换乘/搜索面板内容居中限宽 640px，地图页保持全屏；原生控件量的是网页矩形，自动跟随居中布局。城市菜单 popover 已有锚点（iPad 安全），时间选择器是 sheet（iPad 不会崩）。
- 上海启动页：web/shanghai/splash.b64（用户发的上海 上海/配线查询图，1170x2532，340,692 字符），已接线为 SH_SPLASH，切换到上海时显示；切换城市时不再闪启动页（见城市记忆）。
- 上海地铁加入（三城切换）：413 个运营站 / 22 条线 / 505 条边 / 91 个换乘站（web/shanghai/stations.json、routes.json；数据来源见 shanghai/NOTES.md）。地图是用户发的 JPG（1206x1044，包成 SVG 用 svg-pan-zoom 缩放，放大后会发虚，和沈阳一样）；Logo 从图左上角裁剪（120x120，红字白底），已做圆形遮罩（透明角，4 倍超采样平滑边缘；红字 5886 像素一个不少，全部保留），城市 pill 里不再是白方块（沈阳 Logo 父级已同样处理）；启动页是用户发的上海图。城市菜单（原生 UIMenu + 弹窗）现在是北京 / 沈阳 / 上海三项；切换城市走同一套 switchCity（清换乘页、写 localStorage、同步原生）。注意：2 号线西端终点蟠祥路·国家会计学院在这张图上没画出来，坐标是 2 号线轴线上的虚拟定位点（165,447），能搜能规划，换新版图时要重定位。
- 上海票价：2005 年标准仍有效（0–6 公里 ¥3、6–16 ¥4、16–26 ¥5、26 公里以上每 10 公里加 ¥1；实际最高 ¥15，全网最长西岑↔滴水湖，票价封顶 ¥15）。距离不用单一换算系数——这张 JPG 图不是等比例的，而且变形不是径向的：市中心约 38 像素/公里，郊区尾段只有 7–19 像素/公里，还分方向（16 号线东南尾 7.1、1 号线北尾约 9、2 号线东尾约 8.5）。试过四种模型都不行：按线系数（市中心短途多算 ¥1、最长 ¥17 超过已知最高）、径向模型（平均误差 23.8%）、二维多项式（浦江线 +88%）、按站估（最长只有 ¥11）。最后用双区模型：每段路按中点位置算——离人民广场（652,421）260 像素以内用 38 像素/公里，以外用该线的郊区系数（从真实长度减去市中心部分反推：1 号线 8.6、2 号线 11.9、3 号线 8.9、5 号线 19.2、6 号线 16.6、7 号线 12.3、8 号线 13.2、9 号线 10.2、10 号线 18.7、11 号线 13.6、12 号线 14.5、13 号线 17.5、14 号线 8.2、15 号线 15.2、16 号线 7.1、17 号线 10.3、18 号线 14.3、浦江线 26.5；4 号线全在市中心区内，没有郊区系数；支线用主线系数）。真实长度：1 号线 36.4、2 号线 65.5、3 号线 40.3、4 号线 33.7、5 号线 32.7、6 号线 32.3、7 号线 44.2、8 号线 37.4、9 号线 65.6、10 号线 44.9、11 号线 82.4、12 号线 40.4、13 号线 38.8、14 号线 38.5、15 号线 42.5、16 号线 59.0、17 号线 41.6、18 号线 44.6、浦江线 6.7 公里。16 条抽查路线（按最短距离路线）9 条票价正确：世纪大道→龙阳路 ¥3、人民广场→陆家嘴 ¥3、上海火车站→上海南站 ¥4、虹桥火车站→龙阳路 ¥5、西岑→滴水湖 ¥15、沈杜公路→汇臻路 ¥4、嘉定北→曹杨路 ¥6、滴水湖→龙阳路 ¥9、莘庄→上海南站 ¥4 都对；已知偏差：东尾（浦东1号2号航站楼→龙阳路 ¥5，实际 ¥7；浦东1号2号航站楼→人民广场 ¥6，实际 ¥8；虹桥火车站→浦东1号2号航站楼 ¥8，实际 ¥9）、西尾（上海松江站→虹桥火车站 ¥8，实际 ¥5；花桥→国家会展中心 ¥8，实际 ¥6）、惠南→龙阳路 ¥7（实际 ¥8）、富锦路→上海火车站 ¥5（实际 ¥4）——图本身的变形不规则，任何光滑模型都修不掉，要完全准得用真实站间里程表。北京的 44 换算不变，沈阳仍按站数估（1.4 公里/站）。
- 上海主颜色：用户还没定，暂用上海地铁品牌红 #E60012（胶囊、底栏选中、搜索按钮、排序标签等），深红 #A8000C 用于文字；北京保持蓝，沈阳保持金。用户如果想换颜色直接说。
- 环线距离修正（北京、上海通用）：4 号线（上海）和 2/10 号线（北京）跨过闭合边的那一段，之前是按整圈算的（比如宜山路→上海体育馆 1 站会算成 33 公里）。现在按最短的那条弧算，跨闭合边的段按实际 1–2 公里计，票价和公里数都对了。
- 版本与文件名：版本号 1.0.2 → 1.0.3，构建号 36 → 37；安装包文件名改为 Convenient-transportation-1.0.3-unsigned.ipa（build.sh 已改；GitHub workflow 的 artifact 名由父级在网页上改）。App 显示名仍是 Subway motion。
- 城市记忆 + 切换不再闪启动页：switchCity 不再调 flashSplash(500)，改为把城市写进 localStorage（'metro-city'，try/catch 保护）；mounted 启动时读出来切到上次的城市再显示该城市的启动页（700ms 闪屏还在）；网页经 cityChanged 通道同步原生，原生用 UserDefaults（'metro-city'）存一份，启动时先读它定胶囊/底栏颜色。51 个 Node 测试通过（/tmp/b37e-test.js，含上海 22 项 + 北京/沈阳回归 + 城市记忆）。
- 换乘输入区改原生液态玻璃：出发/到达输入框 + 换乘按钮 + 搜索按钮改成原生控件（UIVisualEffectView + UIGlassEffect，iOS 26+；以下用磨砂），盖在网页对应位置上，颜色跟城市走（北京蓝 / 沈阳金 / 上海红，tint 用 accentColor）；建议下拉框仍是网页，显示在原生卡片正下方。
- 排序标签重影根治：网页的 .tr-tabs 在原生壳里永不渲染（原生分段控件是唯一的标签行），用一个看不见的 .tr-tabs-slot 占位锚点 + 滚动监听报位置，原生按锚点摆放；布局稳定后再报一次。
- 时刻表 tab（第 5 个 tab，日历时钟图标）：数据收集中，上海/沈阳的首末班车已写入 web/timetable/（sh.json、sy.json），北京的还在找（bjsubway.com 打不开）；UI 还没接，数据齐了再做。

## Build 36 (v1.0.2)

- **排序标签重影修复**：33 版的原生分段控件和网页标签同时出现、上下重叠。原因：网页标签行的隐藏不可靠（nativeApp 的检测可能在原生消息通道注入前就跑完了）+ 原生控件的位置是在布局还没稳定时量的。修法：nativeApp 在 mounted 里再检测一次；网页标签行改成 `visibility: hidden !important`；位置上报改成 requestAnimationFrame + 300ms 后再报一次，等布局稳定了再放。
- **切换城市清空换乘页**：切换城市只清了出发/到达站，没清多路线列表、线路选择、设定时间和排序标签，所以旧城市的路线还留在下面。现在 switchCity 把 routeList、fromLine、toLine、departTime、routeTab 全清掉，切过去就是空白界面。

## Build 35 (v1.0.2)

- **一卡通 / 盛京通跳转**：换乘页搜索按钮下面多了一行「打开一卡通」（北京）/「打开盛京通」（沈阳），点一下跳到对应 App 的 App Store 页面（装了的话点「打开」就能进 App 去充值、开乘车码）。北京一卡通 App Store id 1071038870，盛京通 1441271928，都是用苹果 iTunes Search API 查到的。这两个 App 没有公开确认过的 URL Scheme，所以不用猜的 scheme，直接走 App Store 页面。
- 本版同时包含 34 版的出发时间选择（右上角「现在出发」点开是苹果原生轮盘时间选择器），因为 34 版的推送被拒了没发出去。

## Build 34 (v1.0.2)

- **出发时间选择**：换乘页右上角的「现在出发」可以点了。点开是苹果原生的轮盘时间选择器（UIDatePicker，wheels 样式，SDK 26.5），可以设定一个出发时间；选完所有路线的出发/到达时间都按这个时间算（每条路的耗时不变，只是出发时刻变了）。想回到现在出发，点选择器里的「现在出发」就行，标签变回「现在出发」。
- 网页端：departTime（null = 现在出发，否则 'HH:MM'），showTimePicker 发 timePicker 消息给原生，setDepartTime 收到时间后重新搜索；findRoutes 用 departBase()（今天的设定时间或现在）算出发/到达。

## Build 33 (v1.0.2)

- **排序标签改名**：早到达 → 耗时最短（仍按分钟排），少换乘 → 路径最短（改按站数排，即最短路径，再按换乘数），省票价 → 节省票价（仍按票价排）。路线卡片上的徽标同步：少 → 短（站数最少）。
- **排序标签改为 Apple 官方液态玻璃**：推荐 / 耗时最短 / 路径最短 / 节省票价 四个标签现在是原生 UISegmentedControl（iOS 26+ 自带液态玻璃外观），覆盖在网页标签行的位置上。网页在原生壳里把自己的标签行隐藏（visibility:hidden，占位保留），并通过 tabsFrame 消息把标签行的位置和当前选中项报给原生；原生按这个位置摆放分段控件，点选后调用 window.metroApp.setRouteTab 同步回网页。离开换乘页或没有路线时控件自动隐藏。
- **红庙说明**：红庙是 6 号线正常运营站（2012 年开通，在金台路和十里堡之间），同时也是 14 号线暂缓开通的预留站（随 22 号线开通）。App 里显示 6 号线是对的，因为 6 号线那站现在就能坐；14 号线那部分还没开。

## Build 32 (v1.0.2)

- **停用暂缓开通的车站**：陶然桥（14号线，2017年12月30日起暂缓）、八角游乐园（1号线，配合1号线支线封闭改造至2027年5月2日，列车通过不停车）、模式口（11号线暂缓）、福寿岭（1号线，1969年建成，2021年改造，2023年底完工后消防验收未通过，开通时间未定）已从线路和搜索里移除；广渠门外从17号线移除（2025年12月27日中段开通时暂缓，列车通过不停车），但保留在7号线（7号线广渠门外正常运营）。红庙（14号线，随22号线开通）和高家园（14号线未开工）之前已处理，仍保留在6号线/12号线。老官里不在当前配线图数据里，无需处理。S1线顺带修正：模式口不是S1站，改回金安桥（S1真实换乘站）。北京站数 422 → 418，边 512 → 507。
- **缩放/平移顺滑**：捏合缩放和拖动之前是每次手势事件都立即重绘整张 4.5MB 矢量图，一秒几十次重绘，主线程跟不上就一卡一卡。改成每帧最多只应用一次变换（用 requestAnimationFrame 合并，缩放取最新目标，平移增量累加），并给缩放视口加了 will-change: transform 走 GPU 合成。双击放大不变。

## Build 31 (v1.0.2)
- Line 14 data fix: 金台路 added (6/14 interchange), 红庙 removed from Line 14
  (reserved station, not operating; stays on Line 6), 潘家园西 removed from Line 14
  (it is a Line 17 station). Line 14 now 34 stations; routes 27 lines / 512 edges.
- Fare recalibration: Beijing SVG distance scale 55 -> 44 units/km (calibrated on
  real line lengths; validated on 6 real routes). 苹果园->国贸 ¥6, 苹果园->环球度假区
  ¥8, 石佛营->田村 ¥6, 西直门->宋家庄 ¥5, 天安门东->王府井 ¥3, 管庄->2号航站楼 ¥30,
  东四十条->3号航站楼 ¥28, 草桥->大兴机场 ¥35.
- Multi-route results: after searching, up to 6 candidate routes with sort tabs
  推荐 / 早到达 / 少换乘 / 省票价; each card shows depart->arrive, minutes, fare,
  transfers, km, segment chain with line badges, and 早/少/省 badges. Tap a card
  to see its detail. All options depart "now" (no real timetables).
- Line picker: 出发/到达 suggestions now show one row per line (e.g. 东四十条 as
  2号线 and as 3号线) with the official line badge (color + name). Picking a row
  fixes the start/end line; findRoute respects fromLine/toLine. Typing a station
  or picking from the search tab stays "auto".
- Shenyang gold theme (complete): all web blue accents -> gold in Shenyang mode
  (transfer header, swap button, sort tabs, search button, more/settings rows,
  tab labels); native tab bar selected tint and back button now switch with the
  city (blue Beijing / gold Shenyang). Beijing unchanged.
- Shenyang coordinates: all 144 stations now have (x, y) in JPG pixel space
  (1206x1320) via OCR + manual fixes, so search tap-to-locate pans the map.
- Landscape Dynamic Island safe area: #stationPanel and #transferPanel now use
  env(safe-area-inset-left/right) horizontal padding, so content clears the
  Dynamic Island in landscape. Portrait unchanged (env is 0).
- Shenyang SVG (NOT switched): the Wikimedia SVG the user sent is the 2025
  version — Line 3 has only 14 circles (missing the 13-station east extension
  to 方家栏）. Kept the JPG map (complete, has coordinates). File saved as
  web/shenyang/map-svg-source.svg for reference.
