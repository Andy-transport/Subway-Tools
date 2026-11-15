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
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = MapViewController()
        window?.makeKeyAndVisible()
        return true
    }
}

class MapViewController: UIViewController, WKNavigationDelegate, UITabBarDelegate, WKScriptMessageHandler {
    var webView: WKWebView!
    var backButton: UIButton!
    var tabBar: UITabBar!
    var cityPill: UIButton!
    var searchPill: UIButton!
    // Web tab keys, in the same order as the native tab bar items.
    let tabKeys = ["transfer", "map", "stations", "more"]
    // Beijing Subway blue (Beijing theme, unchanged); Shenyang gold,
    // sampled from the user's gold image: #D4B686 (champagne gold).
    let subwayBlue = UIColor(red: 0, green: 51.0 / 255.0, blue: 128.0 / 255.0, alpha: 1)
    let shenyangGold = UIColor(red: 212.0 / 255.0, green: 182.0 / 255.0, blue: 134.0 / 255.0, alpha: 1)
    let shenyangGoldDark = UIColor(red: 138.0 / 255.0, green: 109.0 / 255.0, blue: 43.0 / 255.0, alpha: 1)
    var currentCity = "bj"
    var currentTab = "map"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "tabChanged")
        config.userContentController.add(self, name: "cityMenu")
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
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
            backButton.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -16),
        ])

        setupNativePills()
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
        return currentCity == "sy" ? shenyangGold : subwayBlue
    }

    // Darker accent for text/borders on light backgrounds (legibility):
    // subway blue in Beijing, deep gold #8a6d2b in Shenyang.
    func accentDark() -> UIColor {
        return currentCity == "sy" ? shenyangGoldDark : subwayBlue
    }

    func cityLogoImage() -> UIImage? {
        let name = currentCity == "sy" ? "ShenyangLogo" : "BeijingLogo"
        guard let img = UIImage(named: name) else { return nil }
        let size = CGSize(width: 26, height: 26)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func updateCityPill() {
        let name = currentCity == "sy" ? "沈阳" : "北京"
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
        return UIMenu(title: "", children: [bj, sy])
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
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.modalPresentationStyle = .popover
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = cityPill.frame
            pop.permittedArrowDirections = .up
        }
        present(sheet, animated: true)
    }

    func pickCity(_ city: String) {
        guard city != currentCity else { return }
        currentCity = city
        tabBar.tintColor = accentColor()
        backButton.layer.borderColor = accentDark().cgColor
        backButton.setTitleColor(accentDark(), for: .normal)
        updateCityPill()
        updateSearchPill()
        webView.evaluateJavaScript("window.metroApp && window.metroApp.switchCity('\(city)')", completionHandler: nil)
    }

    @objc func openStationSearch() {
        webView.evaluateJavaScript("window.metroApp && window.metroApp.openStations()", completionHandler: nil)
    }

    func updatePillVisibility() {
        let show = currentTab == "map"
        cityPill.isHidden = !show
        searchPill.isHidden = !show
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
            tabBar.selectedItem = tabBar.items?[idx]
        } else if message.name == "cityMenu" {
            presentCityMenuPopover()
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
