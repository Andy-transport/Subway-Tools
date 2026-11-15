import UIKit
import WebKit

// 北京市轨道交通线路配置图 (SierraQin/metro, CC0 1.0)
// Shell: a full-screen WKWebView loading the bundled offline page,
// plus a native UITabBar (iOS 27 SDK) at the bottom. The web page's own
// tab bar is hidden; the native bar drives the web UI via JavaScript,
// and the web page reports its current tab back so the two stay in sync.
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
    // Web tab keys, in the same order as the native tab bar items.
    let tabKeys = ["transfer", "map", "stations", "more"]
    // Beijing Subway blue, used for the selected tab.
    let subwayBlue = UIColor(red: 0, green: 51.0 / 255.0, blue: 128.0 / 255.0, alpha: 1)

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

        // Native tab bar (UITabBar, iOS 27 SDK). The web page hides its own
        // tab bar; this bar is the only one the user sees.
        tabBar = UITabBar()
        tabBar.delegate = self
        tabBar.tintColor = subwayBlue
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
        backButton.layer.borderColor = UIColor(red: 0, green: 0.2, blue: 0.5, alpha: 1).cgColor
        backButton.setTitleColor(UIColor(red: 0, green: 0.2, blue: 0.5, alpha: 1), for: .normal)
        backButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.isHidden = true
        view.addSubview(backButton)
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            backButton.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -16),
        ])

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

    // MARK: - Native tab bar -> web page

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        setWebTab(index: item.tag)
    }

    func setWebTab(index: Int) {
        guard index >= 0 && index < tabKeys.count else { return }
        let key = tabKeys[index]
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
            tabBar.selectedItem = tabBar.items?[idx]
            return
        }
        if message.name == "cityMenu" {
            var current = "bj"
            if let body = message.body as? [String: Any], let c = body["city"] as? String {
                current = c
            } else if let c = message.body as? String {
                current = c
            }
            showCityMenu(current: current)
        }
    }

    // MARK: - Native city menu

    // Tapping the city pill asks the native side to show an Apple-native
    // action sheet (UIAlertController, .actionSheet, SDK 26.5) to pick the
    // city. The web page falls back to a plain toggle when the native
    // handler is absent (e.g. the offline page opened in a browser).
    func showCityMenu(current: String) {
        let sheet = UIAlertController(title: "切换城市", message: nil, preferredStyle: .actionSheet)
        let bj = UIAlertAction(title: current == "bj" ? "✓ 北京" : "北京", style: .default) { [weak self] _ in
            self?.webView.evaluateJavaScript("window.metroApp && window.metroApp.switchCity('bj')", completionHandler: nil)
        }
        let sy = UIAlertAction(title: current == "sy" ? "✓ 沈阳" : "沈阳", style: .default) { [weak self] _ in
            self?.webView.evaluateJavaScript("window.metroApp && window.metroApp.switchCity('sy')", completionHandler: nil)
        }
        sheet.addAction(bj)
        sheet.addAction(sy)
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        // iPad popover anchor (the app is iPhone-only, but this keeps the
        // sheet from crashing if it is ever presented on iPad).
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        present(sheet, animated: true, completion: nil)
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
