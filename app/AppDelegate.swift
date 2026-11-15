import UIKit
import WebKit

// 北京市轨道交通线路配置图 (SierraQin/metro, CC0 1.0)
// Minimal shell: a full-screen WKWebView loading the bundled offline page.
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

class MapViewController: UIViewController, WKNavigationDelegate {
    var webView: WKWebView!
    var backButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        webView = WKWebView(frame: view.bounds, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.allowsBackForwardNavigationGestures = true
        view.addSubview(webView)

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
            backButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
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
