import UIKit
import SwiftUI
import Combine

// MARK: - Native Settings hosting (Settings tab -> SwiftUI, SDK 27.2)
//
// How the Settings tab works after this change:
//  * The system UITabBar is untouched (same bar, same items, same
//    Liquid Glass). Tapping 设置 no longer calls the web's setTab('more')
//    — the web's #moreSheet is never shown. Instead the native
//    SettingsHostingController is added as a child view and the WKWebView
//    is hidden underneath (it stays loaded, so every evaluateJavaScript
//    bridge call still works; it simply paints nothing while hidden).
//  * The other four tabs are untouched: leaving 设置 removes the hosted
//    controller, unhides the web view, and setWebTab() proceeds to call
//    the web's setTab(newKey) exactly as before.
//  * Layout (native_fullscreen_gating_pages skill): the hosted view
//    never relies on the area under a native bar —
//      iPhone: top = safe area top, bottom = tab bar top - 8;
//      iPad:   top = tab bar (top capsule) bottom + 8, bottom = safe area bottom;
//      Duo unfolded (sideBarActive): trailing = sidebar leading - 8,
//      otherwise trailing = safe area trailing.
//    Constraints are re-applied in viewDidLayoutSubviews, so a fold /
//    unfold / rotation re-lays the page instead of leaving it under a bar.
//  * Theme: the hosting controller's overrideUserInterfaceStyle follows
//    the store's theme (system -> .unspecified, light -> .light,
//    dark -> .dark), so the SwiftUI page follows the app's theme choice,
//    not only the system appearance. This is scoped to the Settings
//    page; other native chrome keeps its existing behaviour.
//  * The native Appearance/Language pickers (presentAppearance /
//    presentLanguage) are dismissed before the Settings page presents,
//    and the web-only overlays that belong to the web Settings page
//    (nearbySmart UISwitch, dormant theme buttons, struct chrome,
//    sub-view back button) are hidden while it is up.

final class SettingsHostingController: UIViewController {
    let store: SettingsStore
    private var hosting: UIHostingController<AnyView>?
    private var activeConstraints: [NSLayoutConstraint] = []
    private var cancellables = Set<AnyCancellable>()

    init(store: SettingsStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let root = AnyView(NavigationStack { SettingsHomeView().environmentObject(store) })
        let hc = UIHostingController(rootView: root)
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        hc.view.backgroundColor = .systemBackground
        addChild(hc)
        view.addSubview(hc.view)
        hc.didMove(toParent: self)
        hosting = hc
        applyThemeOverride()
        // Follow theme changes made inside the Settings page itself.
        store.$theme
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyThemeOverride() }
            .store(in: &cancellables)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayoutConstraints()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateLayoutConstraints()
    }

    private func applyThemeOverride() {
        switch store.theme {
        case "light": overrideUserInterfaceStyle = .light
        case "dark": overrideUserInterfaceStyle = .dark
        default: overrideUserInterfaceStyle = .unspecified
        }
    }

    private func updateLayoutConstraints() {
        guard let hc = hosting,
              let parent = parent as? MapViewController else { return }
        NSLayoutConstraint.deactivate(activeConstraints)
        var constraints: [NSLayoutConstraint] = [
            hc.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
        ]
        if UIDevice.current.userInterfaceIdiom == .pad {
            // iPad top capsule tab bar: page starts below it.
            if let tabBar = parent.tabBar {
                constraints.append(hc.view.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 8))
            } else {
                constraints.append(hc.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor))
            }
            constraints.append(hc.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor))
        } else {
            constraints.append(hc.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor))
            if let tabBar = parent.tabBar {
                constraints.append(hc.view.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -8))
            } else {
                constraints.append(hc.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor))
            }
        }
        if parent.sideBarActive, let sideBar = parent.sideBar {
            // Duo unfolded: the 64pt sidebar owns the right edge.
            constraints.append(hc.view.trailingAnchor.constraint(equalTo: sideBar.leadingAnchor, constant: -8))
        } else {
            constraints.append(hc.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor))
        }
        activeConstraints = constraints
        NSLayoutConstraint.activate(constraints)
    }
}

// MARK: - MapViewController: SettingsBridge + present/dismiss

extension MapViewController: SettingsBridge {
    var settingsCurrentCity: String { currentCity }

    func settingsPickCity(_ key: String) { pickCity(key) }
    func settingsCitySwitched() { dismissNativeSettings() }

    var settingsThemePref: String {
        UserDefaults.standard.string(forKey: "metro-theme") ?? "system"
    }

    func settingsApplyTheme(_ key: String) { applyAppearanceTheme(key) }

    var settingsLangPref: String {
        UserDefaults.standard.bool(forKey: "metro-lang-explicit")
            ? (UserDefaults.standard.string(forKey: "metro-lang") ?? "system")
            : "system"
    }

    func settingsApplyLanguage(_ key: String) { applyLanguageChoice(key) }

    func settingsEvaluateJS(_ js: String, completion: ((Any?) -> Void)?) {
        webView.evaluateJavaScript(js) { result, _ in completion?(result) }
    }

    func settingsPresentShortcut(_ id: String) { presentShortcutSetup(for: id) }

    func settingsRequestLocationPermission() { requestLocationPermission() }

    func settingsClearCache() { clearWebCache() }

    func settingsOpenExternal(_ url: URL, fallback: URL?) {
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else if let fallback = fallback {
            UIApplication.shared.open(fallback, options: [:], completionHandler: nil)
        }
    }

    // MARK: Present / dismiss the native Settings page

    /// Show the native Settings page for the 设置 tab. The web view is
    /// hidden (not destroyed) and its Settings overlays are parked.
    func presentNativeSettings() {
        guard settingsHosting == nil, !splashShowing else { return }
        if appearanceView != nil { dismissAppearance() }
        if languageView != nil { dismissLanguage() }
        hideNearbySmartSwitch()
        for btn in themeButtons { btn.isHidden = true }
        hideStructChrome()
        setSubViewBackButtonVisible(false)
        if settingsStore == nil {
            let s = SettingsStore()
            s.bridge = self
            settingsStore = s
        }
        guard let store = settingsStore else { return }
        store.bridge = self
        store.reloadFromDefaults()
        store.refreshFromWeb()
        let host = SettingsHostingController(store: store)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        settingsHosting = host
        settingsActive = true
        webView.isHidden = true
        // The tab bar must stay on top of the hosted page.
        view.bringSubviewToFront(tabBar)
    }

    /// Remove the native Settings page and restore the web view.
    func dismissNativeSettings() {
        guard let host = settingsHosting else { return }
        settingsHosting = nil
        settingsActive = false
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        webView.isHidden = false
    }
}
