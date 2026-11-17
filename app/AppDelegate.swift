import UIKit
import WebKit
import CoreLocation
import ActivityKit

// 北京市轨道交通线路配置图 (SierraQin/metro, CC0 1.0)
// Shell: a full-screen WKWebView loading the bundled offline page,
// plus a native UITabBar at the bottom and two native Liquid Glass
// pills at the top (city picker + station search). The web page's own
// tab bar and top pills are hidden; the native controls drive the web
// UI via JavaScript, and the web page reports its current tab back so
// the two stay in sync. Built with iOS SDK 26.5 (Xcode 26.6).
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    // No window here anymore (build 41): the window is created by
    // SceneDelegate below. The old AppDelegate-owned window is what
    // crashed on launch with SDK 27.x — iOS 27 expects the Scene
    // lifecycle, so the window must be created in
    // scene(_:willConnectTo:options:).
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    // Explicitly hand the system the scene configuration (build 42):
    // relying on the Info.plist lookup alone left the app on a black
    // screen, because the Swift class name the runtime registers is
    // module-qualified and the plist's bare "SceneDelegate" did not
    // resolve to it.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

// Scene lifecycle (build 41): owns the UIWindow. iOS 13+ (and
// required in practice on iOS 27 / SDK 27) connects the scene here;
// the AppDelegate no longer creates or manages the window.
// @objc(SceneDelegate) (build 42): pins the Objective-C runtime name
// to exactly "SceneDelegate" so the Info.plist lookup finds it even
// though Swift registers the class module-qualified.
@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let win = UIWindow(windowScene: windowScene)
        win.rootViewController = MapViewController()
        win.makeKeyAndVisible()
        window = win
    }
}

class MapViewController: UIViewController, WKNavigationDelegate, UITabBarDelegate, WKScriptMessageHandler, UITextFieldDelegate, CLLocationManagerDelegate {
    var webView: WKWebView!
    var backButton: UIButton!
    var tabBar: UITabBar!
    var cityPill: UIButton!
    var searchPill: UIButton!
    // Native Liquid Glass route-sort tabs (build 33): a UISegmentedControl
    // (Liquid Glass on iOS 26+) overlaid on the web panel's tab row.
    var sortTabs: UISegmentedControl!
    let sortTabKeys = ["rec", "early", "fewest", "cheap"]
    // Native Apple UI Liquid Glass dark-mode picker (build 44, 3 glass
    // buttons since build 52): 3 separate glass buttons
    // (跟随系统/浅色/深色) overlaid on the settings panel's
    // .more-theme-seg row, same pattern as sortTabs.
    var themeButtons: [UIButton] = []
    let themeSegKeys = ["system", "light", "dark"]
    // Web view's origin in the main view: the web view is full-screen
    // on every device (build 63 removed the iPad top strip), so the
    // origin is (0, 0) and web getBoundingClientRect coordinates map
    // 1:1 to main-view space. Kept as a property so the frame
    // placement code (placeTransfer / placeSortTabs /
    // placeThemeButtons) does not need to know the layout.
    var webOffset: CGPoint { webView.frame.origin }
    // Native Liquid Glass transfer input area (build 37): a glass card
    // holding the two station text fields + swap button, and a glass
    // 搜索 button, overlaid on the web panel's .tr-fields / .tr-search
    // rows (frame-positioned from the web, like sortTabs). The web
    // suggestion dropdown stays web and appears below the card.
    var transferCard: UIView!
    var transferEffectView: UIVisualEffectView!
    var transferSwapButton: UIButton!
    var transferSearchButton: UIButton!
    var fromField: UITextField!
    var toField: UITextField!
    // Label buttons beside the native transfer fields (出发/到达), stored
    // so applyLanguage() can retitle them on a language change.
    var fromLabelBtn: UIButton?
    var toLabelBtn: UIButton?
    var fromBadge: UIButton!
    var toBadge: UIButton!
    var fromClear: UIButton!
    var toClear: UIButton!
    // Line info currently shown in each field's badge, as
    // {name, color, text} (hex strings from the web); nil = no badge.
    var fromLineInfo: [String: Any]?
    var toLineInfo: [String: Any]?
    // Web tab keys, in the same order as the native tab bar items.
    let tabKeys = ["transfer", "map", "stations", "timetable", "more"]
    // Beijing Subway blue (Beijing theme, unchanged); Shenyang gold,
    // sampled from the user's gold image: #D4B686 (champagne gold);
    // Shanghai brand red #E60012 (user has not chosen a Shanghai color
    // yet - red is Shanghai Metro's brand color, matching the red logo).
    let subwayBlue = UIColor(red: 0, green: 51.0 / 255.0, blue: 128.0 / 255.0, alpha: 1)
    let shenyangGold = UIColor(red: 212.0 / 255.0, green: 182.0 / 255.0, blue: 134.0 / 255.0, alpha: 1)
    let shenyangGoldDark = UIColor(red: 138.0 / 255.0, green: 109.0 / 255.0, blue: 43.0 / 255.0, alpha: 1)
    // Shenyang search button red (user asked for red, not gold, on the
    // 搜索 button; logo red 199,33,45). Only the search button uses it.
    let shenyangRed = UIColor(red: 199.0 / 255.0, green: 33.0 / 255.0, blue: 45.0 / 255.0, alpha: 1)
    let shanghaiRed = UIColor(red: 230.0 / 255.0, green: 0, blue: 18.0 / 255.0, alpha: 1)
    let shanghaiRedDark = UIColor(red: 168.0 / 255.0, green: 0, blue: 12.0 / 255.0, alpha: 1)
    // Shanghai search button gold (user asked for gold on the 上海 搜索
    // button). Same champagne gold #D4B686 as the Shenyang theme gold.
    let shanghaiGold = UIColor(red: 212.0 / 255.0, green: 182.0 / 255.0, blue: 134.0 / 255.0, alpha: 1)
    // Harbin brand red #C00030 (sampled from the Harbin metro logo /
    // Line 1 on the user's 2026.08 map; user: 主题色也是红色).
    let harbinRed = UIColor(red: 192.0 / 255.0, green: 0, blue: 48.0 / 255.0, alpha: 1)
    let harbinRedDark = UIColor(red: 138.0 / 255.0, green: 0, blue: 32.0 / 255.0, alpha: 1)
    // Dalian Metro brand blue #0D579A (sampled from the official Dalian
    // Metro logo); darker #0a4273 for text/borders.
    let dalianBlue = UIColor(red: 13.0 / 255.0, green: 87.0 / 255.0, blue: 154.0 / 255.0, alpha: 1)
    let dalianBlueDark = UIColor(red: 10.0 / 255.0, green: 66.0 / 255.0, blue: 115.0 / 255.0, alpha: 1)
    // Jinhua brand dark red #D8273D (Wikipedia Template:金华轨道交通颜色,
    // code JYD; 标志色：深红色). Darker #A81E30 for selected states/text.
    let jinhuaRed = UIColor(red: 216.0 / 255.0, green: 39.0 / 255.0, blue: 61.0 / 255.0, alpha: 1)
    let jinhuaRedDark = UIColor(red: 168.0 / 255.0, green: 30.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
    // Changzhou brand red #CD5C5C (Wikipedia Template:常州地铁颜色, code 1).
    // Darker #A04848 for selected states/text.
    let changzhouRed = UIColor(red: 205.0 / 255.0, green: 92.0 / 255.0, blue: 92.0 / 255.0, alpha: 1)
    let changzhouRedDark = UIColor(red: 160.0 / 255.0, green: 72.0 / 255.0, blue: 72.0 / 255.0, alpha: 1)
    // Chongqing CRT green #0A814B (logo green; median #0F7F4C).
    // Darker #076138 for selected states/text.
    let chongqingGreen = UIColor(red: 10.0 / 255.0, green: 129.0 / 255.0, blue: 75.0 / 255.0, alpha: 1)
    let chongqingGreenDark = UIColor(red: 7.0 / 255.0, green: 97.0 / 255.0, blue: 56.0 / 255.0, alpha: 1)
    var currentCity = "bj"
    var currentTab = "map"
    // Splash gate (user 2026-11-15): the native tab bar + top pills sit
    // ABOVE the WKWebView, so they showed on top of the web splash
    // animation for 2s. Keep them hidden until the web says the splash
    // is done (or the fallback timer fires).
    var splashShowing = true
    // Native launch splash view (build 53): shows the current city's
    // splash image from launch, covering the white gap before the web
    // page loads and its own splash appears. Hidden in splashFinished().
    var splashImageView: UIImageView!
    // Location (build 63): find the nearest station. The permission
    // prompt appears only when the user taps 附近车站, never at launch.
    var locationManager: CLLocationManager?
    var locationPending = false
    // iPhone Duo sidebar (build 63): on a wide iPhone (Duo unfolded)
    // the bottom tab bar is replaced by a vertical floating glass
    // sidebar on the right edge. Same 5 tabs, same order, icon above
    // label. iPad keeps the bottom tab bar (build 63 removes the iPad
    // top strip; the bar floats at the bottom there too).
    var sideBar: UIView!
    var sideBarEffectView: UIVisualEffectView!
    var sideBarButtons: [UIButton] = []
    var sideBarActive = false
    // Web view trailing constraints (build 63): toggled between the
    // view edge (narrow / iPad) and the sidebar's leading edge (wide
    // iPhone) so web content never goes under the sidebar.
    var webViewTrailingToView: NSLayoutConstraint!
    var webViewTrailingToSideBar: NSLayoutConstraint!
    private var lastSideBarLayoutWidth: CGFloat = 0

    // ---- i18n (build 64) ----
    // Native string table: key -> [zh-Hans, zh-Hant, en]. zh-Hans is the
    // default and the fallback. Mirrors the web I18N table for native UI.
    static let LANG: [String: [String]] = [
        "tab.transfer": ["换乘", "換乘", "Transfer"],
        "tab.map": ["配线图", "配線圖", "Track Map"],
        "tab.stations": ["搜索", "搜索", "Search"],
        "tab.timetable": ["时刻表", "時刻表", "Timetable"],
        "tab.more": ["设置", "設定", "Settings"],
        "city.bj": ["北京", "北京", "Beijing"],
        "city.sy": ["沈阳", "瀋陽", "Shenyang"],
        "city.sh": ["上海", "上海", "Shanghai"],
        "city.hb": ["哈尔滨", "哈爾濱", "Harbin"],
        "city.dl": ["大连", "大連", "Dalian"],
        "city.jh": ["金华", "金華", "Jinhua"],
        "city.cz": ["常州", "常州", "Changzhou"],
        "city.cq": ["重庆", "重慶", "Chongqing"],
        "native.cancel": ["取消", "取消", "Cancel"],
        "tr.tab.rec": ["推荐", "推薦", "Recommended"],
        "tr.tab.early": ["耗时最短", "耗時最短", "Fastest"],
        "tr.tab.fewest": ["路径最短", "路徑最短", "Shortest"],
        "tr.tab.cheap": ["节省票价", "節省票價", "Cheapest"],
        "more.theme.system": ["跟随系统", "跟隨系統", "System"],
        "more.theme.light": ["浅色", "淺色", "Light"],
        "more.theme.dark": ["深色", "深色", "Dark"],
        "tr.search": ["搜索", "搜索", "Search"],
        "tr.departNow": ["现在出发", "現在出發", "Depart now"],
        "time.confirm": ["确定", "確定", "Done"],
        "time.done": ["完成", "完成", "Done"],
        "map.searchStation": ["搜车站", "搜車站", "Search Stations"],
        "native.switchCity": ["切换城市", "切換城市", "Switch City"],
        "tr.phFrom": ["选择出发站", "選擇出發站", "Choose departure station"],
        "tr.phTo": ["选择到达站", "選擇到達站", "Choose arrival station"],
        "tr.depart": ["出发", "出發", "Depart"],
        "tr.arrive": ["到达", "到達", "Arrive"],
        "loc.perm": ["需要定位权限才能查找附近车站，请在系统设置中开启。", "需要定位權限才能查找附近車站，請在系統設定中開啟。", "Location permission is needed to find nearby stations. Please enable it in Settings."],
        "loc.failed": ["无法获取定位。", "無法獲取定位。", "Couldn't get your location."],
        "loc.retry": ["定位失败，请稍后重试。", "定位失敗，請稍後再試。", "Location failed. Please try again."],
        "live.next": ["下一站", "下一站", "Next stop"],
        "live.stopsLeft": ["还剩 {n} 站", "還剩 {n} 站", "{n} stops left"],
        "live.trip": ["行程", "行程", "Trip"],
        "live.arrived": ["已到达", "已到達", "Arrived"],
    ]
    var currentLang: String = UserDefaults.standard.string(forKey: "metro-lang") ?? "zh-Hans"
    func L(_ key: String) -> String {
        let arr = Self.LANG[key] ?? [key, key, key]
        let idx: Int
        switch currentLang {
        case "zh-Hant": idx = 1
        case "en": idx = 2
        default: idx = 0
        }
        return arr.indices.contains(idx) ? arr[idx] : arr[0]
    }
    // Called by the web langChanged post. Updates native UI only; the web
    // already switched, so do NOT call setLang on the web here (no loop).
    func setLang(_ lang: String) {
        let l = (lang == "zh-Hant" || lang == "en") ? lang : "zh-Hans"
        currentLang = l
        UserDefaults.standard.set(l, forKey: "metro-lang")
        applyLanguage()
    }
    // Re-apply all native strings for the current language.
    func applyLanguage() {
        let titles = [L("tab.transfer"), L("tab.map"), L("tab.stations"), L("tab.timetable"), L("tab.more")]
        if let items = tabBar?.items {
            for (i, item) in items.enumerated() where i < titles.count { item.title = titles[i] }
        }
        updateCityPill()
        if sortTabs != nil {
            sortTabs.setTitle(L("tr.tab.rec"), forSegmentAt: 0)
            sortTabs.setTitle(L("tr.tab.early"), forSegmentAt: 1)
            sortTabs.setTitle(L("tr.tab.fewest"), forSegmentAt: 2)
            sortTabs.setTitle(L("tr.tab.cheap"), forSegmentAt: 3)
        }
        let themeTitles = [L("more.theme.system"), L("more.theme.light"), L("more.theme.dark")]
        for (i, btn) in themeButtons.enumerated() where i < themeTitles.count {
            var cfg = btn.configuration ?? themeButtonConfig()
            cfg.title = themeTitles[i]
            btn.configuration = cfg
        }
        if transferSearchButton != nil { updateTransferSearchStyle() }
        if fromField != nil { fromField.placeholder = L("tr.phFrom") }
        if toField != nil { toField.placeholder = L("tr.phTo") }
        fromLabelBtn?.setTitle(L("tr.depart"), for: .normal)
        toLabelBtn?.setTitle(L("tr.arrive"), for: .normal)
        updateSideBarSelection()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Restore the last-used city (build 37): relaunch opens on
        // the city the user last switched to (written by pickCity
        // and by the web's cityChanged post; default Beijing).
        // Must run before any accentColor()/pill setup below.
        if let saved = UserDefaults.standard.string(forKey: "metro-city"),
           ["bj", "sy", "sh", "hb", "dl", "jh", "cz", "cq"].contains(saved) {
            currentCity = saved
        }
        view.backgroundColor = UIColor(red: 12.0 / 255.0, green: 15.0 / 255.0, blue: 22.0 / 255.0, alpha: 1) // #0c0f16, the web's dark background (build 63): nothing white shows through while the page loads or at the edges.

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "tabChanged")
        config.userContentController.add(self, name: "cityMenu")
        config.userContentController.add(self, name: "tabsFrame")
        config.userContentController.add(self, name: "transferFrame")
        config.userContentController.add(self, name: "themeFrame")
        config.userContentController.add(self, name: "stationPicked")
        config.userContentController.add(self, name: "timePicker")
        config.userContentController.add(self, name: "openTransitApp")
        config.userContentController.add(self, name: "openRideCode")
        config.userContentController.add(self, name: "requestLocation")
        config.userContentController.add(self, name: "cityChanged")
        config.userContentController.add(self, name: "langChanged")
        config.userContentController.add(self, name: "splashDone")
        config.userContentController.add(self, name: "liveActivity")
        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.allowsBackForwardNavigationGestures = true
        view.addSubview(webView)

        // Native tab bar (UITabBar). The web page hides its own
        // tab bar; this bar is the only one the user sees.
        tabBar = UITabBar()
        tabBar.delegate = self
        tabBar.tintColor = accentColor()
        let items = [
            UITabBarItem(title: L("tab.transfer"), image: UIImage(systemName: "arrow.triangle.2.circlepath"), tag: 0),
            UITabBarItem(title: L("tab.map"), image: UIImage(systemName: "map"), tag: 1),
            UITabBarItem(title: L("tab.stations"), image: UIImage(systemName: "magnifyingglass"), tag: 2),
            UITabBarItem(title: L("tab.timetable"), image: UIImage(named: "TimetableIcon"), tag: 3),
            UITabBarItem(title: L("tab.more"), image: UIImage(systemName: "gearshape"), tag: 4),
        ]
        tabBar.items = items
        tabBar.selectedItem = items[1] // default tab is the map, same as the web page
        // Floating Liquid Glass capsule (iOS 26 / SDK 27.2, user 2026-11-15):
        // the bar floats above the content with rounded ends. The glass is
        // the UITabBar's OWN Apple glass (default appearance on iOS 26+)
        // — a single layer. Build 50 added a UIVisualEffectView glass
        // subview on top of the bar's own glass, so the glass showed
        // TWICE (user 2026-11-15 "为啥有玻璃重复"). Do NOT add a glass
        // view here; the default appearance already is Liquid Glass.
        tabBar.layer.cornerRadius = 25
        tabBar.layer.masksToBounds = true
        if #available(iOS 26.0, *) {
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.shadowColor = .clear
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
        }
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabBar)
        // Splash gate: hidden until the web splash finishes.
        tabBar.isHidden = true
        // Floating bottom tab bar on EVERY device (build 63): the iPad
        // top strip is gone (user 2026-11-16 "不要这个大上吧" /
        // "底栏悬浮用 Apple UI SDK27.2") — the bar floats at the
        // bottom on iPad too, exactly like iPhone. The web view is
        // full-screen, so there is no white strip behind the bar.
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            // Lowered (build 63, user 2026-11-16 "把这个底栏下移一点
            // 按图二的高度"): the bar sits just above the home
            // indicator with only a small gap, like Apple's floating
            // tab bar in iOS 27.2 — anchored to the view bottom (not
            // the safe area) so it is the same height on iPhone and
            // iPad. Was safeArea.bottom - 4 (build 56), which left a
            // large gap above the home indicator.
            tabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
        ])
        // iPhone Duo sidebar (build 63): created here so the web view
        // trailing constraint below can anchor to it.
        setupSideBar()

        // Web view is full-screen on every device (build 63): iPad no
        // longer starts below a top tab bar (that strip is gone), and
        // iPhone keeps the full-screen web view. The bottom clearance
        // for the floating tab bar lives in the web CSS (panels:
        // padding-bottom 57px + safe-area), so no content is hidden
        // behind the floating bar. iPhone Duo sidebar: the trailing
        // edge toggles between the view edge and the sidebar's leading
        // edge (see updateSideBarLayout).
        webView.translatesAutoresizingMaskIntoConstraints = false
        webViewTrailingToView = webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        webViewTrailingToSideBar = webView.trailingAnchor.constraint(equalTo: sideBar.leadingAnchor, constant: -8)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webViewTrailingToView,
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
        ])

        // Swipe left/right on the tab bar to switch tabs (keeps the web
        // tab bar's swipe feature, now on the native bar).
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleTabSwipe(_:)))
        swipeLeft.direction = .left
        tabBar.addGestureRecognizer(swipeLeft)
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleTabSwipe(_:)))
        swipeRight.direction = .right
        tabBar.addGestureRecognizer(swipeRight)

        backButton = UIButton(type: .system)
        backButton.setTitle("‹ 返回", for: .normal)
        backButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        backButton.backgroundColor = UIColor(white: 1, alpha: 0.92)
        backButton.layer.cornerRadius = 18
        backButton.layer.borderWidth = 1
        backButton.layer.borderColor = accentDark().cgColor
        backButton.setTitleColor(accentDark(), for: .normal)
        backButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.isHidden = true
        view.addSubview(backButton)
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            // Above the floating bottom tab bar on every device
            // (build 63: iPad no longer has a top tab bar).
            backButton.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -16),
        ])

        setupNativePills()
        // Splash fallback: if the web never posts splashDone, reveal the
        // controls after 4s anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.splashFinished()
        }
        setupSortTabs()
        setupThemeButtons()
        setupTransferControls()
        // Native launch splash (build 53, user 2026-11-15 "点进去为什么
        // 第一时刻没有开屏动画是白屏"): the web splash only appears after
        // the 6.7 MB page loads, so the first moment was a white screen
        // (blank LaunchScreen + blank web view). Show the current city's
        // splash image natively from launch — same image as the web
        // per-city splash — and hide it when the web posts splashDone.
        // currentCity was restored from UserDefaults above, so the image
        // matches the city the user last used.
        let splashName: String
        switch currentCity {
        case "sy": splashName = "SplashSY"
        case "sh": splashName = "SplashSH"
        case "hb": splashName = "SplashHB"
        case "dl": splashName = "SplashDL"
        case "jh": splashName = "SplashJH"
        case "cz": splashName = "SplashCZ"
        case "cq": splashName = "SplashCQ"
        default: splashName = "Splash"
        }
        splashImageView = UIImageView(image: UIImage(named: splashName))
        splashImageView.contentMode = .scaleAspectFill
        splashImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splashImageView)
        NSLayoutConstraint.activate([
            splashImageView.topAnchor.constraint(equalTo: view.topAnchor),
            splashImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splashImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splashImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        webView.addObserver(self, forKeyPath: "canGoBack", options: .new, context: nil)
        loadMap()
        // iPhone Duo sidebar (build 63): pick sidebar vs bottom tab
        // bar for the launch width; viewDidLayoutSubviews re-picks it
        // when the phone folds/unfolds.
        updateSideBarLayout()
        // Hide the status bar while the splash is showing (build 63).
        setNeedsStatusBarAppearanceUpdate()
    }

    // Status bar (build 63, user 2026-11-16 "启动图片上面不要有时间
    // 和状态栏显示"): hide the status bar while the launch splash is
    // showing, so no time/battery/signal sits on top of the splash
    // image. It comes back once the splash fades and the app content
    // is shown. Only the in-app splash — the LaunchScreen is already
    // a plain blank screen and is untouched.
    override var prefersStatusBarHidden: Bool {
        return splashShowing
    }

    // Fold/unfold (and rotation) change the view width: re-evaluate
    // sidebar vs bottom tab bar. Only when the width actually moved,
    // so a constraint toggle does not re-trigger itself.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        if abs(w - lastSideBarLayoutWidth) > 0.5 {
            lastSideBarLayoutWidth = w
            updateSideBarLayout()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateSideBarLayout()
    }

    func loadMap() {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    @objc func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    // MARK: - Native Liquid Glass top pills

    // The two top pills are native UIButtons with Apple's true Liquid
    // Glass (UIButton.Configuration.glass(), iOS 26+; a frosted blur
    // fallback on older iOS). CSS backdrop-filter can only approximate
    // Liquid Glass, which is why the web pills kept being rejected.
    // Beijing keeps its blue theme; Shenyang uses gold.
    func setupNativePills() {
        cityPill = UIButton(type: .system)
        searchPill = UIButton(type: .system)
        for pill in [cityPill!, searchPill!] {
            pill.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(pill)
        }
        // Pills sit at the top safe area on every device (build 63:
        // the iPad top tab bar is gone, so there is no bar to sit below).
        NSLayoutConstraint.activate([
            cityPill.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            cityPill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            searchPill.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            searchPill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
        ])
        searchPill.addTarget(self, action: #selector(openStationSearch), for: .touchUpInside)
        updateCityPill()
        updateSearchPill()
        updatePillVisibility()
    }

    func accentColor() -> UIColor {
        if currentCity == "sy" { return shenyangGold }
        if currentCity == "sh" { return shanghaiRed }
        if currentCity == "hb" { return harbinRed }
        if currentCity == "dl" { return dalianBlue }
        if currentCity == "jh" { return jinhuaRed }
        if currentCity == "cz" { return changzhouRed }
        if currentCity == "cq" { return chongqingGreen }
        return subwayBlue
    }

    // Darker accent for text/borders on light backgrounds (legibility):
    // subway blue in Beijing, deep gold #8a6d2b in Shenyang.
    func accentDark() -> UIColor {
        if currentCity == "sy" { return shenyangGoldDark }
        if currentCity == "sh" { return shanghaiRedDark }
        if currentCity == "hb" { return harbinRedDark }
        if currentCity == "dl" { return dalianBlueDark }
        if currentCity == "jh" { return jinhuaRedDark }
        if currentCity == "cz" { return changzhouRedDark }
        if currentCity == "cq" { return chongqingGreenDark }
        return subwayBlue
    }

    // Search button colour (user 2026-11-15 ~20:12: "沈阳金 上海红"):
    // the button now matches the city theme — gold in Shenyang, red in
    // Shanghai. This reverses the 18:11 instruction (Shenyang red /
    // Shanghai gold); the user said the red/gold button looked reversed
    // against the gold/red theme.
    func searchButtonColor() -> UIColor {
        if currentCity == "sy" { return shenyangGold }
        if currentCity == "sh" { return shanghaiRed }
        if currentCity == "hb" { return harbinRed }
        if currentCity == "dl" { return dalianBlue }
        if currentCity == "jh" { return jinhuaRed }
        if currentCity == "cz" { return changzhouRed }
        if currentCity == "cq" { return chongqingGreen }
        return accentColor()
    }

    func cityLogoImage() -> UIImage? {
        return cityLogoImage(for: currentCity)
    }

    // Circular logo for a given city (build 65): the city switcher menu
    // shows each city's rail-transit logo in front of its name, so the
    // logo lookup takes the city instead of always using the current one.
    // The artwork is untouched — only clipped to a circle, as in the pill.
    func cityLogoImage(for city: String) -> UIImage? {
        let name: String
        switch city {
        case "sy": name = "ShenyangLogo"
        case "sh": name = "ShanghaiLogo"
        case "hb": name = "HarbinLogo"
        case "dl": name = "DalianLogo"
        case "jh": name = "JinhuaLogo"
        case "cz": name = "ChangzhouLogo"
        case "cq": name = "ChongqingLogo"
        default: name = "BeijingLogo"
        }
        guard let img = UIImage(named: name) else { return nil }
        let size = CGSize(width: 26, height: 26)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Circular clip (build 65): the Dalian logo is a square
            // image and showed as a square in the pill; the user wants
            // it round. The logo artwork itself is not redrawn or
            // altered — only the outer shape is clipped to a circle
            // (transparent corners). Aspect-fit so a non-square logo
            // is never distorted; a square source fills the circle.
            // Both the glass-configuration path and the setImage
            // fallback path use this, so the pill logo is round in
            // both. The pill's own capsule shape is unchanged.
            let rect = CGRect(origin: .zero, size: size)
            ctx.cgContext.addEllipse(in: rect)
            ctx.cgContext.clip()
            let scale = min(size.width / img.size.width, size.height / img.size.height)
            let w = img.size.width * scale, h = img.size.height * scale
            let drawRect = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
            img.draw(in: drawRect)
        }
    }

    func updateCityPill() {
        let name: String
        name = L("city." + currentCity)
        if #available(iOS 26.0, *) {
            var config = UIButton.Configuration.glass()
            config.title = name + "  ▾"
            config.image = cityLogoImage()
            config.imagePadding = 6
            config.baseForegroundColor = accentColor()
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 12)
            cityPill.configuration = config
        } else {
            cityPill.setTitle(name + "  ▾", for: .normal)
            cityPill.setImage(cityLogoImage(), for: .normal)
            cityPill.setTitleColor(accentColor(), for: .normal)
            cityPill.backgroundColor = UIColor(white: 1, alpha: 0.72)
            cityPill.layer.cornerRadius = 18
            cityPill.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 12)
        }
        // UIMenu anchored to this pill (top-left): tapping the pill pops
        // the city menu up right under it, not in the middle of the screen.
        cityPill.menu = cityMenu()
        cityPill.showsMenuAsPrimaryAction = true
    }

    func updateSearchPill() {
        if #available(iOS 26.0, *) {
            var config = UIButton.Configuration.glass()
            config.title = L("map.searchStation")
            config.image = UIImage(systemName: "magnifyingglass")
            config.imagePadding = 6
            config.baseForegroundColor = accentColor()
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 14)
            searchPill.configuration = config
        } else {
            searchPill.setTitle(L("map.searchStation"), for: .normal)
            searchPill.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
            searchPill.setTitleColor(accentColor(), for: .normal)
            searchPill.backgroundColor = UIColor(white: 1, alpha: 0.72)
            searchPill.layer.cornerRadius = 18
            searchPill.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 14)
        }
    }

    func cityMenu() -> UIMenu {
        // City logos in front of each name (build 65, user request):
        // .alwaysOriginal so the menu shows the logos in their own
        // colours instead of tinting them as template images.
        let bj = UIAction(title: L("city.bj"), image: cityLogoImage(for: "bj")?.withRenderingMode(.alwaysOriginal), identifier: nil, discoverabilityTitle: nil, attributes: [], state: currentCity == "bj" ? .on : .off) { [weak self] _ in
            self?.pickCity("bj")
        }
        let sy = UIAction(title: L("city.sy"), image: cityLogoImage(for: "sy")?.withRenderingMode(.alwaysOriginal), identifier: nil, discoverabilityTitle: nil, attributes: [], state: currentCity == "sy" ? .on : .off) { [weak self] _ in
            self?.pickCity("sy")
        }
        let sh = UIAction(title: L("city.sh"), image: cityLogoImage(for: "sh")?.withRenderingMode(.alwaysOriginal), identifier: nil, discoverabilityTitle: nil, attributes: [], state: currentCity == "sh" ? .on : .off) { [weak self] _ in
            self?.pickCity("sh")
        }
        let hb = UIAction(title: L("city.hb"), image: cityLogoImage(for: "hb")?.withRenderingMode(.alwaysOriginal), identifier: nil, discoverabilityTitle: nil, attributes: [], state: currentCity == "hb" ? .on : .off) { [weak self] _ in
            self?.pickCity("hb")
        }
        let dl = UIAction(title: L("city.dl"), image: cityLogoImage(for: "dl")?.withRenderingMode(.alwaysOriginal), identifier: nil, discoverabilityTitle: nil, attributes: [], state: currentCity == "dl" ? .on : .off) { [weak self] _ in
            self?.pickCity("dl")
        }
        let jh = UIAction(title: L("city.jh"), image: cityLogoImage(for: "jh")?.withRenderingMode(.alwaysOriginal), identifier: nil, discoverabilityTitle: nil, attributes: [], state: currentCity == "jh" ? .on : .off) { [weak self] _ in
            self?.pickCity("jh")
        }
        let cz = UIAction(title: L("city.cz"), image: cityLogoImage(for: "cz")?.withRenderingMode(.alwaysOriginal), identifier: nil, discoverabilityTitle: nil, attributes: [], state: currentCity == "cz" ? .on : .off) { [weak self] _ in
            self?.pickCity("cz")
        }
        let cq = UIAction(title: L("city.cq"), image: cityLogoImage(for: "cq")?.withRenderingMode(.alwaysOriginal), identifier: nil, discoverabilityTitle: nil, attributes: [], state: currentCity == "cq" ? .on : .off) { [weak self] _ in
            self?.pickCity("cq")
        }
        return UIMenu(title: "", children: [bj, sy, sh, hb, dl, jh, cz, cq])
    }

    // The transfer panel's city row (web) also asks for the city menu:
    // show it as a native action sheet in a popover anchored to the
    // city pill (top-left), never in the middle of the screen.
    func presentCityMenuPopover() {
        let sheet = UIAlertController(title: L("native.switchCity"), message: nil, preferredStyle: .actionSheet)
        // City logos (build 65): UIAlertAction has no public image API,
        // so the logo is attached with setValue(forKey: "image") — the
        // long-established way to put an image on an alert action.
        func cityAction(_ city: String) -> UIAlertAction {
            let a = UIAlertAction(title: currentCity == city ? "✓ " + L("city." + city) : L("city." + city), style: .default) { [weak self] _ in
                self?.pickCity(city)
            }
            if let img = cityLogoImage(for: city)?.withRenderingMode(.alwaysOriginal) {
                a.setValue(img, forKey: "image")
            }
            return a
        }
        sheet.addAction(cityAction("bj"))
        sheet.addAction(cityAction("sy"))
        sheet.addAction(cityAction("sh"))
        sheet.addAction(cityAction("hb"))
        sheet.addAction(cityAction("dl"))
        sheet.addAction(cityAction("jh"))
        sheet.addAction(cityAction("cz"))
        sheet.addAction(cityAction("cq"))
        sheet.addAction(UIAlertAction(title: L("native.cancel"), style: .cancel))
        sheet.modalPresentationStyle = .popover
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = cityPill.frame
            pop.permittedArrowDirections = .up
        }
        present(sheet, animated: true)
    }

    // Shared city-UI refresh (build 37): tab-bar tint, back-button
    // color, pills and transfer controls for the current city. Used
    // by pickCity() (native-initiated) and the cityChanged handler
    // (web-initiated, incl. the startup restore).
    func refreshCityUI() {
        tabBar.tintColor = accentColor()
        backButton.layer.borderColor = accentDark().cgColor
        backButton.setTitleColor(accentDark(), for: .normal)
        updateCityPill()
        updateSearchPill()
        updateSideBarSelection()
        clearTransferFields()
        updateTransferTint()
    }

    func pickCity(_ city: String) {
        guard city != currentCity else { return }
        currentCity = city
        UserDefaults.standard.set(city, forKey: "metro-city")
        refreshCityUI()
        webView.evaluateJavaScript("window.metroApp && window.metroApp.switchCity('\(city)')", completionHandler: nil)
    }

    @objc func openStationSearch() {
        webView.evaluateJavaScript("window.metroApp && window.metroApp.openStations()", completionHandler: nil)
    }

    // MARK: - Native Liquid Glass route-sort tabs

    // The four route-sort tabs (推荐/耗时最短/路径最短/节省票价) are a
    // native UISegmentedControl, which renders with Apple's Liquid Glass
    // on iOS 26+. The web page hides its own tab row in the native app
    // (visibility:hidden, space kept) and reports the row's frame, so
    // this control sits exactly where the web tabs were. Position is
    // frame-based (not Auto Layout) because the web panel moves it.
    func setupSortTabs() {
        sortTabs = UISegmentedControl(items: [L("tr.tab.rec"), L("tr.tab.early"), L("tr.tab.fewest"), L("tr.tab.cheap")])
        sortTabs.selectedSegmentIndex = 0
        sortTabs.translatesAutoresizingMaskIntoConstraints = true
        sortTabs.isHidden = true
        sortTabs.addTarget(self, action: #selector(sortTabChanged(_:)), for: .valueChanged)
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]
        sortTabs.setTitleTextAttributes(attrs, for: .normal)
        sortTabs.setTitleTextAttributes(attrs, for: .selected)
        view.addSubview(sortTabs)
    }

    @objc func sortTabChanged(_ sender: UISegmentedControl) {
        let idx = sender.selectedSegmentIndex
        guard idx >= 0 && idx < sortTabKeys.count else { return }
        let key = sortTabKeys[idx]
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setRouteTab('\(key)')", completionHandler: nil)
    }

    // Place the native sort tabs over the web tab row's reported frame.
    // The web rect is in CSS pixels; the full-screen web view maps them
    // 1:1 to points. A zero-size rect (no routes, or the transfer panel
    // is hidden) hides the control.
    func placeSortTabs(frame dict: [String: Any]) {
        // Native Apple UI sort tabs (user 2026-11-15: "这个要Apple UI
        // SDK27.2"): the UISegmentedControl (Liquid Glass on iOS 26+)
        // overlays the web tab row's frame; the web hides its own row
        // in the native app. A zero-size rect (no routes, or the panel
        // is hidden) hides the control.
        let x = (dict["x"] as? Double) ?? 0
        let y = (dict["y"] as? Double) ?? 0
        let w = (dict["width"] as? Double) ?? 0
        let h = (dict["height"] as? Double) ?? 0
        let tab = dict["tab"] as? String ?? ""
        if w > 0 && h > 0 && currentTab == "transfer" {
            sortTabs.frame = CGRect(x: x + webOffset.x, y: y + webOffset.y, width: w, height: h)
            sortTabs.isHidden = false
            if let idx = sortTabKeys.firstIndex(of: tab) {
                sortTabs.selectedSegmentIndex = idx
            }
        } else {
            sortTabs.isHidden = true
        }
    }

    // MARK: - Native Apple UI dark-mode picker (build 44, 3 glass buttons since build 52)

    // The 深色模式 picker (跟随系统/浅色/深色) is 3 separate native
    // Liquid Glass buttons (user 2026-11-15 "改成3个液态玻璃按钮
    // 不要滑动效果了") — NOT a UISegmentedControl, so there is no
    // sliding selection pill; each button is independent and the
    // selected one shows a static accent tint. They overlay the
    // settings panel's .more-theme-seg row (same pattern as sortTabs);
    // the web hides its own row in the native app and reports the frame.
    // Glass button config for the theme picker: Liquid Glass on iOS 26+,
    // a filled capsule below (same pattern as the top pills). The
    // .glass() call must sit inside the #available check — calling it
    // unconditionally does not compile against the iOS 16 target
    // (that is what failed build 52).
    func themeButtonConfig() -> UIButton.Configuration {
        var cfg: UIButton.Configuration
        if #available(iOS 26.0, *) {
            cfg = UIButton.Configuration.glass()
        } else {
            cfg = UIButton.Configuration.filled()
        }
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            return a
        }
        return cfg
    }

    func setupThemeButtons() {
        let titles = [L("more.theme.system"), L("more.theme.light"), L("more.theme.dark")]
        for (i, title) in titles.enumerated() {
            let btn = UIButton(type: .system)
            var cfg = themeButtonConfig()
            cfg.title = title
            btn.configuration = cfg
            btn.tag = i
            btn.translatesAutoresizingMaskIntoConstraints = true
            btn.isHidden = true
            btn.addTarget(self, action: #selector(themeButtonTapped(_:)), for: .touchUpInside)
            view.addSubview(btn)
            themeButtons.append(btn)
        }
        updateThemeButtons(selected: 0)
    }

    @objc func themeButtonTapped(_ sender: UIButton) {
        let idx = sender.tag
        guard idx >= 0 && idx < themeSegKeys.count else { return }
        let key = themeSegKeys[idx]
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setTheme('\(key)')", completionHandler: nil)
        updateThemeButtons(selected: idx)
    }

    // Static highlight for the selected glass button (no sliding):
    // selected = accent-tinted glass with an accent title; unselected =
    // plain glass with the default label colour.
    func updateThemeButtons(selected idx: Int) {
        for (i, btn) in themeButtons.enumerated() {
            var cfg = btn.configuration ?? themeButtonConfig()
            if i == idx {
                cfg.baseForegroundColor = accentColor()
                cfg.baseBackgroundColor = accentColor().withAlphaComponent(0.15)
            } else {
                cfg.baseForegroundColor = .label
                cfg.baseBackgroundColor = nil
            }
            btn.configuration = cfg
        }
    }

    // Place the 3 native glass buttons over the web row's reported
    // frame (each 1/3 of the width, 8pt gaps). A zero-size rect
    // (settings panel not shown) hides them.
    func placeThemeButtons(frame dict: [String: Any]) {
        let x = ((dict["x"] as? Double) ?? 0) + webOffset.x
        let y = ((dict["y"] as? Double) ?? 0) + webOffset.y
        let w = (dict["width"] as? Double) ?? 0
        let h = (dict["height"] as? Double) ?? 0
        let theme = dict["theme"] as? String ?? ""
        if w > 0 && h > 0 && currentTab == "more" {
            let gap: CGFloat = 8
            let bw = (CGFloat(w) - gap * 2) / 3
            for (i, btn) in themeButtons.enumerated() {
                btn.frame = CGRect(x: CGFloat(x) + CGFloat(i) * (bw + gap), y: CGFloat(y), width: bw, height: CGFloat(h))
                btn.isHidden = false
            }
            if let idx = themeSegKeys.firstIndex(of: theme) {
                updateThemeButtons(selected: idx)
            }
        } else {
            for btn in themeButtons { btn.isHidden = true }
        }
    }

    // MARK: - Native Liquid Glass transfer input area (build 37)

    // The from/to fields card and the 搜索 button are native Liquid
    // Glass controls overlaid on the web panel's .tr-fields / .tr-search
    // rows (the web hides its own rows in the native app and reports
    // their frames, like the sort tabs). The suggestion dropdown stays
    // web: it renders below the hidden fields card, i.e. directly
    // below this native card. The card is a UIVisualEffectView with
    // UIGlassEffect .clear on iOS 26+ (thinnest material below) — pure
    // transparent glass, no colour tint at all (user 2026-11-17
    // "不要渲染颜色 就要透明"): the background shows straight through.
    // The search button uses UIButton.Configuration.glass() like the
    // top pills.
    func setupTransferControls() {
        // Card container (frame-positioned from the web .tr-fields rect).
        transferCard = UIView()
        transferCard.layer.cornerRadius = 20
        transferCard.clipsToBounds = true
        transferCard.isHidden = true
        view.addSubview(transferCard)

        transferEffectView = makeClearGlassEffectView()
        transferEffectView.translatesAutoresizingMaskIntoConstraints = false
        transferCard.addSubview(transferEffectView)
        NSLayoutConstraint.activate([
            transferEffectView.leadingAnchor.constraint(equalTo: transferCard.leadingAnchor),
            transferEffectView.trailingAnchor.constraint(equalTo: transferCard.trailingAnchor),
            transferEffectView.topAnchor.constraint(equalTo: transferCard.topAnchor),
            transferEffectView.bottomAnchor.constraint(equalTo: transferCard.bottomAnchor),
        ])

        let content = transferEffectView.contentView

        // Two rows: dot + label + text field + line badge + clear.
        fromField = makeTransferField(tag: 0, placeholder: L("tr.phFrom"))
        toField = makeTransferField(tag: 1, placeholder: L("tr.phTo"))
        fromBadge = makeTransferBadge(tag: 0)
        toBadge = makeTransferBadge(tag: 1)
        fromClear = makeTransferClear(tag: 0)
        toClear = makeTransferClear(tag: 1)
        let fromRow = makeTransferRow(dotColor: UIColor(red: 34.0 / 255.0, green: 160.0 / 255.0, blue: 107.0 / 255.0, alpha: 1),
                                      labelTitle: L("tr.depart"), labelTag: 0,
                                      field: fromField, badge: fromBadge, clear: fromClear)
        let toRow = makeTransferRow(dotColor: UIColor(red: 229.0 / 255.0, green: 72.0 / 255.0, blue: 77.0 / 255.0, alpha: 1),
                                    labelTitle: L("tr.arrive"), labelTag: 1,
                                    field: toField, badge: toBadge, clear: toClear)
        fromLabelBtn = fromRow.arrangedSubviews[1] as? UIButton
        toLabelBtn = toRow.arrangedSubviews[1] as? UIButton
        for row in [fromRow, toRow] {
            row.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(row)
        }
        let divider = UIView()
        divider.backgroundColor = UIColor(white: 0, alpha: 0.06)
        divider.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(divider)
        NSLayoutConstraint.activate([
            fromRow.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            fromRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            fromRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -56),
            fromRow.bottomAnchor.constraint(equalTo: divider.topAnchor),
            divider.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            divider.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -56),
            divider.heightAnchor.constraint(equalToConstant: 1),
            divider.bottomAnchor.constraint(equalTo: toRow.topAnchor),
            toRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            toRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -56),
            toRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -6),
            fromRow.heightAnchor.constraint(equalTo: toRow.heightAnchor),
        ])

        // Swap button: a frosted white circle at the right, vertically
        // centred (mirrors the web .tr-swap; it sits on the glass card).
        transferSwapButton = UIButton(type: .system)
        transferSwapButton.setImage(UIImage(systemName: "arrow.up.arrow.down"), for: .normal)
        transferSwapButton.tintColor = accentDark()
        transferSwapButton.backgroundColor = UIColor(white: 1, alpha: 0.85)
        transferSwapButton.layer.cornerRadius = 18
        transferSwapButton.layer.borderWidth = 1
        transferSwapButton.layer.borderColor = accentDark().cgColor
        transferSwapButton.addTarget(self, action: #selector(transferSwapTapped), for: .touchUpInside)
        transferSwapButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(transferSwapButton)
        NSLayoutConstraint.activate([
            transferSwapButton.widthAnchor.constraint(equalToConstant: 36),
            transferSwapButton.heightAnchor.constraint(equalToConstant: 36),
            transferSwapButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            transferSwapButton.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        // 搜索 button (frame-positioned from the web .tr-search rect).
        transferSearchButton = UIButton(type: .system)
        transferSearchButton.isHidden = true
        transferSearchButton.addTarget(self, action: #selector(transferSearchTapped), for: .touchUpInside)
        view.addSubview(transferSearchButton)
        updateTransferSearchStyle()
    }

    func makeGlassEffectView() -> UIVisualEffectView {
        if #available(iOS 26.0, *) {
            return UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        }
        return UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    }

    // Clear glass for the transfer card (user 2026-11-17 "改为纯色透明玻璃"):
    // UIGlassEffect .clear is the most transparent glass — the background
    // shows through with blur and almost no built-in tint, so the card's
    // single solid colour comes only from the uniform accent tint overlay.
    // Fallback on older iOS is the thinnest material.
    func makeClearGlassEffectView() -> UIVisualEffectView {
        if #available(iOS 26.0, *) {
            return UIVisualEffectView(effect: UIGlassEffect(style: .clear))
        }
        return UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    }

    func makeTransferRow(dotColor: UIColor, labelTitle: String, labelTag: Int, field: UITextField, badge: UIButton, clear: UIButton) -> UIStackView {
        let dot = UIView()
        dot.backgroundColor = dotColor
        dot.layer.cornerRadius = 5
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 10).isActive = true
        // Tapping 出发/到达 opens the station picker for that side
        // (web openPick), exactly like the web label.
        let label = UIButton(type: .system)
        label.setTitle(labelTitle, for: .normal)
        label.titleLabel?.font = .systemFont(ofSize: 15)
        label.setTitleColor(.systemGray, for: .normal)
        label.tag = labelTag
        label.addTarget(self, action: #selector(transferLabelTapped(_:)), for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [dot, label, field, badge, clear])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.distribution = .fill
        return row
    }

    func makeTransferField(tag: Int, placeholder: String) -> UITextField {
        let f = UITextField()
        f.tag = tag
        f.delegate = self
        f.font = .systemFont(ofSize: 17, weight: .semibold)
        f.textColor = .label
        f.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor(red: 170.0 / 255.0, green: 170.0 / 255.0, blue: 170.0 / 255.0, alpha: 1), .font: UIFont.systemFont(ofSize: 17)])
        f.borderStyle = .none
        f.backgroundColor = .clear
        f.autocorrectionType = .no
        f.autocapitalizationType = .none
        f.spellCheckingType = .no
        f.returnKeyType = .search
        f.inputAccessoryView = makeKeyboardToolbar()
        f.addTarget(self, action: #selector(transferFieldChanged(_:)), for: .editingChanged)
        return f
    }

    func makeTransferBadge(tag: Int) -> UIButton {
        let b = UIButton(type: .system)
        b.tag = tag
        b.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        b.layer.cornerRadius = 6
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        b.isHidden = true
        b.addTarget(self, action: #selector(transferBadgeTapped(_:)), for: .touchUpInside)
        b.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return b
    }

    func makeTransferClear(tag: Int) -> UIButton {
        let b = UIButton(type: .system)
        b.tag = tag
        b.setTitle("✕", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 12)
        b.setTitleColor(UIColor(white: 0.4, alpha: 1), for: .normal)
        b.backgroundColor = UIColor(white: 0, alpha: 0.08)
        b.layer.cornerRadius = 11
        b.isHidden = true
        b.addTarget(self, action: #selector(transferClearTapped(_:)), for: .touchUpInside)
        b.widthAnchor.constraint(equalToConstant: 22).isActive = true
        b.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return b
    }

    func makeKeyboardToolbar() -> UIToolbar {
        let tb = UIToolbar()
        tb.sizeToFit()
        let done = UIBarButtonItem(title: L("time.done"), style: .done, target: self, action: #selector(dismissTransferKeyboard))
        tb.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), done]
        return tb
    }

    @objc func dismissTransferKeyboard() {
        view.endEditing(true)
    }

    // Place the native transfer card + search button over the web rows'
    // reported frames, and sync the native fields with the web state.
    // The web rects are in CSS pixels; the full-screen web view maps
    // them 1:1 to points. A zero-size rect (panel hidden, or not on
    // the transfer tab) hides the controls. Field text is only copied
    // from the web while the user is NOT typing in that field, so the
    // caret never jumps.
    func placeTransfer(frame dict: [String: Any]) {
        guard let f = dict["fields"] as? [String: Any],
              let s = dict["search"] as? [String: Any] else {
            transferCard.isHidden = true
            transferSearchButton.isHidden = true
            return
        }
        let fx = (f["x"] as? Double) ?? 0
        let fy = (f["y"] as? Double) ?? 0
        let fw = (f["width"] as? Double) ?? 0
        let fh = (f["height"] as? Double) ?? 0
        let sx = (s["x"] as? Double) ?? 0
        let sy = (s["y"] as? Double) ?? 0
        let sw = (s["width"] as? Double) ?? 0
        let sh = (s["height"] as? Double) ?? 0
        if fw > 0 && fh > 0 && currentTab == "transfer" {
            transferCard.frame = CGRect(x: fx + webOffset.x, y: fy + webOffset.y, width: fw, height: fh)
            transferCard.isHidden = false
            if let q = dict["fromQuery"] as? String, !fromField.isFirstResponder, fromField.text != q {
                fromField.text = q
            }
            if let q = dict["toQuery"] as? String, !toField.isFirstResponder, toField.text != q {
                toField.text = q
            }
            applyBadge(which: "from", line: dict["fromLine"] as? [String: Any])
            applyBadge(which: "to", line: dict["toLine"] as? [String: Any])
            updateClearButtons()
        } else {
            transferCard.isHidden = true
        }
        if sw > 0 && sh > 0 && currentTab == "transfer" {
            transferSearchButton.frame = CGRect(x: sx + webOffset.x, y: sy + webOffset.y, width: sw, height: sh)
            transferSearchButton.isHidden = false
            // Refresh the button colour here too (build 43): the colour
            // is set from currentCity, and placeTransfer runs every time
            // the web reports the frame (city switch, scroll, layout),
            // so the red/gold is always re-applied when the button shows.
            // The capsule radius is (re-)applied inside
            // updateTransferSearchStyle, after configuration = nil
            // (build 63 overflow fix) — do not set it here.
            updateTransferSearchStyle()
        } else {
            transferSearchButton.isHidden = true
        }
    }

    func updateTransferVisibility() {
        if currentTab != "transfer" {
            transferCard.isHidden = true
            transferSearchButton.isHidden = true
            view.endEditing(true)
        }
        // Dark-mode picker only lives on the settings tab.
        if currentTab != "more" {
            for btn in themeButtons { btn.isHidden = true }
        }
    }

    func clearTransferFields() {
        fromField.text = ""
        toField.text = ""
        fromLineInfo = nil
        toLineInfo = nil
        applyBadge(which: "from", line: nil)
        applyBadge(which: "to", line: nil)
        updateClearButtons()
    }

    func updateTransferTint() {
        transferSwapButton.layer.borderColor = accentDark().cgColor
        transferSwapButton.tintColor = accentDark()
        updateTransferSearchStyle()
    }

    func updateTransferSearchStyle() {
        // Solid city colour (build 44, repainted build 55): the glass
        // configuration never showed the colour — UIButton.Configuration
        // .glass() ignored baseBackgroundColor (and tintColor) on
        // iOS 27.2, so the button stayed the default blue in
        // Shenyang/Shanghai through builds 42 and 43 ("按钮还是没改").
        // Build 44 used a filled() configuration, but its own capsule
        // background view can peek out past the button's rounded layer
        // (the white crescents the user still sees in build 51,
        // "还是溢出"). So paint the capsule with the button's own layer
        // instead: backgroundColor = city colour, cornerRadius = half
        // the height (set in placeTransfer), masksToBounds — the blue
        // itself IS the capsule, so nothing can overflow it.
        transferSearchButton.configuration = nil
        transferSearchButton.setTitle(L("tr.search"), for: .normal)
        transferSearchButton.setTitleColor(.white, for: .normal)
        transferSearchButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        transferSearchButton.backgroundColor = searchButtonColor()
        transferSearchButton.tintColor = .white
        // Capsule radius (build 63, user 2026-11-16 "颜色溢出"): the
        // radius MUST be set here, AFTER configuration = nil — clearing
        // the configuration resets the layer's corner radius, so the
        // solid background painted past the rounded ends even though
        // placeTransfer had set it (the build-55 fix was undone by
        // the ordering). bounds.height is the button's current height
        // (placeTransfer sets the frame before calling this); the
        // zero-height guard covers setup time, before any frame.
        if transferSearchButton.bounds.height > 0 {
            transferSearchButton.layer.cornerRadius = transferSearchButton.bounds.height / 2
        }
        transferSearchButton.clipsToBounds = true
        transferSearchButton.layer.masksToBounds = true
    }

    // Line badge: a small pill with the line's colour + name (same
    // style as the web .tr-line-pick). line is {name, color, text}
    // with hex strings; nil hides the badge.
    func applyBadge(which: String, line: [String: Any]?) {
        if which == "from" { fromLineInfo = line } else { toLineInfo = line }
        guard let badge = which == "from" ? fromBadge : toBadge else { return }
        guard let line = line,
              let name = line["name"] as? String,
              let colorHex = line["color"] as? String,
              let bg = colorFromHex(colorHex) else {
            badge.isHidden = true
            return
        }
        let fg: UIColor
        if let textHex = line["text"] as? String, let c = colorFromHex(textHex) {
            fg = c
        } else {
            fg = .white
        }
        badge.setTitle(name, for: .normal)
        badge.backgroundColor = bg
        badge.setTitleColor(fg, for: .normal)
        badge.isHidden = false
    }

    func updateClearButtons() {
        fromClear.isHidden = (fromField.text ?? "").isEmpty
        toClear.isHidden = (toField.text ?? "").isEmpty
    }

    func colorFromHex(_ hex: String) -> UIColor? {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        if h.count == 3 {
            var out = ""
            for ch in h { out.append(ch); out.append(ch) }
            h = out
        }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return UIColor(red: CGFloat((v >> 16) & 0xff) / 255.0,
                       green: CGFloat((v >> 8) & 0xff) / 255.0,
                       blue: CGFloat(v & 0xff) / 255.0,
                       alpha: 1)
    }

    func jsString(_ s: String) -> String {
        var out = "'"
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "'": out += "\\'"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            default: out.append(ch)
            }
        }
        out += "'"
        return out
    }

    // MARK: - Transfer input actions + text field delegate

    @objc func transferFieldChanged(_ sender: UITextField) {
        let which = sender.tag == 0 ? "from" : "to"
        let text = sender.text ?? ""
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setNativeQuery('\(which)', \(jsString(text)))", completionHandler: nil)
        updateClearButtons()
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        let which = textField.tag == 0 ? "from" : "to"
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setNativeFocus('\(which)')", completionHandler: nil)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setNativeBlur()", completionHandler: nil)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        transferSearchTapped()
        return true
    }

    @objc func transferLabelTapped(_ sender: UIButton) {
        let which = sender.tag == 0 ? "from" : "to"
        webView.evaluateJavaScript("window.metroApp && window.metroApp.openPick('\(which)')", completionHandler: nil)
    }

    @objc func transferSwapTapped() {
        let ft = fromField.text ?? ""
        fromField.text = toField.text
        toField.text = ft
        let fl = fromLineInfo
        fromLineInfo = toLineInfo
        toLineInfo = fl
        applyBadge(which: "from", line: fromLineInfo)
        applyBadge(which: "to", line: toLineInfo)
        updateClearButtons()
        webView.evaluateJavaScript("window.metroApp && window.metroApp.swapStations()", completionHandler: nil)
    }

    @objc func transferClearTapped(_ sender: UIButton) {
        let which = sender.tag == 0 ? "from" : "to"
        if which == "from" {
            fromField.text = ""
            applyBadge(which: "from", line: nil)
        } else {
            toField.text = ""
            applyBadge(which: "to", line: nil)
        }
        updateClearButtons()
        webView.evaluateJavaScript("window.metroApp && window.metroApp.clearStation('\(which)')", completionHandler: nil)
    }

    @objc func transferBadgeTapped(_ sender: UIButton) {
        let which = sender.tag == 0 ? "from" : "to"
        applyBadge(which: which, line: nil)
        webView.evaluateJavaScript("window.metroApp && window.metroApp.clearLine('\(which)')", completionHandler: nil)
    }

    @objc func transferSearchTapped() {
        view.endEditing(true)
        webView.evaluateJavaScript("window.metroApp && window.metroApp.doSearch()", completionHandler: nil)
    }

    func updatePillVisibility() {
        let show = currentTab == "map" && !splashShowing
        cityPill.isHidden = !show
        searchPill.isHidden = !show
    }

    // Called when the web splash finishes (or the fallback timer fires):
    // reveal the native controls.
    func splashFinished() {
        guard splashShowing else { return }
        splashShowing = false
        // Status bar comes back now that the splash is done (build 63).
        setNeedsStatusBarAppearanceUpdate()
        // Reveal the tab bar or the Duo sidebar, whichever the current
        // layout uses (build 63).
        updateSideBarLayout()
        updatePillVisibility()
        // Fade the native launch splash out (same 0.4s as the web splash)
        // to reveal the map underneath.
        if let splash = splashImageView {
            UIView.animate(withDuration: 0.4, animations: {
                splash.alpha = 0
            }, completion: { _ in
                splash.removeFromSuperview()
            })
            splashImageView = nil
        }
    }

    // MARK: - Departure time picker (build 34)

    // The top-right 现在出发 label (web) asks the native shell for a
    // time picker: a sheet with Apple's UIDatePicker in wheel style
    // (preferredDatePickerStyle .wheels, SDK 26.5), plus 现在出发
    // (back to "now") and 确定. The chosen time is sent back to the
    // web page, which recomputes every route's depart/arrive times
    // from it (durations are unchanged estimates).
    func presentTimePicker(current: String?) {
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        if #available(iOS 13.4, *) { picker.preferredDatePickerStyle = .wheels }
        picker.locale = Locale(identifier: currentLang == "en" ? "en_US" : (currentLang == "zh-Hant" ? "zh_TW" : "zh_CN"))
        if let t = current {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            if let d = fmt.date(from: t) { picker.date = d }
        }
        picker.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(picker)

        let nowButton = UIButton(type: .system)
        nowButton.setTitle(L("tr.departNow"), for: .normal)
        nowButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        nowButton.setTitleColor(accentDark(), for: .normal)
        nowButton.addTarget(self, action: #selector(timePickerNow), for: .touchUpInside)
        nowButton.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(nowButton)

        let doneButton = UIButton(type: .system)
        doneButton.setTitle(L("time.confirm"), for: .normal)
        doneButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        doneButton.setTitleColor(accentDark(), for: .normal)
        doneButton.addTarget(self, action: #selector(timePickerDone(_:)), for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(doneButton)
        // The picker is found by tag when 确定 is tapped.
        picker.tag = 7701

        NSLayoutConstraint.activate([
            nowButton.leadingAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            nowButton.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            doneButton.trailingAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            doneButton.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            picker.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            picker.topAnchor.constraint(equalTo: nowButton.bottomAnchor, constant: 8),
            picker.bottomAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])

        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        present(vc, animated: true)
    }

    @objc func timePickerNow() {
        dismiss(animated: true)
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setDepartTime(null)", completionHandler: nil)
    }

    @objc func timePickerDone(_ sender: UIButton) {
        guard let vc = presentedViewController,
              let picker = vc.view.viewWithTag(7701) as? UIDatePicker else {
            dismiss(animated: true)
            return
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let t = fmt.string(from: picker.date)
        dismiss(animated: true)
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setDepartTime('\(t)')", completionHandler: nil)
    }

    // MARK: - Transit app link (build 35)

    // The transfer panel's 打开一卡通 / 打开盛京通 / 打开Metro大都会 row:
    // open the current city's transit-card app on the App Store (tap 打开
    // there if it is installed). App Store ids verified via the iTunes
    // Search API 2026-11-15: Beijing Yikatong 1071038870, Shenyang
    // Shengjing Tong 1441271928, Shanghai Metro大都会 1202750238, Dalian
    // 交通e出行 1383655806. There
    // is no confirmed URL scheme for any of these apps, so the App Store
    // page (not a guessed scheme) is the link.
    func openTransitApp() {
        let id: String
        switch currentCity {
        case "sy": id = "1441271928"
        case "sh": id = "1202750238"
        case "hb": id = "1448467024"
        case "dl": id = "1383655806"
        case "jh": id = "6503238645"
        case "cz": id = "1474201266"
        case "cq": id = "1491110313"
        default: id = "1071038870"
        }
        guard let url = URL(string: "https://apps.apple.com/cn/app/id\(id)") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    // 乘车码 (build 63): jump to the WeChat 乘车码 mini-program. The
    // user-provided mini-program link is
    // #小程序://乘车码/cZxzR2rsEppAxSv — one mini-program covering
    // all cities, so the same link is used for every city. WeChat's
    // deep link is weixin://dl/business/?t= with the link
    // percent-encoded as the ticket; if WeChat cannot open it, fall
    // back to opening WeChat itself. `weixin` is declared in
    // LSApplicationQueriesSchemes so canOpenURL works. Whether WeChat
    // opens the mini-program directly from this ticket needs an
    // on-device check — the link form is WeChat's own share format.
    func openRideCode(link: String) {
        let encoded = link.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "weixin://dl/business/?t=\(encoded)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return
        }
        if let wx = URL(string: "weixin://"), UIApplication.shared.canOpenURL(wx) {
            UIApplication.shared.open(wx, options: [:], completionHandler: nil)
        }
    }

    // MARK: - Location: nearest station (build 63)

    // The user taps 附近车站 in the transfer panel. The permission
    // prompt appears ONLY here, never at launch. If already
    // authorized, fetch one location fix and hand it to the web,
    // which computes the nearest stations (haversine) from the
    // stations' lat/lng and lists them. If denied/restricted, tell
    // the web so it shows a message instead of crashing or hanging.
    // NOTE: station lat/lng data is pending for all 5 cities in this
    // build (no reliable geocoding source was reachable — Overpass
    // timed out, Nominatim returned nothing for these stations), so
    // the web currently reports "coordinates not yet available" until
    // lat/lng is added per city. The wiring below is complete.
    func requestNearbyLocation() {
        if locationManager == nil {
            let lm = CLLocationManager()
            lm.delegate = self
            lm.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManager = lm
        }
        guard let lm = locationManager else { return }
        let status = lm.authorizationStatus
        switch status {
        case .notDetermined:
            locationPending = true
            lm.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationPending = true
            lm.requestLocation()
        case .denied, .restricted:
            notifyLocationError(L("loc.perm"))
        @unknown default:
            notifyLocationError(L("loc.failed"))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Called after the user answers the permission prompt.
        guard locationPending else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            locationPending = false
            notifyLocationError(L("loc.perm"))
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard locationPending, let loc = locations.last else { return }
        locationPending = false
        manager.stopUpdatingLocation()
        let lat = loc.coordinate.latitude
        let lng = loc.coordinate.longitude
        webView.evaluateJavaScript("window.metroApp && window.metroApp.showNearbyStations(\(lat), \(lng))", completionHandler: nil)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard locationPending else { return }
        locationPending = false
        notifyLocationError(L("loc.retry"))
    }

    func notifyLocationError(_ message: String) {
        let escaped = message.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.metroApp && window.metroApp.nearbyError('\(escaped)')", completionHandler: nil)
    }

    // MARK: - Native tab bar -> web page

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        setWebTab(index: item.tag)
    }

    func setWebTab(index: Int) {
        guard index >= 0 && index < tabKeys.count else { return }
        let key = tabKeys[index]
        currentTab = key
        updatePillVisibility()
        updateTransferVisibility()
        updateSideBarSelection()
        if key != "transfer" { sortTabs.isHidden = true }
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setTab('\(key)')", completionHandler: nil)
    }

    @objc func handleTabSwipe(_ gesture: UISwipeGestureRecognizer) {
        let current = tabBar.selectedItem?.tag ?? 1
        var next = current
        if gesture.direction == .left {
            next = min(current + 1, tabKeys.count - 1)
        } else {
            next = max(current - 1, 0)
        }
        if next != current {
            tabBar.selectedItem = tabBar.items?[next]
            setWebTab(index: next)
        }
    }

    // MARK: - iPhone Duo sidebar (build 63)

    // The sidebar is a vertical floating glass capsule on the right
    // edge, vertically centered, with the same 5 tabs in the same
    // order as the bottom tab bar (transfer, map, stations, timetable,
    // more), each as a button with its icon above its label — the
    // effect in the user's iPhone Duo screenshot. It appears ONLY on
    // a wide iPhone (Duo unfolded); iPad and narrow iPhone keep the
    // bottom floating tab bar. Content is never covered: when the
    // sidebar is active the web view's trailing edge moves to the
    // sidebar's leading edge (minus 8pt), so the web reflows into the
    // space left of it.
    func setupSideBar() {
        sideBar = UIView()
        sideBar.translatesAutoresizingMaskIntoConstraints = false
        sideBar.layer.cornerRadius = 32
        sideBar.clipsToBounds = true
        sideBar.isHidden = true
        view.addSubview(sideBar)

        // Single glass layer: the capsule's own Liquid Glass
        // (UIGlassEffect on iOS 26+, frosted material below). The
        // buttons inside are PLAIN — not glass() — or the glass would
        // stack twice (the build-50 double-glass bug the user
        // rejected: "为啥有玻璃重复"). The selected item is highlighted
        // with the city accent instead.
        sideBarEffectView = makeGlassEffectView()
        sideBarEffectView.translatesAutoresizingMaskIntoConstraints = false
        sideBar.addSubview(sideBarEffectView)
        NSLayoutConstraint.activate([
            sideBarEffectView.leadingAnchor.constraint(equalTo: sideBar.leadingAnchor),
            sideBarEffectView.trailingAnchor.constraint(equalTo: sideBar.trailingAnchor),
            sideBarEffectView.topAnchor.constraint(equalTo: sideBar.topAnchor),
            sideBarEffectView.bottomAnchor.constraint(equalTo: sideBar.bottomAnchor),
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .fill
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        sideBarEffectView.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sideBarEffectView.contentView.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: sideBarEffectView.contentView.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: sideBarEffectView.contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: sideBarEffectView.contentView.bottomAnchor, constant: -10),
        ])

        let titles = [L("tab.transfer"), L("tab.map"), L("tab.stations"), L("tab.timetable"), L("tab.more")]
        let images: [UIImage?] = [
            UIImage(systemName: "arrow.triangle.2.circlepath"),
            UIImage(systemName: "map"),
            UIImage(systemName: "magnifyingglass"),
            UIImage(named: "TimetableIcon"),
            UIImage(systemName: "gearshape"),
        ]
        for i in 0..<tabKeys.count {
            let btn = UIButton(type: .system)
            btn.tag = i
            btn.configuration = sideBarButtonConfig(title: titles[i], image: images[i], selected: i == 1)
            btn.addTarget(self, action: #selector(sideBarButtonTapped(_:)), for: .touchUpInside)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.heightAnchor.constraint(equalToConstant: 52).isActive = true
            stack.addArrangedSubview(btn)
            sideBarButtons.append(btn)
        }

        NSLayoutConstraint.activate([
            sideBar.widthAnchor.constraint(equalToConstant: 64),
            sideBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            sideBar.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // Sidebar button: plain configuration (see setupSideBar — the
    // glass lives in the container, not in the buttons). Icon above
    // label; selected = city accent icon + title on a faint accent
    // wash, unselected = default label colour on clear.
    func sideBarButtonConfig(title: String, image: UIImage?, selected: Bool) -> UIButton.Configuration {
        var cfg = UIButton.Configuration.plain()
        cfg.title = title
        cfg.image = image
        cfg.imagePlacement = .top
        cfg.imagePadding = 4
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 2, bottom: 6, trailing: 2)
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
            return a
        }
        cfg.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        cfg.baseForegroundColor = selected ? accentColor() : .label
        var bg = UIBackgroundConfiguration.clear()
        bg.backgroundColor = selected ? accentColor().withAlphaComponent(0.15) : .clear
        bg.cornerRadius = 10
        cfg.background = bg
        return cfg
    }

    // Wide iPhone = Duo unfolded (also a large iPhone in landscape,
    // which is acceptable adaptive behaviour). iPad never gets the
    // sidebar — it keeps the bottom floating tab bar.
    func sideBarShouldShow() -> Bool {
        return UIDevice.current.userInterfaceIdiom == .phone && view.bounds.width >= 700
    }

    // Switch between sidebar (wide iPhone) and bottom tab bar
    // (narrow / iPad). Idempotent: constraint toggling only runs when
    // the mode actually changes; visibility is re-asserted every time
    // (it also follows the splash gate, same as the tab bar).
    func updateSideBarLayout() {
        guard sideBar != nil else { return }
        let show = sideBarShouldShow()
        if show != sideBarActive {
            sideBarActive = show
            if show {
                webViewTrailingToView.isActive = false
                webViewTrailingToSideBar.isActive = true
            } else {
                webViewTrailingToSideBar.isActive = false
                webViewTrailingToView.isActive = true
            }
        }
        tabBar.isHidden = show || splashShowing
        sideBar.isHidden = !show || splashShowing
        updateSideBarSelection()
    }

    // Keep the sidebar's selected highlight in sync with currentTab
    // (and with the city accent). Called by updateSideBarLayout,
    // setWebTab, the tabChanged handler and refreshCityUI.
    func updateSideBarSelection() {
        guard !sideBarButtons.isEmpty else { return }
        let idx = tabKeys.firstIndex(of: currentTab) ?? 1
        let titles = [L("tab.transfer"), L("tab.map"), L("tab.stations"), L("tab.timetable"), L("tab.more")]
        let images: [UIImage?] = [
            UIImage(systemName: "arrow.triangle.2.circlepath"),
            UIImage(systemName: "map"),
            UIImage(systemName: "magnifyingglass"),
            UIImage(named: "TimetableIcon"),
            UIImage(systemName: "gearshape"),
        ]
        for (i, btn) in sideBarButtons.enumerated() {
            btn.configuration = sideBarButtonConfig(title: titles[i], image: images[i], selected: i == idx)
        }
    }

    // Tapping a sidebar item switches tabs exactly like tapping the
    // bottom tab bar item (same setWebTab path); the hidden tab bar's
    // selectedItem is kept in sync so folding back to narrow shows
    // the right tab selected.
    @objc func sideBarButtonTapped(_ sender: UIButton) {
        let idx = sender.tag
        guard idx >= 0 && idx < tabKeys.count else { return }
        tabBar.selectedItem = tabBar.items?[idx]
        setWebTab(index: idx)
    }

    // MARK: - Live Activity (build 65)

    // The running Live Activity for the current trip, if any. Stored
    // type-erased as Any: Activity<TripAttributes> is iOS 16.1+ only,
    // so it cannot be a stored-property type on this iOS 16.0 class.
    // Cast back inside `if #available(iOS 16.2, *)` wherever it is
    // used. ActivityKit is weak-linked in build.sh.
    var tripActivity: Any?

    // Handle the web's liveActivity posts:
    // {action: 'start'|'update'|'end', from, to, line, themeHex,
    //  totalStops, minutes, nextStation, remainingStops, arrivalMs}.
    // The web computes the route + progress; native owns the ActivityKit
    // activity. Never crashes and never starts a stale activity: a
    // payload missing from/to or the route data is ignored.
    func handleLiveActivity(_ dict: [String: Any]) {
        guard #available(iOS 16.1, *) else { return }
        let action = dict["action"] as? String ?? ""
        switch action {
        case "start":
            startTripActivity(dict)
        case "update":
            updateTripActivity(dict)
        case "end":
            endTripActivity()
        default:
            break
        }
    }

    // City theme colour as a 6-digit hex string (matches the app theme).
    func themeHex() -> String {
        switch currentCity {
        case "sy": return "D4B686"
        case "sh": return "E60012"
        case "hb": return "C00030"
        case "dl": return "0D579A"
        case "jh": return "D8273D"
        default: return "003380"
        }
    }

    func startTripActivity(_ dict: [String: Any]) {
        guard #available(iOS 16.2, *) else { return }
        guard let from = dict["from"] as? String, !from.isEmpty,
              let to = dict["to"] as? String, !to.isEmpty,
              let next = dict["nextStation"] as? String,
              let remaining = dict["remainingStops"] as? Int,
              let arrivalMs = dict["arrivalMs"] as? Double else { return }
        let line = dict["line"] as? String ?? ""
        let totalStops = dict["totalStops"] as? Int ?? 0
        let theme = dict["themeHex"] as? String ?? themeHex()
        let arrival = Date(timeIntervalSince1970: arrivalMs / 1000)
        // End any running activity first (never two at once).
        if let old = tripActivity as? Activity<TripAttributes> {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
            tripActivity = nil
        }
        let attrs = TripAttributes(
            fromName: from, toName: to, lineName: line,
            themeHex: theme, totalStops: totalStops,
            nextLabel: L("live.next"),
            stopsFormat: L("live.stopsLeft"),
            tripLabel: L("live.trip"),
            arrivedLabel: L("live.arrived")
        )
        let state = TripAttributes.ContentState(
            nextStation: next, remainingStops: remaining,
            arrivalDate: arrival, status: "active"
        )
        do {
            let activity = try Activity<TripAttributes>.request(
                attributes: attrs,
                content: .init(state: state, staleDate: arrival),
                pushType: nil
            )
            tripActivity = activity
        } catch {
            // Live Activities disabled for this app, or the system
            // refused: fail silently (the in-app trip UI still works).
            tripActivity = nil
        }
    }

    func updateTripActivity(_ dict: [String: Any]) {
        guard #available(iOS 16.2, *) else { return }
        guard let activity = tripActivity as? Activity<TripAttributes>,
              let next = dict["nextStation"] as? String,
              let remaining = dict["remainingStops"] as? Int,
              let arrivalMs = dict["arrivalMs"] as? Double else { return }
        let arrival = Date(timeIntervalSince1970: arrivalMs / 1000)
        let state = TripAttributes.ContentState(
            nextStation: next, remainingStops: remaining,
            arrivalDate: arrival, status: "active"
        )
        Task { await activity.update(.init(state: state, staleDate: arrival)) }
    }

    func endTripActivity() {
        guard #available(iOS 16.2, *) else { return }
        guard let activity = tripActivity as? Activity<TripAttributes> else { return }
        tripActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: - Web page -> native tab bar

    // The web page posts its current tab whenever setTab runs, so the
    // native bar stays selected on the tab the page is actually showing
    // (e.g. when the user opens station search from the search pill).
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "tabChanged",
           let tab = message.body as? String,
           let idx = tabKeys.firstIndex(of: tab) {
            currentTab = tab
            updatePillVisibility()
            updateTransferVisibility()
            tabBar.selectedItem = tabBar.items?[idx]
            updateSideBarSelection()
        } else if message.name == "cityMenu" {
            presentCityMenuPopover()
        } else if message.name == "splashDone" {
            splashFinished()
        } else if message.name == "cityChanged",
                  let dict = message.body as? [String: Any],
                  let city = dict["city"] as? String,
                  ["bj", "sy", "sh", "hb", "dl", "jh", "cz", "cq"].contains(city) {
            // The web switched cities (user switch or the startup
            // restore). Mirror it natively; the web already switched,
            // so do NOT call switchCity here (that would loop).
            UserDefaults.standard.set(city, forKey: "metro-city")
            if city != currentCity {
                currentCity = city
                refreshCityUI()
            }
        } else if message.name == "langChanged",
                  let dict = message.body as? [String: Any],
                  let lang = dict["lang"] as? String {
            // The web switched languages (settings picker or the startup
            // restore). Mirror it natively; the web already switched, so
            // do NOT call setLang on the web here (that would loop).
            setLang(lang)
        } else if message.name == "tabsFrame",
                  let dict = message.body as? [String: Any] {
            placeSortTabs(frame: dict)
        } else if message.name == "transferFrame",
                  let dict = message.body as? [String: Any] {
            placeTransfer(frame: dict)
        } else if message.name == "themeFrame",
                  let dict = message.body as? [String: Any] {
            placeThemeButtons(frame: dict)
        } else if message.name == "stationPicked",
                  let dict = message.body as? [String: Any] {
            // The user tapped a web suggestion row: mirror the picked
            // station + line into the native field and dismiss the
            // keyboard (the web already set its own state).
            let which = dict["which"] as? String ?? "from"
            let name = dict["name"] as? String ?? ""
            let line = dict["line"] as? [String: Any]
            if which == "from" {
                fromField.text = name
                applyBadge(which: "from", line: line)
            } else {
                toField.text = name
                applyBadge(which: "to", line: line)
            }
            updateClearButtons()
            view.endEditing(true)
        } else if message.name == "timePicker",
                  let dict = message.body as? [String: Any] {
            let current = dict["departTime"] as? String
            presentTimePicker(current: current)
        } else if message.name == "openTransitApp" {
            openTransitApp()
        } else if message.name == "openRideCode",
                  let dict = message.body as? [String: Any] {
            openRideCode(link: dict["link"] as? String ?? "#小程序://乘车码/cZxzR2rsEppAxSv")
        } else if message.name == "requestLocation" {
            requestNearbyLocation()
        } else if message.name == "liveActivity",
                  let dict = message.body as? [String: Any] {
            handleLiveActivity(dict)
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "canGoBack" {
            backButton.isHidden = !webView.canGoBack
        }
    }

    deinit {
        webView.removeObserver(self, forKeyPath: "canGoBack")
    }

    // window.open() and target=_blank links have no target frame:
    // open them in this web view instead of dropping them.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if url.isFileURL {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: url))
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
