// SettingsData.swift — GENERATED, do not hand-edit.
// Sources (this copy, verbatim): web/template.html rankingList / upcomingLines /
// releaseNotes / soonCityList / cityList; web/briefing.json, web/trains.json,
// web/structure/index.json are embedded as JSON text in SettingsSeedData.swift.
import Foundation

enum SettingsData {
    struct City: Hashable { let key: String; let nameHans: String; let nameHant: String; let nameEn: String; let logoImageName: String }
    static let cities: [City] = [
        City(key: "bj", nameHans: "北京", nameHant: "北京", nameEn: "Beijing", logoImageName: "BeijingLogo"),
        City(key: "sy", nameHans: "沈阳", nameHant: "瀋陽", nameEn: "Shenyang", logoImageName: "ShenyangLogo"),
        City(key: "sh", nameHans: "上海", nameHant: "上海", nameEn: "Shanghai", logoImageName: "ShanghaiLogo"),
        City(key: "hb", nameHans: "哈尔滨", nameHant: "哈爾濱", nameEn: "Harbin", logoImageName: "HarbinLogo"),
        City(key: "dl", nameHans: "大连", nameHant: "大連", nameEn: "Dalian", logoImageName: "DalianLogo"),
        City(key: "jh", nameHans: "金华", nameHant: "金華", nameEn: "Jinhua", logoImageName: "JinhuaLogo"),
        City(key: "cz", nameHans: "常州", nameHant: "常州", nameEn: "Changzhou", logoImageName: "ChangzhouLogo"),
        City(key: "cq", nameHans: "重庆", nameHant: "重慶", nameEn: "Chongqing", logoImageName: "ChongqingLogo"),
        City(key: "cc", nameHans: "长春", nameHant: "長春", nameEn: "Changchun", logoImageName: "ChangchunLogo"),
        City(key: "sz", nameHans: "深圳", nameHant: "深圳", nameEn: "Shenzhen", logoImageName: "ShenzhenLogo"),
        City(key: "cd", nameHans: "成都", nameHant: "成都", nameEn: "Chengdu", logoImageName: "ChengduLogo"),
        City(key: "qd", nameHans: "青岛", nameHant: "青島", nameEn: "Qingdao", logoImageName: "QingdaoLogo"),
        City(key: "sjz", nameHans: "石家庄", nameHant: "石家莊", nameEn: "Shijiazhuang", logoImageName: "ShijiazhuangLogo"),
        City(key: "tj", nameHans: "天津", nameHant: "天津", nameEn: "Tianjin", logoImageName: "TianjinLogo"),
        City(key: "wx", nameHans: "无锡", nameHant: "無錫", nameEn: "Wuxi", logoImageName: "WuxiLogo"),
    ]
    static func cityName(_ key: String, lang: SettingsLanguage) -> String {
        guard let c = cities.first(where: { $0.key == key }) else { return key }
        switch lang { case .zhHans: return c.nameHans; case .zhHant: return c.nameHant; case .english: return c.nameEn; case .system: return cityName(key, lang: SettingsLanguage.systemLanguage()) }
    }

    /// More-cities directory: CAMET 2026-Q3, 44 entries incl. the Xiong'an placeholder.
    /// logoStem is the web/upcoming-logos/*.b64 stem when a verified logo exists on disk, else nil (grey M fallback, same as web).
    static let soonCities: [(name: String, logoStem: String?)] = [
        ("广州", "guangzhou"),
        ("武汉", "wuhan"),
        ("南京", "nanjing"),
        ("西安", "xian"),
        ("苏州", "suzhou"),
        ("郑州", "zhengzhou"),
        ("昆明", "kunming"),
        ("杭州", "hangzhou"),
        ("佛山", "foshan"),
        ("长沙", "changsha"),
        ("宁波", "ningbo"),
        ("南昌", "nanchang"),
        ("兰州", "lanzhou"),
        ("淮安", nil),
        ("福州", "fuzhou"),
        ("东莞", "dongguan"),
        ("南宁", "nanning"),
        ("合肥", "hefei"),
        ("乌鲁木齐", "wulumuqi"),
        ("贵阳", "guiyang"),
        ("厦门", "xiamen"),
        ("温州", "wenzhou"),
        ("济南", "jinan"),
        ("呼和浩特", "huhehaote"),
        ("徐州", "xuzhou"),
        ("天水", nil),
        ("三亚", nil),
        ("太原", "taiyuan"),
        ("株洲", nil),
        ("宜宾", nil),
        ("洛阳", "luoyang"),
        ("嘉兴", nil),
        ("绍兴", "shaoxing"),
        ("文山州", nil),
        ("芜湖", nil),
        ("南平", nil),
        ("南通", "nantong"),
        ("台州", nil),
        ("黄石", nil),
        ("盐城", nil),
        ("红河州", nil),
        ("滁州", nil),
        ("许昌", nil),
        ("雄安", "xiongan"),
    ]

    struct UpcomingLine { let key: String; let cityKey: String; let badge: String; let colorHex: String; let dateKey: String; let km: String; let stations: String; let interchanges: String; let approx: Bool }
    static let upcomingCityKey: [String: String] = ["bj22": "bj", "bjjx": "bj", "sh22": "sh", "gz12": "gz", "gz13": "gz", "sy6": "sy", "sy9": "sy", "sz13": "sz", "cq27": "cq", "cdS5": "cd", "tjZ2": "tj"]
    static let upcomingLines: [UpcomingLine] = [
        UpcomingLine(key: "bj22", cityKey: "bj", badge: "22", colorHex: "F4C1CA", dateKey: "2026", km: "", stations: "20", interchanges: "", approx: false),
        UpcomingLine(key: "bjjx", cityKey: "bj", badge: "R1", colorHex: "8E8E93", dateKey: "2026y", km: "86.21", stations: "8", interchanges: "1", approx: false),
        UpcomingLine(key: "sh22", cityKey: "sh", badge: "22", colorHex: "401AA6", dateKey: "2026", km: "42.9", stations: "8", interchanges: "", approx: true),
        UpcomingLine(key: "gz12", cityKey: "gz", badge: "12", colorHex: "59621D", dateKey: "2026", km: "8.8", stations: "7", interchanges: "", approx: false),
        UpcomingLine(key: "gz13", cityKey: "gz", badge: "13", colorHex: "888600", dateKey: "2026", km: "25.3", stations: "19", interchanges: "", approx: false),
        UpcomingLine(key: "sy6", cityKey: "sy", badge: "6", colorHex: "FEDC00", dateKey: "2027", km: "", stations: "", interchanges: "", approx: false),
        UpcomingLine(key: "sy9", cityKey: "sy", badge: "9", colorHex: "0095D2", dateKey: "2027", km: "", stations: "", interchanges: "", approx: false),
        UpcomingLine(key: "sz13", cityKey: "sz", badge: "13", colorHex: "DE7C00", dateKey: "2027", km: "4.1", stations: "3", interchanges: "", approx: true),
        UpcomingLine(key: "cq27", cityKey: "cq", badge: "27", colorHex: "0057B8", dateKey: "2027", km: "56", stations: "15", interchanges: "", approx: true),
        UpcomingLine(key: "cdS5", cityKey: "cd", badge: "S5", colorHex: "A7C6ED", dateKey: "2027", km: "", stations: "", interchanges: "", approx: false),
        UpcomingLine(key: "tjZ2", cityKey: "tj", badge: "Z2", colorHex: "006BA6", dateKey: "2027", km: "", stations: "", interchanges: "", approx: false),
    ]
    static func upcoming(for cityKey: String) -> [UpcomingLine] { upcomingLines.filter { $0.cityKey == cityKey } }

    struct RankingRow { let rank: Int; let name: String; let km: String; let cityKey: String; let colorHex: String; let source: String; let date: String; let note: String }
    /// 42 rows; rank 40 is absent in the web source too (cities without a verified logo were dropped from the display list).
    static let ranking: [RankingRow] = [
        RankingRow(rank: 1, name: "北京", km: "909.0", cityKey: "bj", colorHex: "005ab4", source: "北京市交通委", date: "2025 年底", note: ""),
        RankingRow(rank: 2, name: "上海", km: "906.0", cityKey: "sh", colorHex: "e60012", source: "上海市交通委", date: "2025-12-27", note: "纯地铁 816.0 公里"),
        RankingRow(rank: 3, name: "广州", km: "779.9", cityKey: "", colorHex: "", source: "广州地铁集团官网", date: "2025-06-29", note: ""),
        RankingRow(rank: 4, name: "成都", km: "758.2", cityKey: "cd", colorHex: "0f0f96", source: "成都轨道交通集团评级报告", date: "2026-03-31", note: ""),
        RankingRow(rank: 5, name: "南京", km: "658.1", cityKey: "", colorHex: "", source: "英文维基", date: "2026-09-29", note: ""),
        RankingRow(rank: 6, name: "深圳", km: "653.7", cityKey: "sz", colorHex: "00a051", source: "深铁集团半年报（新浪财经）", date: "2026-06", note: ""),
        RankingRow(rank: 7, name: "重庆", km: "625.0", cityKey: "cq", colorHex: "0a814b", source: "中文维基", date: "2026-11-12", note: ""),
        RankingRow(rank: 8, name: "武汉", km: "581.0", cityKey: "", colorHex: "", source: "新华社", date: "2026-10-29", note: ""),
        RankingRow(rank: 9, name: "杭州", km: "562.0", cityKey: "", colorHex: "", source: "英文维基", date: "2022-09-22 起", note: ""),
        RankingRow(rank: 10, name: "郑州", km: "450.0", cityKey: "", colorHex: "", source: "21 世纪经济报道", date: "2024-12-29", note: ""),
        RankingRow(rank: 11, name: "西安", km: "423.2", cityKey: "", colorHex: "", source: "英文维基", date: "2026-06-30", note: ""),
        RankingRow(rank: 12, name: "天津", km: "391.0", cityKey: "tj", colorHex: "cb333b", source: "天津政务网", date: "2026-01-18", note: ""),
        RankingRow(rank: 13, name: "青岛", km: "365.0", cityKey: "qd", colorHex: "317c5b", source: "青岛市政府网", date: "2026-09-22", note: ""),
        RankingRow(rank: 14, name: "宁波", km: "约 360", cityKey: "", colorHex: "", source: "宁波市政府（英文版）", date: "2026-09-22", note: ""),
        RankingRow(rank: 15, name: "苏州", km: "约 350", cityKey: "", colorHex: "", source: "江苏省交通运输厅", date: "2024-12-01", note: ""),
        RankingRow(rank: 16, name: "合肥", km: "306.8", cityKey: "", colorHex: "", source: "英文维基", date: "2026-11-19", note: ""),
        RankingRow(rank: 17, name: "济南", km: "248.5", cityKey: "", colorHex: "", source: "大众新闻", date: "2025-12-30", note: ""),
        RankingRow(rank: 18, name: "长沙", km: "247.9", cityKey: "", colorHex: "", source: "长沙市交通运输局", date: "2026-09-04", note: ""),
        RankingRow(rank: 19, name: "大连", km: "237.7", cityKey: "dl", colorHex: "0d579a", source: "英文维基", date: "2023-03-17 起", note: ""),
        RankingRow(rank: 20, name: "沈阳", km: "218.0", cityKey: "sy", colorHex: "d4b686", source: "沈阳地铁集团官网", date: "2026-06-30", note: ""),
        RankingRow(rank: 21, name: "福州", km: "210.3", cityKey: "", colorHex: "", source: "中新网", date: "2025-12-10", note: ""),
        RankingRow(rank: 22, name: "长春", km: "194.1", cityKey: "cc", colorHex: "e50011", source: "新浪财经", date: "2026-09-28", note: ""),
        RankingRow(rank: 23, name: "昆明", km: "165.9", cityKey: "", colorHex: "", source: "云南日报网", date: "2025-04-11", note: ""),
        RankingRow(rank: 24, name: "南昌", km: "160.2", cityKey: "", colorHex: "", source: "江西日报", date: "2025-06-28", note: ""),
        RankingRow(rank: 25, name: "佛山", km: "153.1", cityKey: "", colorHex: "", source: "佛山新闻传媒中心", date: "2026-11-03", note: ""),
        RankingRow(rank: 26, name: "贵阳", km: "149.1", cityKey: "", colorHex: "", source: "中文维基", date: "2024-12-28", note: ""),
        RankingRow(rank: 27, name: "无锡", km: "142.0", cityKey: "wx", colorHex: "ee2737", source: "中共江苏省委新闻网", date: "2026-09-08", note: ""),
        RankingRow(rank: 28, name: "南宁", km: "132.6", cityKey: "", colorHex: "", source: "南宁市交通运输局", date: "2025-09-26", note: ""),
        RankingRow(rank: 29, name: "温州", km: "116.8", cityKey: "", colorHex: "", source: "城轨协会 2026 上半年统计", date: "2026-06-30", note: ""),
        RankingRow(rank: 30, name: "厦门", km: "98.4", cityKey: "", colorHex: "", source: "英文维基", date: "2025-12-31", note: ""),
        RankingRow(rank: 31, name: "东莞", km: "95.3", cityKey: "", colorHex: "", source: "中文维基", date: "2025-11-28", note: ""),
        RankingRow(rank: 32, name: "徐州", km: "95.1", cityKey: "", colorHex: "", source: "城轨协会 2026 上半年统计", date: "2026-06-30", note: ""),
        RankingRow(rank: 33, name: "哈尔滨", km: "91.6", cityKey: "hb", colorHex: "c00030", source: "黑龙江省人民政府网", date: "2024-11-26", note: ""),
        RankingRow(rank: 34, name: "石家庄", km: "78.2", cityKey: "sjz", colorHex: "e53e30", source: "新华社", date: "2025 年上半年", note: ""),
        RankingRow(rank: 35, name: "绍兴", km: "64.5", cityKey: "", colorHex: "", source: "浙江省交通运输厅", date: "2025-12-30", note: ""),
        RankingRow(rank: 36, name: "南通", km: "60.0", cityKey: "", colorHex: "", source: "中文维基", date: "2023-12-27", note: ""),
        RankingRow(rank: 37, name: "常州", km: "54.0", cityKey: "cz", colorHex: "cd5c5c", source: "常州市政府", date: "2021-06-28", note: ""),
        RankingRow(rank: 38, name: "太原", km: "52.4", cityKey: "", colorHex: "", source: "中文维基", date: "2025-02-22", note: ""),
        RankingRow(rank: 39, name: "呼和浩特", km: "49.0", cityKey: "", colorHex: "", source: "中文维基", date: "2020-10-01 起", note: ""),
        RankingRow(rank: 41, name: "乌鲁木齐", km: "45.5", cityKey: "", colorHex: "", source: "中文维基", date: "2026-11-15", note: ""),
        RankingRow(rank: 42, name: "洛阳", km: "43.6", cityKey: "", colorHex: "", source: "中文维基", date: "2021-12-26", note: ""),
        RankingRow(rank: 43, name: "兰州", km: "35.0", cityKey: "", colorHex: "", source: "兰州市轨道交通有限公司官网", date: "2026-06", note: ""),
    ]

    struct ReleaseNote { let version: String; let date: String; let lines: [[String]] }
    /// Formal releases ONLY (this copy: A26109 + A26108 + A26107). No test entries — see the formal rule.
    static let releaseNotes: [ReleaseNote] = [
        ReleaseNote(version: "1.0.0 (A26109)", date: "2026-11-24", lines: [
            ["设置页改为原生 Apple UI：首页与 13 个子页全部用 SwiftUI 重写，切换城市、语言与外观即时生效", "設定頁改為原生 Apple UI：首頁與 13 個子頁全部用 SwiftUI 重寫，切換城市、語言與外觀即時生效", "Settings is now native Apple UI: the home page and all 13 subpages are rewritten in SwiftUI, and switching city, language or appearance applies immediately"],
        ]),
        ReleaseNote(version: "1.0.0 (A26108)", date: "2026-11-23", lines: [
            ["功能介绍只保留正式版内容：混入的测试版更新记录已全部移除，正式版里不再出现测试版条目", "功能介紹只保留正式版內容：混入的測試版更新記錄已全部移除，正式版裡不再出現測試版條目", "Release notes now list formal releases only: all test-build entries have been removed from the formal version"],
            ["修复设置页「功能介绍」右侧版本号误显示为测试版 1.1.0 的问题，现显示 1.0.0", "修復設定頁「功能介紹」右側版本號誤顯示為測試版 1.1.0 的問題，現顯示 1.0.0", "Fixed the Features row in Settings showing the test version number 1.1.0; it now shows 1.0.0"],
        ]),
        ReleaseNote(version: "1.0.0 (A26107)", date: "2026-11-23", lines: [
            ["正式版发布：测试阶段的全部功能与修复转入正式版", "正式版發布：測試階段的全部功能與修復轉入正式版", "Formal release: the test phase’s full feature set and fixes graduate to the release build"],
            ["修复北京 1 号线公主坟站缺失：公主坟恢复为 1 号线 / 10 号线换乘站，站序、距离与搜索徽章一并修正（1 号线在该站的首末班时刻暂无可核实来源，页面显示暂无数据）", "修復北京 1 號線公主墳站缺失：公主墳恢復為 1 號線 / 10 號線換乘站，站序、距離與搜尋徽章一併修正（1 號線在該站的首末班時刻暫無可核實來源，頁面顯示暫無數據）", "Beijing Line 1’s Gongzhufen station is restored: it is once again a Line 1 / Line 10 interchange, with station order, distances and search badges corrected (no verifiable source exists yet for its Line 1 first/last trains, so that row shows no data)"],
            ["换乘站可选线锁定：联想行里点某条线的徽章即按该线选站，徽章打勾，输入框同步显示；点已打勾的徽章取消锁定，规划按锁定的出发线 × 到达线计算", "換乘站可選線鎖定：聯想行裡點某條線的徽章即按該線選站，徽章打勾，輸入框同步顯示；點已打勾的徽章取消鎖定，規劃按鎖定的出發線 × 到達線計算", "Pick a line at an interchange: tap a line badge on the merged suggestion row to select the station on that line — the badge gets a check and the field mirrors it; tap the checked badge again to unlock. Planning then runs on the locked origin-line x destination-line pairing"],
            ["路线详情时间轴的车站圆点改用线路颜色：起点、终点取所在线路色，换乘站圆环上半环为到达线颜色、下半环为出发线颜色，与上下脊线接续", "路線詳情時間軸的車站圓點改用線路顏色：起點、終點取所在線路色，換乘站圓環上半環為到達線顏色、下半環為出發線顏色，與上下脊線接續", "Route-detail timeline dots now use line colours: origin and destination take their line’s colour, and a transfer station’s ring is two half rings — the arriving line’s colour on top, the departing line’s colour below — joining the rails above and below"],
            ["修复换乘页联想列表被压成一条缝、页面拖动时整屏涂抹重影的问题：联想列表完整显示，页面只有记录与路线区域可滚动；底部栏略微抬高，与 Home 指示条留出间隙；修复 Siri 子页开关滑出屏幕的问题", "修復換乘頁聯想列表被壓成一條縫、頁面拖動時整屏塗抹重影的問題：聯想列表完整顯示，頁面只有記錄與路線區域可滾動；底部欄略微抬高，與 Home 指示條留出間隙；修復 Siri 子頁開關滑出螢幕的問題", "Fixed the transfer page’s suggestion list being crushed to a sliver and the whole page smearing when dragged: suggestions now show in full and only the history/route region scrolls. The bottom bar floats slightly higher, clear of the Home indicator, and the Siri page’s switch no longer slides off-screen"],
            ["「快速换乘」说明改用系统原生液态玻璃弹框呈现，与系统界面一致", "「快速換乘」說明改用系統原生液態玻璃彈框呈現，與系統介面一致", "The Fast Transfer note now appears in a native system Liquid Glass alert, matching the rest of iOS"],
        ]),
    ]
    /// The version shown on the Settings home 功能介绍 row: the formal short version, never a test version.
    static let formalShortVersion = "1.0.0"
    static let formalBuild = "A26109"
}
