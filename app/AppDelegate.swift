import UIKit
import WebKit

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

class MapViewController: UIViewController, WKNavigationDelegate, UITabBarDelegate, WKScriptMessageHandler, UITextFieldDelegate {
    var webView: WKWebView!
    var backButton: UIButton!
    var tabBar: UITabBar!
    var cityPill: UIButton!
    var searchPill: UIButton!
    // Native Liquid Glass route-sort tabs (build 33): a UISegmentedControl
    // (Liquid Glass on iOS 26+) overlaid on the web panel's tab row.
    var sortTabs: UISegmentedControl!
    let sortTabKeys = ["rec", "early", "fewest", "cheap"]
    // Native Apple UI Liquid Glass dark-mode picker (build 44): a
    // UISegmentedControl (跟随系统/浅色/深色) overlaid on the settings
    // panel's .more-theme-seg row, same pattern as sortTabs.
    var themeSeg: UISegmentedControl!
    let themeSegKeys = ["system", "light", "dark"]
    // Native Liquid Glass transfer input area (build 37): a glass card
    // holding the two station text fields + swap button, and a glass
    // 搜索 button, overlaid on the web panel's .tr-fields / .tr-search
    // rows (frame-positioned from the web, like sortTabs). The web
    // suggestion dropdown stays web and appears below the card.
    var transferCard: UIView!
    var transferEffectView: UIVisualEffectView!
    var transferTintView: UIView!
    var transferSwapButton: UIButton!
    var transferSearchButton: UIButton!
    var fromField: UITextField!
    var toField: UITextField!
    var fromBadge: UIButton!
    var toBadge: UIButton!
    var fromClear: UIButton!
    var toClear: UIButton!
    // Line info currently shown in each field's badge, as
    // {name, color, text} (hex strings from the web); nil = no badge.
    var fromLineInfo: [String: Any]?
    var toLineInfo: [String: Any]?
    // Web tab keys, in the same order as the native tab bar items.
    let tabKeys = ["transfer", "map", "stations", "more"]
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
    var currentCity = "bj"
    var currentTab = "map"

    override func viewDidLoad() {
        super.viewDidLoad()
        // Restore the last-used city (build 37): relaunch opens on
        // the city the user last switched to (written by pickCity
        // and by the web's cityChanged post; default Beijing).
        // Must run before any accentColor()/pill setup below.
        if let saved = UserDefaults.standard.string(forKey: "metro-city"),
           ["bj", "sy", "sh"].contains(saved) {
            currentCity = saved
        }
        view.backgroundColor = .white

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "tabChanged")
        config.userContentController.add(self, name: "cityMenu")
        config.userContentController.add(self, name: "tabsFrame")
        config.userContentController.add(self, name: "transferFrame")
        config.userContentController.add(self, name: "themeFrame")
        config.userContentController.add(self, name: "stationPicked")
        config.userContentController.add(self, name: "timePicker")
        config.userContentController.add(self, name: "openTransitApp")
        config.userContentController.add(self, name: "cityChanged")
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
            UITabBarItem(title: "换乘", image: UIImage(systemName: "arrow.triangle.2.circlepath"), tag: 0),
            UITabBarItem(title: "配线图", image: UIImage(systemName: "map"), tag: 1),
            UITabBarItem(title: "搜索", image: UIImage(systemName: "magnifyingglass"), tag: 2),
            UITabBarItem(title: "设置", image: UIImage(systemName: "gearshape"), tag: 3),
        ]
        tabBar.items = items
        tabBar.selectedItem = items[1] // default tab is the map, same as the web page
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabBar)
        // iPad (user 2026-11-15): the tab bar moves to the TOP; iPhone
        // keeps it at the bottom. The top pills move below the bar on
        // iPad so they do not overlap it (see setupNativePills).
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            isPad ? tabBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
                  : tabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
            // iPad: the tab bar is at the top, so the back button sits
            // below it; iPhone: it sits above the bottom tab bar.
            isPad ? backButton.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 16)
                  : backButton.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -16),
        ])

        setupNativePills()
        setupSortTabs()
        setupThemeSeg()
        setupTransferControls()
        webView.addObserver(self, forKeyPath: "canGoBack", options: .new, context: nil)
        loadMap()
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
        // iPad: the tab bar is at the top, so the pills sit below it;
        // iPhone: the pills sit at the top safe area as before.
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        NSLayoutConstraint.activate([
            cityPill.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            cityPill.topAnchor.constraint(equalTo: isPad ? tabBar.bottomAnchor : view.safeAreaLayoutGuide.topAnchor, constant: 10),
            searchPill.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            searchPill.topAnchor.constraint(equalTo: isPad ? tabBar.bottomAnchor : view.safeAreaLayoutGuide.topAnchor, constant: 10),
        ])
        searchPill.addTarget(self, action: #selector(openStationSearch), for: .touchUpInside)
        updateCityPill()
        updateSearchPill()
        updatePillVisibility()
    }

    func accentColor() -> UIColor {
        if currentCity == "sy" { return shenyangGold }
        if currentCity == "sh" { return shanghaiRed }
        return subwayBlue
    }

    // Darker accent for text/borders on light backgrounds (legibility):
    // subway blue in Beijing, deep gold #8a6d2b in Shenyang.
    func accentDark() -> UIColor {
        if currentCity == "sy" { return shenyangGoldDark }
        if currentCity == "sh" { return shanghaiRedDark }
        return subwayBlue
    }

    // Search button colour: red in Shenyang, gold in Shanghai (user asked
    // for 沈阳 red / 上海 gold on the 搜索 button), city accent elsewhere
    // (Beijing blue).
    func searchButtonColor() -> UIColor {
        if currentCity == "sy" { return shenyangRed }
        if currentCity == "sh" { return shanghaiGold }
        return accentColor()
    }

    func cityLogoImage() -> UIImage? {
        let name: String
        switch currentCity {
        case "sy": name = "ShenyangLogo"
        case "sh": name = "ShanghaiLogo"
        default: name = "BeijingLogo"
        }
        guard let img = UIImage(named: name) else { return nil }
        let size = CGSize(width: 26, height: 26)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func updateCityPill() {
        let name: String
        switch currentCity {
        case "sy": name = "沈阳"
        case "sh": name = "上海"
        default: name = "北京"
        }
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
            config.title = "搜车站"
            config.image = UIImage(systemName: "magnifyingglass")
            config.imagePadding = 6
            config.baseForegroundColor = accentColor()
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 14)
            searchPill.configuration = config
        } else {
            searchPill.setTitle("搜车站", for: .normal)
            searchPill.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
            searchPill.setTitleColor(accentColor(), for: .normal)
            searchPill.backgroundColor = UIColor(white: 1, alpha: 0.72)
            searchPill.layer.cornerRadius = 18
            searchPill.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 14)
        }
    }

    func cityMenu() -> UIMenu {
        let bj = UIAction(title: "北京", state: currentCity == "bj" ? .on : .off) { [weak self] _ in
            self?.pickCity("bj")
        }
        let sy = UIAction(title: "沈阳", state: currentCity == "sy" ? .on : .off) { [weak self] _ in
            self?.pickCity("sy")
        }
        let sh = UIAction(title: "上海", state: currentCity == "sh" ? .on : .off) { [weak self] _ in
            self?.pickCity("sh")
        }
        return UIMenu(title: "", children: [bj, sy, sh])
    }

    // The transfer panel's city row (web) also asks for the city menu:
    // show it as a native action sheet in a popover anchored to the
    // city pill (top-left), never in the middle of the screen.
    func presentCityMenuPopover() {
        let sheet = UIAlertController(title: "切换城市", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: currentCity == "bj" ? "✓ 北京" : "北京", style: .default) { [weak self] _ in
            self?.pickCity("bj")
        })
        sheet.addAction(UIAlertAction(title: currentCity == "sy" ? "✓ 沈阳" : "沈阳", style: .default) { [weak self] _ in
            self?.pickCity("sy")
        })
        sheet.addAction(UIAlertAction(title: currentCity == "sh" ? "✓ 上海" : "上海", style: .default) { [weak self] _ in
            self?.pickCity("sh")
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
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
        sortTabs = UISegmentedControl(items: ["推荐", "耗时最短", "路径最短", "节省票价"])
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
            sortTabs.frame = CGRect(x: x, y: y, width: w, height: h)
            sortTabs.isHidden = false
            if let idx = sortTabKeys.firstIndex(of: tab) {
                sortTabs.selectedSegmentIndex = idx
            }
        } else {
            sortTabs.isHidden = true
        }
    }

    // MARK: - Native Apple UI dark-mode picker (build 44)

    // The 深色模式 picker (跟随系统/浅色/深色) is a native
    // UISegmentedControl (Liquid Glass on iOS 26+), overlaid on the
    // settings panel's .more-theme-seg row — same pattern as sortTabs.
    // The web hides its own row in the native app and reports the frame.
    func setupThemeSeg() {
        themeSeg = UISegmentedControl(items: ["跟随系统", "浅色", "深色"])
        themeSeg.selectedSegmentIndex = 0
        themeSeg.translatesAutoresizingMaskIntoConstraints = true
        themeSeg.isHidden = true
        themeSeg.addTarget(self, action: #selector(themeSegChanged(_:)), for: .valueChanged)
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14, weight: .semibold)]
        themeSeg.setTitleTextAttributes(attrs, for: .normal)
        themeSeg.setTitleTextAttributes(attrs, for: .selected)
        view.addSubview(themeSeg)
    }

    @objc func themeSegChanged(_ sender: UISegmentedControl) {
        let idx = sender.selectedSegmentIndex
        guard idx >= 0 && idx < themeSegKeys.count else { return }
        let key = themeSegKeys[idx]
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setTheme('\(key)')", completionHandler: nil)
    }

    // Place the native dark-mode picker over the web row's reported
    // frame. A zero-size rect (settings panel not shown) hides it.
    func placeThemeSeg(frame dict: [String: Any]) {
        let x = (dict["x"] as? Double) ?? 0
        let y = (dict["y"] as? Double) ?? 0
        let w = (dict["width"] as? Double) ?? 0
        let h = (dict["height"] as? Double) ?? 0
        let theme = dict["theme"] as? String ?? ""
        if w > 0 && h > 0 && currentTab == "more" {
            themeSeg.frame = CGRect(x: x, y: y, width: w, height: h)
            themeSeg.isHidden = false
            if let idx = themeSegKeys.firstIndex(of: theme) {
                themeSeg.selectedSegmentIndex = idx
            }
        } else {
            themeSeg.isHidden = true
        }
    }

    // MARK: - Native Liquid Glass transfer input area (build 37)

    // The from/to fields card and the 搜索 button are native Liquid
    // Glass controls overlaid on the web panel's .tr-fields / .tr-search
    // rows (the web hides its own rows in the native app and reports
    // their frames, like the sort tabs). The suggestion dropdown stays
    // web: it renders below the hidden fields card, i.e. directly
    // below this native card. The faint tint follows the city
    // accent (Beijing blue / Shenyang gold / Shanghai red). The card
    // is a UIVisualEffectView with
    // UIGlassEffect on iOS 26+ (frosted systemMaterial below) plus a
    // faint accent tint overlay; the search button uses
    // UIButton.Configuration.glass() like the top pills.
    func setupTransferControls() {
        // Card container (frame-positioned from the web .tr-fields rect).
        transferCard = UIView()
        transferCard.layer.cornerRadius = 20
        transferCard.clipsToBounds = true
        transferCard.isHidden = true
        view.addSubview(transferCard)

        transferEffectView = makeGlassEffectView()
        transferEffectView.translatesAutoresizingMaskIntoConstraints = false
        transferCard.addSubview(transferEffectView)
        NSLayoutConstraint.activate([
            transferEffectView.leadingAnchor.constraint(equalTo: transferCard.leadingAnchor),
            transferEffectView.trailingAnchor.constraint(equalTo: transferCard.trailingAnchor),
            transferEffectView.topAnchor.constraint(equalTo: transferCard.topAnchor),
            transferEffectView.bottomAnchor.constraint(equalTo: transferCard.bottomAnchor),
        ])

        let content = transferEffectView.contentView
        transferTintView = UIView()
        transferTintView.backgroundColor = accentColor().withAlphaComponent(0.10)
        transferTintView.isUserInteractionEnabled = false
        transferTintView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(transferTintView)
        NSLayoutConstraint.activate([
            transferTintView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            transferTintView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            transferTintView.topAnchor.constraint(equalTo: content.topAnchor),
            transferTintView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Two rows: dot + label + text field + line badge + clear.
        fromField = makeTransferField(tag: 0, placeholder: "选择出发站")
        toField = makeTransferField(tag: 1, placeholder: "选择到达站")
        fromBadge = makeTransferBadge(tag: 0)
        toBadge = makeTransferBadge(tag: 1)
        fromClear = makeTransferClear(tag: 0)
        toClear = makeTransferClear(tag: 1)
        let fromRow = makeTransferRow(dotColor: UIColor(red: 34.0 / 255.0, green: 160.0 / 255.0, blue: 107.0 / 255.0, alpha: 1),
                                      labelTitle: "出发", labelTag: 0,
                                      field: fromField, badge: fromBadge, clear: fromClear)
        let toRow = makeTransferRow(dotColor: UIColor(red: 229.0 / 255.0, green: 72.0 / 255.0, blue: 77.0 / 255.0, alpha: 1),
                                    labelTitle: "到达", labelTag: 1,
                                    field: toField, badge: toBadge, clear: toClear)
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
        let done = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(dismissTransferKeyboard))
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
            transferCard.frame = CGRect(x: fx, y: fy, width: fw, height: fh)
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
            transferSearchButton.frame = CGRect(x: sx, y: sy, width: sw, height: sh)
            transferSearchButton.isHidden = false
            transferSearchButton.layer.cornerRadius = sh / 2
            // Refresh the button colour here too (build 43): the colour
            // is set from currentCity, and placeTransfer runs every time
            // the web reports the frame (city switch, scroll, layout),
            // so the red/gold is always re-applied when the button shows.
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
            themeSeg.isHidden = true
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
        transferTintView.backgroundColor = accentColor().withAlphaComponent(0.10)
        transferSwapButton.layer.borderColor = accentDark().cgColor
        transferSwapButton.tintColor = accentDark()
        updateTransferSearchStyle()
    }

    func updateTransferSearchStyle() {
        // Filled (solid) city colour (build 44): the glass configuration
        // never showed the colour — UIButton.Configuration.glass() ignored
        // baseBackgroundColor (and tintColor) on iOS 27.2, so the button
        // stayed the default blue in Shenyang/Shanghai through builds 42
        // and 43 ("按钮还是没改"). A filled button renders the exact city
        // colour: Shenyang red / Shanghai gold / Beijing blue. Still a
        // native Apple UIButton (capsule, bold white title).
        var config = UIButton.Configuration.filled()
        config.title = "搜索"
        config.baseForegroundColor = .white
        config.baseBackgroundColor = searchButtonColor()
        config.cornerStyle = .capsule
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = UIFont.systemFont(ofSize: 17, weight: .bold)
            return out
        }
        transferSearchButton.configuration = config
        transferSearchButton.tintColor = searchButtonColor()
        transferSearchButton.backgroundColor = searchButtonColor()
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
        let show = currentTab == "map"
        cityPill.isHidden = !show
        searchPill.isHidden = !show
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
        picker.locale = Locale(identifier: "zh_CN")
        if let t = current {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            if let d = fmt.date(from: t) { picker.date = d }
        }
        picker.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(picker)

        let nowButton = UIButton(type: .system)
        nowButton.setTitle("现在出发", for: .normal)
        nowButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        nowButton.setTitleColor(accentDark(), for: .normal)
        nowButton.addTarget(self, action: #selector(timePickerNow), for: .touchUpInside)
        nowButton.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(nowButton)

        let doneButton = UIButton(type: .system)
        doneButton.setTitle("确定", for: .normal)
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
    // Shengjing Tong 1441271928, Shanghai Metro大都会 1202750238. There
    // is no confirmed URL scheme for any of these apps, so the App Store
    // page (not a guessed scheme) is the link.
    func openTransitApp() {
        let id: String
        switch currentCity {
        case "sy": id = "1441271928"
        case "sh": id = "1202750238"
        default: id = "1071038870"
        }
        guard let url = URL(string: "https://apps.apple.com/cn/app/id\(id)") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
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
        } else if message.name == "cityMenu" {
            presentCityMenuPopover()
        } else if message.name == "cityChanged",
                  let dict = message.body as? [String: Any],
                  let city = dict["city"] as? String,
                  ["bj", "sy", "sh"].contains(city) {
            // The web switched cities (user switch or the startup
            // restore). Mirror it natively; the web already switched,
            // so do NOT call switchCity here (that would loop).
            UserDefaults.standard.set(city, forKey: "metro-city")
            if city != currentCity {
                currentCity = city
                refreshCityUI()
            }
        } else if message.name == "tabsFrame",
                  let dict = message.body as? [String: Any] {
            placeSortTabs(frame: dict)
        } else if message.name == "transferFrame",
                  let dict = message.body as? [String: Any] {
            placeTransfer(frame: dict)
        } else if message.name == "themeFrame",
                  let dict = message.body as? [String: Any] {
            placeThemeSeg(frame: dict)
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
