import UIKit
import WebKit
import CoreLocation
import Network // 26E127 fix 7: NWPathMonitor for the cellular-download gate
import ActivityKit
import UserNotifications

// 26F128 B: a UISwitch whose touches never scroll the web page
// underneath. The switch floats over the WKWebView; a drag starting
// on it could be claimed by the web view's scroll-view pan gesture,
// so the page slid while the user toggled (user report 2026-11-25).
// Freezing the scroll view for the duration of the touch makes the
// switch own the gesture end-to-end; the enlarged hit area keeps
// the first touch on the switch instead of beside it.
final class NoScrollSwitch: UISwitch {
    weak var scrollViewToFreeze: UIScrollView?
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return bounds.insetBy(dx: -14, dy: -10).contains(point)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        scrollViewToFreeze?.isScrollEnabled = false
        super.touchesBegan(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        scrollViewToFreeze?.isScrollEnabled = true
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        scrollViewToFreeze?.isScrollEnabled = true
    }
}

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
        // 26F128: Siri Shortcuts removed (user: 砍掉快捷指令功能) —
        // the App Intents, their launch-path registration call and
        // the Settings row are all gone.
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
        // Launch appearance, resolved BEFORE the first frame (26E109,
        // user: light mode cold-starts occasionally flash the DARK
        // splash for one frame). The old first-frame pick read the
        // persisted "metro-dark" — the PREVIOUS session's effective
        // appearance, written by its last themeState post. With the
        // theme following the system, a scheduled appearance flip
        // between sessions (dark at night, light next morning) left
        // that flag stale, so the launch poster opened dark and the
        // web's splashState/themeState correction a moment later
        // flipped it — one visible dark frame. Resolve here instead,
        // from the same source the in-app theme uses: the persisted
        // mode (metro-theme); manual light/dark wins outright, and
        // "system" reads the SCENE's trait at connection time (valid
        // here, unlike the view controller's traitCollection inside
        // viewDidLoad, which is not attached to the scene yet). The
        // resolved value refreshes metro-dark immediately, so every
        // launch reader (poster, injected _metroInitDark, root
        // background) agrees from the first frame, and it is handed
        // to the controller as launchResolvedDark, which outranks
        // the stored flag until the web's first report this session.
        let themeMode = UserDefaults.standard.string(forKey: "metro-theme") ?? "system"
        let sceneDark = windowScene.traitCollection.userInterfaceStyle == .dark
        let resolvedDark = themeMode == "dark" || (themeMode == "system" && sceneDark)
        UserDefaults.standard.set(resolvedDark, forKey: "metro-dark")
        let rootVC = MapViewController()
        rootVC.launchResolvedDark = resolvedDark
        win.rootViewController = rootVC
        // The window's own backing matches the poster's edge colour,
        // so no dark (or light) gap can show before the poster paints.
        win.backgroundColor = resolvedDark ? .black : .white
        win.makeKeyAndVisible()
        window = win
        // Cold launch via a subwaymotion:// deep link (Siri / Shortcuts):
        // the page is not loaded yet, so MapViewController stashes it
        // and applies it once the page finishes loading.
        if let url = connectionOptions.urlContexts.first?.url {
            (win.rootViewController as? MapViewController)?.handleDeepLink(url)
        }
    }

    // Warm open via a subwaymotion:// deep link while the app is
    // already running (Siri / Shortcuts / another app).
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        (window?.rootViewController as? MapViewController)?.handleDeepLink(url)
    }
}


// SDK 26+ Apple corners: UICornerConfiguration gives the system corner
// curve and is the supported way to round glass effect views on
// iOS 26+; older systems fall back to a continuous layer corner.
extension UIView {
    func applyAppleCorner(radius: CGFloat) {
        if #available(iOS 26.0, *) {
            cornerConfiguration = .corners(radius: .fixed(radius))
        } else {
            layer.cornerRadius = radius
            layer.cornerCurve = .continuous
        }
    }
}

class MapViewController: UIViewController, WKNavigationDelegate, UITabBarDelegate, WKScriptMessageHandler, UITextFieldDelegate, CLLocationManagerDelegate {
    var webView: WKWebView!
    var backButton: UIButton!
    // Native sub-view back button (user 2026-11-18: all sub-view back
    // buttons must be native Apple UI SDK 27.2, not the web's CSS circle
    // with a "‹" glyph): a 34pt circular glass button with an SF Symbol
    // chevron.backward, shown only while a Settings sub-view or a
    // timetable line detail is open (web posts "subView" {open: Bool}).
    // Distinct from backButton above, which is the bottom-anchored
    // "‹ 返回" web-history button driven by webView.canGoBack.
    var subViewBackButton: UIButton!
    // Left-edge swipe-back recognizer (26D104): lives on the root view,
    // enabled only while a sub-view is open (mirrors the back button's
    // visibility via setSubViewBackButtonVisible / setSubChromeVisible),
    // and performs the exact back-button action (subViewBackTapped).
    var subViewEdgePan: UIScreenEdgePanGestureRecognizer?
    var subBackLeadingConstraint: NSLayoutConstraint?
    var cityPillLeadingConstraint: NSLayoutConstraint?
    var subBackTopConstraint: NSLayoutConstraint?
    var subHeaderGlass: UIVisualEffectView!
    var subHeaderSep: UIView!
    var subHeaderEffect: UIVisualEffect?
    var subHeaderTitle: UILabel!
    var subHeaderHeightConstraint: NSLayoutConstraint?
    // iPad only (2026-11-22 fix): an opaque cover over the top chrome
    // zone while a sub-view is open, spanning the view's top edge down
    // to the sub-header strip's bottom edge. On iPad the tab bar is a
    // narrow floating pill and the strip starts BELOW it, so the zone
    // beside/above the strip had no cover at all — sub-page content
    // scrolled (or opened, via the sheet's inherited scroll offset) up
    // into it and ghosted bare around the pill. The cover sits above
    // the web view but below the tab bar, the strip and the back
    // button, coloured with rootBackgroundColor() — the exact
    // background of the page underneath — so it reads as the page's
    // own top edge. Nil on iPhone (its strip spans the full width
    // from y=0, so no cover is needed and nothing changes there).
    var subTopCover: UIView?
    // Sub-view header state (user 2026-11-20, latest instruction
    // 22:53: "安全区的按钮参考第二张效果 上移一下" — the reference is
    // the iOS Settings Accessibility page): while ANY sub-view is open
    // the glass strip + centred title fill the safe-area header and
    // the 40pt back button docks inside it at the standard navigation
    // position, at rest AND scrolled alike. This replaces the earlier
    // same-day design (button floating alone at rest over the web's
    // big title, strip only after scrolling) — the timetable detail
    // keeps its title in the web's own .tt-title row, so its strip
    // carries no centred title, but its button docks the same way.
    var subScrolled = false
    // True while the sub-view chrome (glass strip + back button) is
    // fading out after a close; a re-open during the fade cancels it.
    var subChromeClosing = false
    var subDockTitle: String?
    // True while a structurally static sub-view is open (About, 通用
    // and the web fallbacks for 外观/语言 — pages whose content fits
    // the screen and cannot scroll). On those pages the glass strip
    // stays fully hidden and the back button floats alone (26C102);
    // a real scroll post graduates the page back to the frosted
    // strip. Set from the web's subView open post ({static: true}).
    var subViewStatic = false
    var subTimetableMode = false
    var subFrameCenter: (x: CGFloat, y: CGFloat)?
    // Native Appearance picker (user 2026-11-19, 外观 → Apple UI SDK 27.2):
    // a full-screen native view (two Light/Dark preview cards + 自动 switch),
    // opened by the web's "openAppearance" post. Nil while closed.
    var appearanceView: AppearanceView?
    // Native Language picker (user 2026-11-19, 语言 → Apple UI SDK 27.2):
    // a full-screen native grouped list, opened by the web's
    // "openLanguage" post. Nil while closed.
    var languageView: LanguageView?
    var tabBar: UITabBar!
    // Last bottom-clearance value reported to the web (26E115,
    // reportBarFrame): the distance from the screen's bottom edge
    // to the system tab bar's top edge, in points. -1 = nothing
    // reported yet. (The 26E113 hand-drawn iPhone bar is retired;
    // its class survives at the end of this file but is never
    // instantiated or shown.)
    var lastBarClearance: CGFloat = -1
    var cityPill: UIButton!
    // Map tools pill (top-right, build 74): a single Liquid Glass capsule
    // holding the my-location arrow + station search, matching the Apple
    // UI reference the user sent. The two icon buttons live inside it.
    var mapToolsPill: UIView!
    var locateButton: UIButton!
    var resetZoomButton: UIButton!
    var searchPill: UIButton!
    // Native Liquid Glass route-sort tabs (build 33): a UISegmentedControl
    // (Liquid Glass on iOS 26+) overlaid on the web panel's tab row.
    var sortTabs: UISegmentedControl!
    let sortTabKeys = ["rec", "early", "fewest", "cheap"]
    // Native structure-detail chrome (test/structure, 26E107): a
    // UISegmentedControl for 空间结构/平面示意 plus a glass 搜索
    // capsule and (26E108) a circular glass chevron 退出 button
    // matching the sub-view back button, overlaid on the web
    // detail header from "structFrame" reports — same overlay
    // pattern as sortTabs. Test builds only: the web panel itself
    // is unreachable in release builds.
    var structSeg: UISegmentedControl!
    var structSearchButton: UIButton!
    var structExitButton: UIButton!
    let structKindKeys = ["spatial", "plan"]
    // Whether the web structure panel is currently open (26E112:
    // the panel is a Settings sub-page, so currentTab stays "more"
    // while it is up; the web reports the panel state with every
    // "structFrame" post as "panel"). Drives the chrome gate in
    // placeStructChrome and the Duo sidebar strip colour in
    // rootBackgroundColor (the panel's dark background is #101420,
    // not the Settings black).
    var structPanelOpen = false
    // Native Apple UI Liquid Glass dark-mode picker (build 44, 3 glass
    // buttons since build 52): 3 separate glass buttons
    // (跟随系统/浅色/深色) overlaid on the settings panel's
    // .more-theme-seg row, same pattern as sortTabs.
    var themeButtons: [UIButton] = []
    let themeSegKeys = ["system", "light", "dark"]
    // Native UISwitch for the Siri page's 附近车站智能显示 row
    // (26C101, user: the toggle must be Apple UI, not the web CSS
    // switch): frame-positioned over the web's slot element from the
    // "switchFrame" reports, same overlay pattern as the theme
    // buttons. nearbySmartApplying guards the programmatic state sync
    // so it can never be mistaken for a user toggle.
    var nearbySmartSwitch: UISwitch!
    var nearbySmartApplying = false
    // 26E122: the last Home City picker payload, kept so the
    // location-unavailable alert can hand the user straight back
    // to the manual list (re-presenting the same action sheet).
    var lastCommonCityPick: [String: Any]?
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
    // 26E123 ⑥: full-row tap layers for the transfer card — each
    // covers its row band at full card width UNDER the row contents,
    // so tapping any blank part of a row focuses that row's field.
    // The swap button and the badge / clear buttons are added above
    // them and keep their own taps.
    var fromRowTap: UIButton!
    var toRowTap: UIButton!
    // Profile page native Liquid Glass pieces. 26E123 ⑤ shipped
    // a clear-glass BACKPLATE for the info card plus three glass
    // rows (Save / Redeem / Sign Out); on device the backplate
    // blurred the web rows under it into mush. 26E124: the info
    // card is rendered ENTIRELY natively (profileInfoCard: glass
    // card + native nickname field + native labels, rebuilt from
    // the profileFrame payload's rows) — the web card is only a
    // layout anchor now. The three glass rows are unchanged. The
    // identity badges are NOT glass (user exception) and stay web
    // plain-solid chips.
    var profileInfoCard: UIView!
    var profileInfoStack: UIStackView!
    var profileNameField: UITextField?
    var profileRowsSignature: String = ""
    // 26E124: the map station card — rendered ENTIRELY natively
    // (Liquid Glass card, native badges at 60% of the web badge
    // size, native buttons) from the web's mapCardFrame posts.
    var mapCardView: UIView!
    var mapCardNameLabel: UILabel!
    var mapCardBadgeArea: UIView!
    var mapCardBadgeHeight: NSLayoutConstraint?
    var mapCardFromButton: UIButton!
    var mapCardToButton: UIButton!
    var profileSaveRow: UIView!
    var profileSaveLabel: UILabel!
    var profileRedeemRow: UIView!
    var profileRedeemLabel: UILabel!
    var profileLogoutRow: UIView!
    var profileLogoutLabel: UILabel!
    var fromField: UITextField!
    var toField: UITextField!
    // Label buttons beside the native transfer fields (出发/到达), stored
    // so applyLanguage() can retitle them on a language change.
    var fromLabelBtn: UIButton?
    var toLabelBtn: UIButton?
    // Line badges per field (26E110 P): a horizontal stack of pills,
    // one per line serving the picked station (interchange stations
    // show ALL their lines side by side). Buttons are pooled per
    // field and re-titled/re-coloured by applyBadges.
    var fromBadgeStack: UIStackView!
    var toBadgeStack: UIStackView!
    var fromBadges: [UIButton] = []
    var toBadges: [UIButton] = []
    // 26E121 G: the line key each end is pinned to (nil = by station).
    var fromPinnedKey: String?
    var toPinnedKey: String?
    var fromClear: UIButton!
    var toClear: UIButton!
    // Line info currently shown in each field's badge, as
    // {name, color, text} (hex strings from the web); nil = no badge.
    var fromLineInfo: [String: Any]?
    var toLineInfo: [String: Any]?
    // Native Liquid Glass quick-action row (transfer page): the
    // three pills under the search button — transit app / 附近车站
    // / Apple Pay — overlaid on the web's .tr-actions row
    // (frame-positioned from the web, like the transfer card).
    // The web keeps the row as an invisible spacer and reports its
    // frame plus the current transit label / nearby loading state
    // in the same transferFrame posts; the icon images (the SAME
    // App Store artwork the web row shows, inlined into the page
    // from web/*-icon.b64) ride along only when they change and
    // are decoded + cached here.
    var transitAppButton: UIButton!
    var nearbyStationsButton: UIButton!
    var applePayButton: UIButton!
    var actionTransitLabel = ""
    var actionNearbyLoading = false
    var actionTransitIconURL = ""
    var actionTransitIcon: UIImage?
    var actionPinIconURL = ""
    var actionPinIcon: UIImage?
    // Web tab keys, in the same order as the native tab bar items.
    // TEST-BUILD GATE (test/structure branch, 2026-11-22): test
    // builds (CFBundleVersion in the 26E test train, e.g. 26E112)
    // are told apart from release builds (A-train, e.g. A26106) by
    // isTestBuild. 26E106–26E111 carried a 6th "structure" tab behind
    // this gate; 26E112 removes it again (user: back to the 5-tab
    // reference bar) — the structure panel now lives as a Settings
    // sub-page, and isTestBuild remains as the gate for its native
    // chrome (placeStructChrome). This branch is never merged to
    // main; the gate is a second line of defence.
    var isTestBuild: Bool {
        let v = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        // Promotion (2026-11-23, user): the 26E121 test content was
        // promoted to release 1.0.0 as build A26107, so on this branch
        // the A261 train passes the gate too — the structure panel
        // keeps its native chrome in the promoted release build.
        return v.hasPrefix("26E") || v.hasPrefix("A261")
    }
    var tabKeys: [String] {
        ["transfer", "map", "stations", "timetable", "more"]
    }
    // Titles / images aligned with tabKeys.
    func tabTitles() -> [String] {
        [L("tab.transfer"), L("tab.map"), L("tab.stations"), L("tab.timetable"), L("tab.more")]
    }
    func tabImages() -> [UIImage?] {
        // Solid-filled glyphs (26E110, user: the 26E109 bar still
        // read as thin outline icons; match the reference app's
        // filled set). SF Symbols with a true .fill variant use it
        // (map.fill / gearshape.fill — all verified in the SF
        // Symbols catalog). Two tabs have NO fill variant in
        // the catalog (verified): arrow.triangle.2.circlepath (only
        // .camera/.circle/.doc variants) and magnifyingglass — those
        // read solid through the BOLD symbol configuration applied
        // where the images are rendered (tabBarItemImage for the
        // tab bars, sideBarButtonConfig for the Duo sidebar). The
        // timetable stays the bundled PNG, regenerated solid in
        // 26E110 (see tabBarItemImage). (The cube.fill that rode
        // along for the structure tab until 26E111 left with it in
        // 26E112; the Settings 车站结构 row is web-rendered.)
        [
            UIImage(systemName: "arrow.triangle.2.circlepath"),
            UIImage(systemName: "map.fill"),
            UIImage(systemName: "magnifyingglass"),
            UIImage(named: "TimetableIcon"),
            UIImage(systemName: "gearshape.fill"),
        ]
    }
    // Tab-bar glyph sizing (test/structure, user 2026-11-22): the
    // glyph size is a parameter of tabBarItemImage — 24pt for the
    // UITabBar items (the iPad top capsule and, since 26E115, the
    // iPhone bottom bar again). This is applied only where the bar
    // items are created; tabImages() itself is shared with the Duo
    // sidebar, which keeps its own sizing and is NOT touched here.
    // The only non-symbol tab icon is the timetable PNG, and it has
    // transparent margins. The asset was REGENERATED SOLID in
    // 26E110 (heavy calendar: solid header band with binder holes,
    // thick frame, dot grid, big solid clock badge with knocked-out
    // hands — the reference app's glyph; drawn by
    // gate-26e110/draw_tt_icon.py). SF's calendar.badge.clock was
    // NOT used: its calendar body is an empty outline frame with
    // binder rings and no dot grid, so at any weight it still reads
    // as an outline icon next to the filled set. Measured on the
    // asset build.sh actually bundles — web/timetable-icon@3x.b64
    // decoded, 75x75px: the glyph's alpha bbox (thresholded past
    // the resampling fringe) is (5,13)–(70,66), i.e. x 0.067–0.933
    // / y 0.173–0.880 of the canvas. (History: the 26E108 crop
    // fractions were measured on a stray web/timetable-icon PNG
    // whose glyph box differs, and they cut the glyph's right and
    // bottom edges; 26E109 re-measured on the then-bundled line-art
    // asset, bbox (4,10)–(70,65).) Scaling the whole canvas to the
    // symbol size leaves the visible glyph short next to the
    // symbols (user 2026-11-22: 时刻表图标偏小), so the PNG is
    // rendered by its GLYPH box instead: the image is drawn
    // shifted/scaled so the padded glyph box fills a 26pt-tall
    // canvas, aligning the glyph's height with the symbols.
    // Render-time only — the source asset is untouched.
    // (26E118: that alignment assumption was wrong — the raw
    // symbols' glyphs are ~29pt at pointSize 24, not 24. The
    // symbols are normalized by their glyph boxes too now; see
    // the 26E118 note inside tabBarItemImage.)
    // 26E118 (user, on the 26E116 device shot): the four symbols
    // still read BIGGER than the timetable — "四大一小". Measured
    // on the user's own screenshot of the running bar (glyph alpha
    // heights, fringe-thresholded, @3x px): transfer 89, map 86,
    // search 88, settings 90 vs timetable 66. The symbols were
    // handed to the bar as raw pointSize-24-bold symbol images,
    // whose glyphs fill ~0.94 of a ~31pt-tall canvas (~29pt glyph);
    // the PNG is placed by its padded glyph box on a 24pt canvas,
    // so its TRUE glyph is only 24 x 0.9178 = 22.0pt (the @3x asset
    // measures x 5-69 / y 13-65 on 75x75 = fractions 0.8667 x
    // 0.7067; the padded box below is 0.92 x 0.77, so the true
    // glyph occupies 0.8667/0.92 = 0.9420 of the canvas width and
    // 0.7067/0.77 = 0.9178 of the canvas height — and 66px on the
    // device shot is 22.0pt, confirming the model end to end).
    // Fix: the symbols now go through the SAME glyph-box
    // normalization as the PNG. Each symbol's alpha bbox is
    // measured at render time (symbolGlyphFractions), padded by
    // the timetable's own ratios (glyph = 0.9420 of the padded
    // width, 0.9178 of the padded height, centred), and the padded
    // box is mapped onto a canvas of height `size` — so all five
    // tabs end with a true glyph 22.0pt tall occupying identical
    // fractions of their canvases. Render-time only, exactly like
    // the PNG path; no artwork is redrawn, the symbol is only
    // scaled/translated into its canvas. One image per tab is
    // enough: the bar tints the same image for the normal and
    // selected states (no separate selected set exists).
    func tabBarItemImage(_ image: UIImage?, size: CGFloat = 24) -> UIImage? {
        guard let image = image else { return nil }
        if image.isSymbolImage {
            // Bold since 26E110 (regular until 26E109): the two
            // stroke-based glyphs (transfer arrows, magnifier) have
            // no .fill variant and only read as solid at bold
            // weight; the .fill variants stay filled at any weight.
            let configured = image.withConfiguration(UIImage.SymbolConfiguration(pointSize: size, weight: .bold))
            return glyphNormalizedSymbolImage(configured, size: size) ?? configured
        }
        guard image.size.width > 0, image.size.height > 0 else { return image }
        // Glyph box as fractions of the image size (measured alpha
        // bbox x 0.067-0.933 / y 0.173-0.880 on the bundled @3x
        // asset decoded from web/timetable-icon@3x.b64 — the solid
        // 26E110 redraw — padded ~0.02-0.03 a side).
        let glyph = CGRect(x: 0.04, y: 0.14, width: 0.92, height: 0.77)
        let targetHeight: CGFloat = size
        let canvas = CGSize(width: targetHeight * (glyph.width / glyph.height) * (image.size.width / image.size.height),
                            height: targetHeight)
        let scale = targetHeight / (image.size.height * glyph.height)
        let drawRect = CGRect(x: -glyph.minX * image.size.width * scale,
                              y: -glyph.minY * image.size.height * scale,
                              width: image.size.width * scale,
                              height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { _ in image.draw(in: drawRect) }
    }
    // 26E118: the timetable glyph's share of its finished canvas
    // (measured on the bundled @3x asset vs the padded box the PNG
    // branch renders by — see tabBarItemImage). The symbol
    // normalization pads each symbol's measured glyph box by these
    // same ratios, so every tab's glyph lands at the same size and
    // the same canvas fractions as the timetable's.
    static let tabGlyphWidthShare: CGFloat = 0.9420  // 0.8667 / 0.92
    static let tabGlyphHeightShare: CGFloat = 0.9178 // 0.7067 / 0.77
    // Alpha bbox of a rendered image as fractions of its pixel
    // size, in top-left (UIKit) coordinates. Same fringe threshold
    // as the offline timetable measurement (alpha > 32 past the
    // resampling fringe). Nil when the image has no drawable
    // CGImage or no pixel passes the threshold.
    func symbolGlyphFractions(_ image: UIImage) -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = ctx.data else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, maxX = -1, minRow = h, maxRow = -1
        for row in 0..<h {
            for x in 0..<w where px[(row * w + x) * 4 + 3] > 32 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if row < minRow { minRow = row }
                if row > maxRow { maxRow = row }
            }
        }
        guard maxX >= minX, maxRow >= minRow else { return nil }
        // Bitmap-context memory rows run bottom-up (Quartz space);
        // convert the row extent to top-left fractions. The x extent
        // is unaffected.
        let topRow = h - 1 - maxRow
        return CGRect(x: CGFloat(minX) / CGFloat(w),
                      y: CGFloat(topRow) / CGFloat(h),
                      width: CGFloat(maxX - minX + 1) / CGFloat(w),
                      height: CGFloat(maxRow - minRow + 1) / CGFloat(h))
    }
    // 26E118: render a configured symbol the way the PNG branch
    // renders the timetable — by its glyph box. The measured glyph
    // box is padded around its centre by the timetable's shares
    // (above), then the padded box is mapped onto a canvas of
    // height `size`, so the finished glyph is `size` x 0.9178 tall
    // (= 22.0pt at the default 24), the timetable's exact size.
    // Falls back to nil (caller uses the raw configured symbol) if
    // the glyph cannot be measured.
    // 26E120 F (user, on the 26E119 device crop): the four symbols
    // STILL rendered bigger than the timetable. Measured on the
    // crop (native @3x, icon band separated from the title band):
    // timetable glyph 65px; transfer 93, map 89, search 91,
    // settings 94 — the symbols sit at ~29-31pt, their RAW
    // pointSize-24-bold glyph size, while the timetable is at its
    // modelled 22.0pt. Root cause: the measurement above read the
    // symbol image's cgImage, but an SF Symbol image has no
    // directly measurable CGImage bitmap — symbolGlyphFractions
    // returned nil on device, this function bailed, and the
    // caller fell back to the raw configured symbol. (The 26E118
    // gate verified the algebra, which is exact, but never
    // executed the measurement.) Fix: rasterise the configured
    // symbol into a plain bitmap FIRST (a renderer draw always
    // works), measure THAT bitmap's alpha bbox, then run the
    // unchanged normalization, drawing the symbol itself into the
    // padded canvas so the vector stays crisp. The target is
    // unchanged — glyph = size x 0.9178 = 22.03pt, the
    // timetable's own height, about x0.74 of the size the symbols
    // render at today — and each symbol is measured individually,
    // so the four land mutually equal by construction.
    func glyphNormalizedSymbolImage(_ image: UIImage, size: CGFloat) -> UIImage? {
        guard let bitmap = symbolBitmap(image),
              let glyph = symbolGlyphFractions(bitmap),
              image.size.width > 0, image.size.height > 0 else { return nil }
        let padW = glyph.width / Self.tabGlyphWidthShare
        let padH = glyph.height / Self.tabGlyphHeightShare
        let padded = CGRect(x: glyph.midX - padW / 2, y: glyph.midY - padH / 2, width: padW, height: padH)
        let canvas = CGSize(width: size * (padded.width / padded.height) * (image.size.width / image.size.height),
                            height: size)
        let scale = size / (image.size.height * padded.height)
        let drawRect = CGRect(x: -padded.minX * image.size.width * scale,
                              y: -padded.minY * image.size.height * scale,
                              width: image.size.width * scale,
                              height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let rendered = renderer.image { _ in image.draw(in: drawRect) }
        // Keep the symbol's template behaviour in the bar (the raw
        // symbol was a template image; the rendered copy must tint
        // the same way for the normal and selected states).
        return rendered.withRenderingMode(.alwaysTemplate)
    }
    // 26E120 F: rasterise a (symbol) image into a plain bitmap at
    // scale 3 so its alpha bbox can be measured — a symbol image
    // itself exposes no CGImage to measure (see the note above).
    func symbolBitmap(_ image: UIImage) -> UIImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }
    // Siri / deep-link routing (user 2026-11-18, Siri Shortcuts): a
    // subwaymotion:// link that arrives before the offline page has
    // finished loading is stashed here and applied from
    // webView(_:didFinish:) once window.metroApp exists.
    var pendingDeepLinkURL: URL?
    var webPageReady = false
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
    // Changchun Line 1 red #E50011 (Wikipedia Template: 长春轨道交通颜色,
    // code 1; no separate system brand colour is published - see NOTES.md).
    // Darker #B3000D for selected states/text.
    let changchunRed = UIColor(red: 229.0 / 255.0, green: 0.0 / 255.0, blue: 17.0 / 255.0, alpha: 1)
    let changchunRedDark = UIColor(red: 179.0 / 255.0, green: 0.0 / 255.0, blue: 13.0 / 255.0, alpha: 1)
    // Chengdu Line 1 #0F0F96 (official line colour, Chengdu DB510100/T
    // 083-2012 wayfinding standard; no single official system brand colour
    // is published). Darker #0A0A6E is derived (Line 1 darkened ~30%), not
    // an official published value.
    let chengduBlue = UIColor(red: 15.0 / 255.0, green: 15.0 / 255.0, blue: 150.0 / 255.0, alpha: 1)
    let chengduBlueDark = UIColor(red: 10.0 / 255.0, green: 10.0 / 255.0, blue: 110.0 / 255.0, alpha: 1)
    // Shenzhen Metro system colour #00A051 (Shenzhen Metro brand
    // green). Darker #007039 is derived (darkened ~30%), not an
    // official published value.
    let shenzhenGreen = UIColor(red: 0, green: 160.0 / 255.0, blue: 81.0 / 255.0, alpha: 1)
    let shenzhenGreenDark = UIColor(red: 0, green: 112.0 / 255.0, blue: 57.0 / 255.0, alpha: 1)
    // Qingdao Metro brand green #317C5B (sampled from the official
    // app icon). Darker #276349 is derived (darkened ~20%), not an
    // official published value.
    let qingdaoGreen = UIColor(red: 49.0 / 255.0, green: 124.0 / 255.0, blue: 91.0 / 255.0, alpha: 1)
    let qingdaoGreenDark = UIColor(red: 39.0 / 255.0, green: 99.0 / 255.0, blue: 73.0 / 255.0, alpha: 1)
    // Shijiazhuang Metro Line 1 red #E53E30 (official line colour,
    // RMP palette). Darker #B53126 is derived (x0.79), not an
    // official published value.
    let shijiazhuangRed = UIColor(red: 229.0 / 255.0, green: 62.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
    let shijiazhuangRedDark = UIColor(red: 181.0 / 255.0, green: 49.0 / 255.0, blue: 38.0 / 255.0, alpha: 1)
    // Tianjin Metro Line 1 red #CB333B (official line colour, sampled
    // from the official 2026-07-21 network map; also the city theme).
    // Darker #A0282F is derived (x0.79), not an official published value.
    let tianjinRed = UIColor(red: 203.0 / 255.0, green: 51.0 / 255.0, blue: 59.0 / 255.0, alpha: 1)
    let tianjinRedDark = UIColor(red: 160.0 / 255.0, green: 40.0 / 255.0, blue: 47.0 / 255.0, alpha: 1)
    // Wuxi Metro Line 1 red #EE2737 (official line colour, Wikipedia
    // rail colour / RMP palette agree). Darker #BC1F2B is derived
    // (x0.79), not an official published value.
    let wuxiRed = UIColor(red: 238.0 / 255.0, green: 39.0 / 255.0, blue: 55.0 / 255.0, alpha: 1)
    let wuxiRedDark = UIColor(red: 188.0 / 255.0, green: 31.0 / 255.0, blue: 43.0 / 255.0, alpha: 1)
    let luoyangPink = UIColor(red: 196.0 / 255.0, green: 96.0 / 255.0, blue: 140.0 / 255.0, alpha: 1)
    let luoyangPinkDark = UIColor(red: 154.0 / 255.0, green: 75.0 / 255.0, blue: 110.0 / 255.0, alpha: 1)
    let guangzhouYellow = UIColor(red: 237.0 / 255.0, green: 207.0 / 255.0, blue: 59.0 / 255.0, alpha: 1)
    let guangzhouYellowDark = UIColor(red: 187.0 / 255.0, green: 163.0 / 255.0, blue: 46.0 / 255.0, alpha: 1)
    var currentCity = "bj"
    var currentTab = "transfer"
    // Splash gate (user 2026-11-15): the native tab bar + top pills sit
    // ABOVE the WKWebView, so they showed on top of the web splash
    // animation for 2s. Keep them hidden until the web says the splash
    // is done (or the fallback timer fires).
    var splashShowing = true
    // Launch appearance (26E109): the variant resolved by the scene
    // delegate at connection time, before the first frame. Until the
    // web's first themeState/splashState report THIS session, this
    // outranks the persisted metro-dark flag (which may be the
    // previous session's stale effective appearance).
    var launchResolvedDark: Bool? = nil
    var themeResolvedThisSession = false
    // Single dark-appearance resolver for every launch-time reader
    // (splash poster, injected _metroInitDark, root background):
    // this session's web report once it lands, else the scene-time
    // resolution, else the persisted flag, else the trait.
    func splashDarkResolved() -> Bool {
        if themeResolvedThisSession, let b = UserDefaults.standard.object(forKey: "metro-dark") as? Bool { return b }
        if let l = launchResolvedDark { return l }
        if let b = UserDefaults.standard.object(forKey: "metro-dark") as? Bool { return b }
        return traitCollection.userInterfaceStyle == .dark
    }
    // Native launch splash view (build 53): shows the current city's
    // splash image from launch, covering the white gap before the web
    // page loads and its own splash appears. Hidden in splashFinished().
    var splashImageView: UIImageView!
    // First-launch What's New, native full-screen page (26E125):
    // the 26E124 web overlay's confirm button sat under the native
    // tab bar, so users could not enter the app at all. The page is
    // native, shown after the splash, covering the webView and all
    // native chrome; the confirm button is pinned above the safe
    // area and never moves. pendingWhatsNew holds the web's payload
    // until the splash ends.
    var pendingWhatsNew: [String: Any]? = nil
    var whatsNewShowing = false
    var whatsNewView: UIView? = nil
    // Location (build 63): find the nearest station. The permission
    // prompt appears only when the user taps 附近车站, never at launch.
    var locationManager: CLLocationManager?
    var locationPending = false
    // Location permission row (Settings): true while waiting for the
    // user to answer the permission prompt triggered from the row.
    var locPermPending = false
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
        "tab.map": ["线路图", "線路圖", "Line Map"],
        "tab.stations": ["搜索", "搜索", "Search"],
        "tab.timetable": ["时刻表", "時刻表", "Timetable"],
        "tab.structure": ["结构", "結構", "Structure"],
        "struct.spatial": ["空间结构", "空間結構", "Spatial Layout"],
        "struct.plan": ["平面示意", "平面示意", "Plan Diagram"],
        "struct.exit": ["退出", "退出", "Exit"],
        "tab.more": ["设置", "設定", "Settings"],
        "city.bj": ["北京", "北京", "Beijing"],
        "city.sy": ["沈阳", "瀋陽", "Shenyang"],
        "city.sh": ["上海", "上海", "Shanghai"],
        "city.hb": ["哈尔滨", "哈爾濱", "Harbin"],
        "city.dl": ["大连", "大連", "Dalian"],
        "city.jh": ["金华", "金華", "Jinhua"],
        "city.cz": ["常州", "常州", "Changzhou"],
        "city.cq": ["重庆", "重慶", "Chongqing"],
        "city.cc": ["长春", "長春", "Changchun"],
        "city.sz": ["深圳", "深圳", "Shenzhen"],
        "city.cd": ["成都", "成都", "Chengdu"],
        "city.qd": ["青岛", "青島", "Qingdao"],
        "city.sjz": ["石家庄", "石家莊", "Shijiazhuang"],
        "city.tj": ["天津", "天津", "Tianjin"],
        "city.wx": ["无锡", "無錫", "Wuxi"],
        "city.ly": ["洛阳", "洛陽", "Luoyang"],
        "city.gz": ["广州", "廣州", "Guangzhou"],
        "native.cancel": ["取消", "取消", "Cancel"],
        "tr.tab.rec": ["推荐", "推薦", "Recommended"],
        "tr.tab.early": ["耗时最短", "耗時最短", "Fastest"],
        "tr.tab.fewest": ["路径最短", "路徑最短", "Shortest"],
        "tr.tab.cheap": ["节省票价", "節省票價", "Cheapest"],
        "more.theme.system": ["跟随系统", "跟隨系統", "System"],
        "more.theme.light": ["浅色", "淺色", "Light"],
        "more.theme.dark": ["深色", "深色", "Dark"],
        "more.theme.auto": ["自动", "自動", "Automatic"],
        "more.appearance": ["外观", "外觀", "Appearance"],
        "more.lang": ["语言", "語言", "Language"],
        "more.lang.system": ["跟随系统", "跟隨系統", "Follow System"],
        "more.lang.hans": ["简体中文", "簡體中文", "Simplified Chinese"],
        "more.lang.hant": ["繁體中文", "繁體中文", "Traditional Chinese"],
        "more.lang.en": ["English", "English", "English"],
        "map.downloadAll": ["下载全部线路图", "下載全部線路圖", "Download all line maps"],
        "map.downloading": ["正在下载…", "正在下載…", "Downloading…"],
        "map.downloaded": ["已下载 {n}/17 张线路图", "已下載 {n}/17 張線路圖", "Downloaded {n}/17 line maps"],
        "map.downloadingCount": ["正在下载 {done}/{total}", "正在下載 {done}/{total}", "Downloading {done}/{total}"],
        "map.download": ["下载", "下載", "Download"],
        "map.retry": ["重试", "重試", "Retry"],
        "map.downloadingShort": ["下载中", "下載中", "Downloading…"],
        "common.ok": ["知道了", "知道了", "OK"],
        "tr.nearby": ["附近车站", "附近車站", "Nearby Stations"],
        "tr.nearby.locating": ["定位中…", "定位中…", "Locating…"],
        "tr.applepay": ["Apple Pay", "Apple Pay", "Apple Pay"],
        "transit.bj": ["一卡通", "一卡通", "Yikatong"],
        "transit.sy": ["盛京通", "盛京通", "Shengjing Tong"],
        "transit.sh": ["Metro大都会", "Metro大都會", "Metro Daduhui"],
        "transit.hb": ["哈尔滨城市通", "哈爾濱城市通", "Harbin City Pass"],
        "transit.dl": ["大连交通e出行", "大連交通e出行", "Dalian e-Travel"],
        "transit.jh": ["任我行", "任我行", "Renwoxing"],
        "transit.cz": ["常州地铁", "常州地鐵", "Changzhou Metro"],
        "transit.cq": ["渝畅行", "渝暢行", "Yuchangxing"],
        "transit.cc": ["长春E出行", "長春E出行", "Changchun E-Travel"],
        "transit.sz": ["深圳地铁", "深圳地鐵", "Shenzhen Metro"],
        "transit.cd": ["成都地铁", "成都地鐵", "Chengdu Metro"],
        "transit.qd": ["青岛地铁", "青島地鐵", "Qingdao Metro"],
        "transit.sjz": ["石慧行", "石慧行", "Shihuihang"],
        "transit.tj": ["天津地铁", "天津地鐵", "Tianjin Metro"],
        "transit.wx": ["码上行", "碼上行", "Mashangxing"],
        "transit.ly": ["洛易行", "洛易行", "Luoyixing"],
        "transit.gz": ["广州地铁官方APP", "廣州地鐵官方APP", "Guangzhou Metro"],
        "tr.search": ["搜索", "搜索", "Search"],
        "tr.departNow": ["现在出发", "現在出發", "Depart now"],
        "time.confirm": ["确定", "確定", "Done"],
        "time.done": ["完成", "完成", "Done"],
        "search.title": ["搜索条件", "搜索條件", "Search Conditions"],
        "search.first": ["首班车", "首班車", "First train"],
        "search.last": ["末班车", "末班車", "Last train"],
        "search.card": ["交通卡", "交通卡", "Transit card"],
        "search.cash": ["现金", "現金", "Cash"],
        "search.applepay": ["Apple Pay", "Apple Pay", "Apple Pay"],
        "search.applepay.unavailable.title": ["无法打开钱包", "無法打開錢包", "Wallet unavailable"],
        "search.applepay.unavailable.message": ["无法打开 Apple Pay / 钱包，请确认钱包应用已安装。", "無法打開 Apple Pay / 錢包，請確認錢包應用已安裝。", "Apple Pay / Wallet could not be opened. Please make sure the Wallet app is installed."],
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
        "live.notifyBody": ["{from} → {to}，下一站 {next}", "{from} → {to}，下一站 {next}", "{from} → {to} — next stop {next}"],
    ]
    // System per-app language (iOS Settings > Subway Tools > Language).
    // Bundle.main.preferredLocalizations reflects the per-app choice when
    // the bundle has .lproj localizations; otherwise the device language.
    static func systemLang() -> String {
        let pref = Bundle.main.preferredLocalizations.first ?? ""
        if pref.hasPrefix("zh-Hant") || pref.hasPrefix("zh-HK") || pref.hasPrefix("zh-TW") || pref.hasPrefix("zh-MO") { return "zh-Hant" }
        if pref.hasPrefix("en") { return "en" }
        return "zh-Hans"
    }
    // Effective language: the explicit in-app choice (UserDefaults
    // "metro-lang") if the user picked one in the app, else the iOS
    // per-app language from System Settings. "metro-lang-explicit" is
    // false until the user taps a language in the in-app picker, so a
    // fresh install follows the system language.
    var currentLang: String = {
        if UserDefaults.standard.bool(forKey: "metro-lang-explicit"),
           let saved = UserDefaults.standard.string(forKey: "metro-lang") { return saved }
        return MapViewController.systemLang()
    }()
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
    // lang == "system" means the user picked Follow System in-app: clear
    // the explicit override and follow the iOS per-app language.
    // explicit == false is the web's startup restore post, not a user
    // choice: never turn it into an explicit override.
    func setLang(_ lang: String, explicit: Bool = true) {
        if lang == "system" {
            UserDefaults.standard.set(false, forKey: "metro-lang-explicit")
            UserDefaults.standard.removeObject(forKey: "metro-lang")
            currentLang = Self.systemLang()
            applyLanguage()
            return
        }
        let l = (lang == "zh-Hant" || lang == "en") ? lang : "zh-Hans"
        guard explicit else {
            applyLanguage()
            return
        }
        currentLang = l
        UserDefaults.standard.set(true, forKey: "metro-lang-explicit")
        UserDefaults.standard.set(l, forKey: "metro-lang")
        applyLanguage()
    }
    // Re-apply all native strings for the current language.
    func applyLanguage() {
        let titles = tabTitles()
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
        refreshStructChromeTitles()
        let themeTitles = [L("more.theme.system"), L("more.theme.light"), L("more.theme.dark")]
        for (i, btn) in themeButtons.enumerated() where i < themeTitles.count {
            var cfg = btn.configuration ?? themeButtonConfig()
            cfg.title = themeTitles[i]
            btn.configuration = cfg
        }
        if transferSearchButton != nil { updateTransferSearchStyle() }
        refreshActionButtons()
        if fromField != nil { fromField.placeholder = L("tr.phFrom") }
        if toField != nil { toField.placeholder = L("tr.phTo") }
        fromLabelBtn?.setTitle(L("tr.depart"), for: .normal)
        toLabelBtn?.setTitle(L("tr.arrive"), for: .normal)
        updateSideBarSelection()
        if let lv = languageView {
            lv.relocalize(pageTitle: L("more.lang"), systemTitle: L("more.lang.system"), hansTitle: L("more.lang.hans"), hantTitle: L("more.lang.hant"), enTitle: L("more.lang.en"), systemDetail: systemLangDisplayName())
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Restore the last-used city (build 37): relaunch opens on
        // the city the user last switched to (written by pickCity
        // and by the web's cityChanged post; default Beijing).
        // Must run before any accentColor()/pill setup below.
        if let saved = UserDefaults.standard.string(forKey: "metro-city"),
           ["bj", "sy", "sh", "hb", "dl", "jh", "cz", "cq", "cc", "sz", "cd", "qd", "sjz", "tj", "wx", "ly", "gz"].contains(saved) {
            currentCity = saved
        }
        view.backgroundColor = rootBackgroundColor() // Tab- and theme-matched page background: on the unfolded Duo the area beside the sidebar blends with the page instead of showing as an edge (users 2026-11-21, 2026-11-22).

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "tabChanged")
        config.userContentController.add(self, name: "cityMenu")
        config.userContentController.add(self, name: "tabsFrame")
        config.userContentController.add(self, name: "structFrame")
        config.userContentController.add(self, name: "transferFrame")
        config.userContentController.add(self, name: "themeFrame")
        config.userContentController.add(self, name: "switchFrame")
        config.userContentController.add(self, name: "profileFrame")
        config.userContentController.add(self, name: "mapCardFrame")
        config.userContentController.add(self, name: "stationPicked")
        config.userContentController.add(self, name: "fastNote")
        config.userContentController.add(self, name: "redeemCode")
        config.userContentController.add(self, name: "redeemNote")
        config.userContentController.add(self, name: "commonCityPick")
        config.userContentController.add(self, name: "recommendCity")
        config.userContentController.add(self, name: "commonCityNote")
        config.userContentController.add(self, name: "timePicker")
        config.userContentController.add(self, name: "openTransitApp")
        config.userContentController.add(self, name: "openRideCode")
        config.userContentController.add(self, name: "requestLocation")
        config.userContentController.add(self, name: "requestLocationPermission")
        config.userContentController.add(self, name: "openURL")
        config.userContentController.add(self, name: "cityChanged")
        config.userContentController.add(self, name: "langChanged")
        config.userContentController.add(self, name: "splashDone")
        config.userContentController.add(self, name: "splashState")
        config.userContentController.add(self, name: "whatsNew")
        config.userContentController.add(self, name: "themeState")
        config.userContentController.add(self, name: "liveActivity")
        config.userContentController.add(self, name: "clearCache")
        config.userContentController.add(self, name: "subView")
        config.userContentController.add(self, name: "topChrome")
        config.userContentController.add(self, name: "mapState")
        config.userContentController.add(self, name: "mapsDownloadFrame")
        config.userContentController.add(self, name: "cityDownloadFrame")
        config.userContentController.add(self, name: "departFrame") // 26E127 fix 11
        config.userContentController.add(self, name: "mapProgress")
        config.userContentController.add(self, name: "openAppearance")
        config.userContentController.add(self, name: "openLanguage")
        // Inject the iOS per-app language + device idiom before the page's
        // scripts run, so the web's savedLang() can follow the system
        // language when the user has no explicit in-app choice (see
        // systemLang()), and the web can clear the top tab bar on iPad.
        // Splash state injection (2026-11-20, second fix for "每个城市都
        // 显示北京 / 没有深色模式"): the web's file:// localStorage did
        // not survive on the user's device — the launch restore read
        // nothing back, so the web overlay stayed on Beijing + light
        // even though the native side held the right values.
        // UserDefaults is now the single source of truth: inject the
        // persisted city + theme + effective dark flag at document
        // start and let the web prefer them over localStorage.
        let _isPadStr = UIDevice.current.userInterfaceIdiom == .pad ? "true" : "false"
        let _initCity = currentCity
        let _initTheme = UserDefaults.standard.string(forKey: "metro-theme") ?? "system"
        let _initDark = splashDarkResolved()
        let _langScript = WKUserScript(source: "window._metroSystemLang = '\(Self.systemLang())'; window._metroIsPad = \(_isPadStr); window._metroInitCity = '\(_initCity)'; window._metroInitTheme = '\(_initTheme)'; window._metroInitDark = \(_initDark); window._metroIsCellular = false;", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(_langScript)
        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.allowsBackForwardNavigationGestures = true
        view.addSubview(webView)

        // 26E127 fix 7: start the cellular path monitor before the page loads, so window._metroIsCellular is set before any download can ask the gate.
        startNetworkMonitor()

        // Native tab bar (UITabBar). The web page hides its own
        // tab bar; this bar is the only one the user sees.
        tabBar = UITabBar()
        tabBar.delegate = self
        // Selected tab = system blue (26E112, user with reference
        // shot: blue icon + blue title on the grey selection
        // capsule), NOT the city accent — the bar no longer turns
        // red/blue with the city's theme colour.
        tabBar.tintColor = .systemBlue
        let _titles = tabTitles()
        let _images = tabImages()
        var items: [UITabBarItem] = []
        for i in 0..<tabKeys.count {
            items.append(UITabBarItem(title: _titles[i], image: tabBarItemImage(_images[i]), tag: i))
        }
        tabBar.items = items
        tabBar.selectedItem = items[0] // default tab is transfer (26E126, user 2026-11-24), same as the web page
        // Floating Liquid Glass capsule (iOS 26 / SDK 27.2, user 2026-11-15):
        // the bar floats above the content with rounded ends. The glass is
        // the UITabBar's OWN Apple glass (default appearance on iOS 26+)
        // — a single layer. Build 50 added a UIVisualEffectView glass
        // subview on top of the bar's own glass, so the glass showed
        // TWICE (user 2026-11-15 "为啥有玻璃重复"). Do NOT add a glass
        // view here.
        // 26E119: the corner clip is iPad-only now. On iPhone the
        // system's own background draws the capsule with its own
        // fully rounded ends (the reference bar's look); the manual
        // 25pt clip dates from the custom-appearance era and can
        // only flatten the system's own rounding. The iPad top
        // capsule still gets its rounded shape from this clip (its
        // appearance is a transparent material over the bar bounds).
        if UIDevice.current.userInterfaceIdiom == .pad {
            tabBar.layer.cornerRadius = 25
            tabBar.layer.masksToBounds = true
        }
        tabBar.isTranslucent = true
        if #available(iOS 26.0, *) {
            // Light-mode fix (user 2026-11-18, iPad branch only since
            // 26E115): configureWithDefaultBackground() rendered as a
            // flat medium-grey capsule in light mode, with white
            // unselected icons. Use a transparent background with the
            // adaptive system material instead: light mode is a light
            // translucent glass, dark mode the dark glass. Unselected
            // items use .secondaryLabel so they stay legible in both
            // modes; the selected item is system blue via
            // tabBar.tintColor (26E112: no longer the city accent).
            let appearance = UITabBarAppearance()
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad top capsule — UNCHANGED (26E115 does not touch
                // the iPad bar): the transparent background with the
                // adaptive system material from the light-mode fix
                // below (user 2026-11-18).
                appearance.configureWithTransparentBackground()
                appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
                appearance.backgroundColor = .clear
                appearance.shadowColor = .clear
            } else {
                // iPhone (26E115, user: the hand-drawn 26E113 bar
                // "is not Apple UI Liquid Glass and cannot slide"):
                // the visible bar is THIS system UITabBar again, with
                // the system's OWN default background — on iOS 26
                // that IS Liquid Glass, with the system selection
                // capsule that slides between items on tap. Do NOT
                // override backgroundEffect / backgroundColor here:
                // the systemMaterial override is exactly what made
                // the bar read as a flat fake. (Info.plist carries
                // no UIDesignRequiresCompatibility opt-out, so a
                // stock bar adopts the glass by itself.)
                appearance.configureWithDefaultBackground()
            }
            appearance.stackedLayoutAppearance.normal.iconColor = .secondaryLabel
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
            // Roomier tab layout (test/structure, user 2026-11-22,
            // aligned to the user's reference shot — near-full-width
            // capsule, items spread evenly): pin the title font
            // in both states on every layout appearance, so the
            // labels keep even breathing room instead of the system
            // default. 11pt since 26E109 (10pt until 26E108),
            // matching the 26pt icons (tabBarItemImage) the user
            // asked for against the iOS 26 reference bar. Selected
            // keeps the system-blue tint colour (no foreground
            // override, tint still drives it; 26E112). The bar's
            // height is intrinsic and grows with the larger
            // glyphs/titles on its own.
            let tabTitleFont = UIFont.systemFont(ofSize: 11)
            let tabTitleFontSelected = UIFont.systemFont(ofSize: 11, weight: .medium)
            for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
                layout.normal.titleTextAttributes[.font] = tabTitleFont
                layout.selected.titleTextAttributes = [.font: tabTitleFontSelected]
            }
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
        }
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabBar)
        // Splash gate: hidden until the web splash finishes.
        tabBar.isHidden = true
        // Floating tab bar (build 74, user 2026-11-18 "将iPad底栏改成顶栏"):
        // iPad floats it at the TOP as a compact capsule (not the big top
        // strip removed in build 63); iPhone keeps it at the bottom.
        // The web view is full-screen, so there is no white strip
        // behind the bar.
        let isPadBar = UIDevice.current.userInterfaceIdiom == .pad
        // Side insets (test/structure, user 2026-11-22 "底栏不要那么
        // 拥挤", reference shot is a near-full-width capsule): iPhone
        // insets go 16 -> 8pt so the capsule nearly spans the screen
        // and the items spread evenly with clear gaps. iPad keeps
        // 16pt — its bar floats at the top as a compact capsule and
        // the wider inset is part of that look; not changed.
        // 26E119 (user: match the reference bar's margins): measured
        // on the 26E117 device shot, the VISIBLE capsule sits ~24pt
        // in from the screen edges — the 8pt frame inset plus ~16pt
        // the system background keeps inside a standalone UITabBar
        // frame (no public API moves that inner inset). The
        // reference bar's visible inset measures ~17pt, so the
        // frame now spans the full width (inset 0) and the visible
        // capsule is expected at ~16pt, within ~1pt of the
        // reference. iPad unchanged.
        let barSideInset: CGFloat = isPadBar ? 16 : 0
        var barConstraints = [
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: barSideInset),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -barSideInset),
        ]
        if isPadBar {
            barConstraints.append(tabBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10))
        } else {
            // Lowered (build 63, user 2026-11-16 "把这个底栏下移一点
            // 按图二的高度"): the bar sits just above the home
            // indicator with only a small gap, like Apple's floating
            // tab bar in iOS 27.2 — anchored to the view bottom (not
            // the safe area) so it is the same height on iPhone and
            // iPad. Was safeArea.bottom - 4 (build 56), which left a
            // large gap above the home indicator.
            // Lowered again (26C101, user: the pill still floated too
            // high with a large gap under it): -18 -> -10, so the
            // pill's bottom edge sits ~10pt above the screen bottom,
            // snug above the home indicator like Apple's own floating
            // bars. iPhone portrait only — the iPad top bar and the
            // Duo sidebar are separate layouts, untouched.
            // Lowered to the reference (26E119, user: match the
            // reference bar's margins/height): the -10 above was the
            // FRAME's bottom edge, but the visible capsule does not
            // reach it — measured on the 26E117 device shot, the
            // capsule's bottom edge sits ~21pt above the frame's
            // bottom edge inside a standalone UITabBar (frame bottom
            // -10 -> capsule bottom 31pt above the screen bottom),
            // which is why the bar still floated high. The frame now
            // extends 8pt PAST the screen bottom (+8), so the
            // capsule is expected to land ~13pt above the screen
            // bottom, floating just over the home indicator like the
            // reference. The off-screen frame strip draws nothing —
            // the system background lives in the capsule region —
            // and reportBarFrame derives the web clearance from the
            // real frame, so page clearances follow automatically.
            // Raised a touch (26E121, user: 底栏稍微抬高一点点，不要
            // 碰到小白条）: at +8 the capsule's bottom edge sat ~13pt
            // above the screen bottom, visually crowding the home
            // indicator. The frame's bottom anchor goes +8 -> +3:
            // the whole bar rises 5pt, the capsule lands ~18pt above
            // the screen bottom with a clear gap over the indicator.
            // Still NO height constraint (the 26E112 lesson stands);
            // reportBarFrame reads the real frame, so --bar-clear
            // follows the new geometry on its own.
            barConstraints.append(tabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 3))
            // 26E115: on iPhone THIS UITabBar is the visible bottom
            // bar again — the system bar with its own Liquid Glass
            // and sliding selection capsule (see the appearance
            // branch above). The 26E113 hand-drawn replacement bar
            // is retired (the user ruled it "not Apple UI Liquid
            // Glass, cannot slide"). NO height constraint is set:
            // the bar lays out at its own intrinsic height (the
            // 26E112 experiment of pinning it to 62pt overflowed
            // its internal item layout and clipped the titles).
            // Its real frame is reported to the web (reportBarFrame)
            // so page bottom clearances follow the true bar, in
            // portrait and landscape alike.
        }
        NSLayoutConstraint.activate(barConstraints)
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

        // Left-edge swipe-back (26D104, restored): a screen-edge pan on
        // the root view. It is DISABLED by default and enabled only
        // while a sub-view is open (the same state that shows the
        // native back button), so it can never eat pans on the home /
        // map pages. UIScreenEdgePan begins only from the left edge,
        // so ordinary scrolls and the tab-bar swipes above are
        // unaffected while it is enabled.
        let edgePan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(subViewEdgePanBegan(_:)))
        edgePan.edges = .left
        edgePan.isEnabled = false
        view.addGestureRecognizer(edgePan)
        subViewEdgePan = edgePan

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
        // Above the floating tab bar (the system UITabBar on every
        // device since 26E115).
        let backButtonBarAnchor: NSLayoutYAxisAnchor = tabBar.topAnchor
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            backButton.bottomAnchor.constraint(equalTo: backButtonBarAnchor, constant: -16),
        ])

        // Native sub-view back button (user 2026-11-19): a real Apple UI
        // LARGE 50pt circular glass button (SF Symbol chevron.backward)
        // at the top-left, shown only while a web sub-view is open. It
        // replaces the old 34pt overlay, which sat a few points off the
        // web's own .more-sub-back / .tt-back button so both circles
        // showed at once (the double circle in the user's screenshot).
        // The web buttons are now hidden in the native app (template.html:
        // html.native-app .more-sub-back / .tt-back { visibility: hidden }),
        // so this native button is the only one. On iOS 26+ it uses the
        // SDK 27.2 UIButton.Configuration.glass() (real Liquid Glass);
        // below that it falls back to a makeGlassEffectView() subview
        // (UIGlassEffect .regular / .systemMaterial), same as the tab bar.
        // The chevron uses the adaptive label colour (.label: black in
        // light mode, white in dark mode).
        subViewBackButton = UIButton(type: .system)
        subViewBackButton.translatesAutoresizingMaskIntoConstraints = false
        subViewBackButton.tintColor = .label
        let subViewBackChevron = UIImage(systemName: "chevron.backward")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .bold))
        if #available(iOS 26.0, *) {
            var subViewBackConfig = UIButton.Configuration.glass()
            subViewBackConfig.image = subViewBackChevron
            subViewBackConfig.cornerStyle = .capsule
            subViewBackConfig.baseForegroundColor = .label
            subViewBackButton.configuration = subViewBackConfig
        } else {
            subViewBackButton.backgroundColor = .clear
            subViewBackButton.layer.cornerRadius = 20
            subViewBackButton.clipsToBounds = true
            let subViewBackGlass = makeGlassEffectView()
            subViewBackGlass.translatesAutoresizingMaskIntoConstraints = false
            subViewBackGlass.layer.cornerRadius = 20
            subViewBackGlass.clipsToBounds = true
            subViewBackGlass.isUserInteractionEnabled = false
            subViewBackButton.insertSubview(subViewBackGlass, at: 0)
            NSLayoutConstraint.activate([
                subViewBackGlass.leadingAnchor.constraint(equalTo: subViewBackButton.leadingAnchor),
                subViewBackGlass.trailingAnchor.constraint(equalTo: subViewBackButton.trailingAnchor),
                subViewBackGlass.topAnchor.constraint(equalTo: subViewBackButton.topAnchor),
                subViewBackGlass.bottomAnchor.constraint(equalTo: subViewBackButton.bottomAnchor),
            ])
            subViewBackButton.setImage(subViewBackChevron, for: .normal)
        }
        subViewBackButton.addTarget(self, action: #selector(subViewBackTapped), for: .touchUpInside)
        subViewBackButton.isHidden = true
        view.addSubview(subViewBackButton)
        // Top-left of the visible content area. On iPhone the top safe
        // area; on iPad the tab bar floats at the top, so sit below it
        // (same anchor as the native top pills) — otherwise the button
        // would land on top of the tab bar.
        let subViewBackTopAnchor: NSLayoutYAxisAnchor = (UIDevice.current.userInterfaceIdiom == .pad) ? tabBar.bottomAnchor : view.safeAreaLayoutGuide.topAnchor
        let subViewBackTopConstant: CGFloat = (UIDevice.current.userInterfaceIdiom == .pad) ? 10 : 8
        subBackLeadingConstraint = subViewBackButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 22)
        subBackTopConstraint = subViewBackButton.topAnchor.constraint(equalTo: subViewBackTopAnchor, constant: subViewBackTopConstant)
        NSLayoutConstraint.activate([
            subBackLeadingConstraint!,
            subBackTopConstraint!,
            subViewBackButton.widthAnchor.constraint(equalToConstant: 40),
            subViewBackButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        // Native Settings header (user 2026-11-19, iOS Settings style,
        // SDK 27.2 Liquid Glass): a frosted-glass strip across the top
        // safe area with a centred 17pt title and a hairline at its
        // bottom edge, shown while a Settings sub-view is open (the web
        // posts the sub-view's title with its "subView" message). The
        // web's own sub-view head is collapsed in the native app, the
        // content scrolls underneath the glass, and the back button
        // sits in the strip at the standard navigation position.
        // (User 2026-11-20 22:53: the strip now shows for the whole
        // time a sub-view is open — see applySubScrollState.)
        subHeaderGlass = makeGlassEffectView()
        subHeaderEffect = subHeaderGlass.effect // 26F128 H: kept so applySubScrollState can toggle the backdrop by scroll state.
        subHeaderGlass.translatesAutoresizingMaskIntoConstraints = false
        subHeaderGlass.isHidden = true
        view.addSubview(subHeaderGlass)
        subHeaderSep = UIView()
        subHeaderSep.backgroundColor = .separator
        subHeaderSep.translatesAutoresizingMaskIntoConstraints = false
        subHeaderGlass.contentView.addSubview(subHeaderSep)
        subHeaderTitle = UILabel()
        subHeaderTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        subHeaderTitle.textColor = .label
        subHeaderTitle.textAlignment = .center
        subHeaderTitle.translatesAutoresizingMaskIntoConstraints = false
        subHeaderGlass.contentView.addSubview(subHeaderTitle)
        let subHeaderTopAnchor: NSLayoutYAxisAnchor = (UIDevice.current.userInterfaceIdiom == .pad) ? tabBar.bottomAnchor : view.topAnchor
        subHeaderHeightConstraint = subHeaderGlass.heightAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([
            subHeaderGlass.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subHeaderGlass.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subHeaderGlass.topAnchor.constraint(equalTo: subHeaderTopAnchor),
            subHeaderHeightConstraint!,
            subHeaderSep.leadingAnchor.constraint(equalTo: subHeaderGlass.leadingAnchor),
            subHeaderSep.trailingAnchor.constraint(equalTo: subHeaderGlass.trailingAnchor),
            subHeaderSep.bottomAnchor.constraint(equalTo: subHeaderGlass.bottomAnchor),
            subHeaderSep.heightAnchor.constraint(equalToConstant: 0.5),
            subHeaderTitle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subHeaderTitle.centerYAnchor.constraint(equalTo: subViewBackButton.centerYAnchor),
            subHeaderTitle.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 76),
            subHeaderTitle.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -76),
        ])

        // iPad sub-view top cover (2026-11-22 fix, see the property
        // note): from the view's top edge down to the strip's bottom
        // edge — anchored to the strip's bottom anchor, so it follows
        // the strip's height automatically (44pt shown, 0 on static
        // pages, where it still covers the pill zone). Shown and faded
        // together with the rest of the sub-view chrome in
        // setSubChromeVisible; iPhone never creates it.
        if UIDevice.current.userInterfaceIdiom == .pad {
            let cover = UIView()
            cover.translatesAutoresizingMaskIntoConstraints = false
            cover.isHidden = true
            cover.backgroundColor = rootBackgroundColor()
            view.addSubview(cover)
            NSLayoutConstraint.activate([
                cover.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                cover.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                cover.topAnchor.constraint(equalTo: view.topAnchor),
                cover.bottomAnchor.constraint(equalTo: subHeaderGlass.bottomAnchor),
            ])
            subTopCover = cover
        }

        setupNativePills()
        // Splash fallback: if the web never posts splashDone, reveal the
        // controls after 4s anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.splashFinished()
        }
        setupSortTabs()
        setupStructChrome()
        setupThemeButtons()
        setupNearbySmartSwitch()
        setupTransferControls()
        setupActionButtons()
        setupProfileControls()
        setupMapCard()
        // Native launch splash (build 53, user 2026-11-15 "点进去为什么
        // 第一时刻没有开屏动画是白屏"): the web splash only appears after
        // the 6.7 MB page loads, so the first moment was a white screen
        // (blank LaunchScreen + blank web view). Show the current city's
        // splash image natively from launch — same image as the web
        // per-city splash — and hide it when the web posts splashDone.
        // currentCity was restored from UserDefaults above, so the image
        // matches the city the user last used.
        splashImageView = UIImageView()
        splashImageView.translatesAutoresizingMaskIntoConstraints = false
        splashImageView.clipsToBounds = true
        view.addSubview(splashImageView)
        // Pinned to the view's EDGES (not the safe area) so no strip
        // of root background can show above or below the poster.
        NSLayoutConstraint.activate([
            splashImageView.topAnchor.constraint(equalTo: view.topAnchor),
            splashImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splashImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splashImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        // refreshSplashImage owns the image, the content mode and the
        // background colour (26C101): fill on phone widths (poster
        // aspect ≈ phone aspect, so no letterbox at all), fit on
        // iPad / Duo widths with the background set to the picked
        // poster's OWN background colour, so any letterbox area is
        // invisible. The old code used aspect-fit everywhere and set
        // the background once from the appearance flag — in dark mode
        // a light poster then sat on black, which is exactly the
        // "black bars top and bottom" the user reported.
        refreshSplashImage()
        webView.addObserver(self, forKeyPath: "canGoBack", options: .new, context: nil)
        // App Intents in-process deep links (26C101): the rewritten
        // intents no longer open subwaymotion:// URLs through the
        // system (no OpenURLIntent); perform() posts this notification
        // and stashes the URL in UserDefaults. The notification covers
        // the running app; the didBecomeActive consume covers a cold
        // start where perform() ran before this controller existed.
        NotificationCenter.default.addObserver(self, selector: #selector(handleIntentDeepLink(_:)), name: SubwayDeepLink.notification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(consumePendingIntentDeepLink), name: UIApplication.didBecomeActiveNotification, object: nil)
        loadMap()
        // iPhone Duo sidebar (build 63): pick sidebar vs bottom tab
        // bar for the launch width; viewDidLayoutSubviews re-picks it
        // when the phone folds/unfolds.
        updateSideBarLayout()
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
            // Width class changed (fold/unfold, rotation) while the
            // splash is up: re-evaluate fill vs fit (26C101).
            refreshSplashImage()
        }
        // Every layout pass (rotation included, where only the
        // height may move): keep the web's --bar-clear in sync with
        // the system bar's real frame (26E115). Self-guarded:
        // unchanged values are not re-posted.
        reportBarFrame()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        view.backgroundColor = rootBackgroundColor()
        refreshSolidChrome() // 26F128: de-glassed pieces follow the theme.
        subTopCover?.backgroundColor = rootBackgroundColor() // iPad sub-view top cover follows the page background (2026-11-22).
        updateSideBarLayout()
        // Appearance changed while running (26C101): re-pick the
        // launch poster variant too — this hook previously refreshed
        // everything EXCEPT the splash, so a system appearance flip
        // with the splash still up kept the stale variant.
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            refreshSplashImage()
        }
    }

    func loadMap() {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    @objc func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    // Native sub-view back button tap (user 2026-11-18): the web owns
    // sub-view state, so this only asks the web to go back. The guarded
    // form never throws if window.metroApp or goBack() is absent (e.g. an
    // older cached page); the result is ignored.
    @objc func subViewBackTapped() {
        // Native Appearance picker: the web has no sub-view open while
        // the native picker is showing (it posted "openAppearance"
        // instead), so goBack() alone would do nothing — dismiss the
        // native view too. goBack() is still evaluated: it is a safe
        // no-op when the web has nothing open, and it closes a web
        // sub-view if one somehow is open.
        if appearanceView != nil { dismissAppearance() }
        if languageView != nil { dismissLanguage() }
        webView.evaluateJavaScript("window.metroApp && window.metroApp.goBack()", completionHandler: nil)
    }

    // Left-edge swipe-back (26D104): performs the identical action as
    // the native back button — dismisses a native picker if one is
    // showing and asks the web to goBack() (which closes an in-page
    // sub-view). The recognizer is only enabled while a sub-view is
    // open, so .began here always means "go back".
    @objc func subViewEdgePanBegan(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        guard recognizer.state == .began else { return }
        subViewBackTapped()
    }

    // Show/hide the native sub-view back button. Called from the "subView"
    // message handler. If the button was never created, there is nothing
    // to show — the web back button remains the fallback.
    func setSubViewBackButtonVisible(_ visible: Bool) {
        guard let button = subViewBackButton else { return }
        button.isHidden = !visible
        subViewEdgePan?.isEnabled = visible
        if visible { view.bringSubviewToFront(button) }
        updateCityPillLeading()
    }

    // 26E124: on the map tab the docked sub-view back button and
    // the city pill share the top-left corner — the button (40pt
    // at leading 22) covered the pill's left half (only the last
    // character of the city name showed). Whenever both are up,
    // the pill moves right of the button with the standard 8pt
    // gap; otherwise it keeps its 12pt home. The map tools pill
    // (top-right) and map pan/zoom are untouched.
    func updateCityPillLeading() {
        guard let c = cityPillLeadingConstraint else { return }
        let backUp = subViewBackButton != nil && !subViewBackButton.isHidden
        let pillUp = cityPill != nil && !cityPill.isHidden
        if backUp && pillUp {
            c.constant = (subBackLeadingConstraint?.constant ?? 22) + 40 + 8
        } else {
            c.constant = 12
        }
    }

    // Position the native back button exactly over the web back
    // button's centre (the web posts the centre with its "subView"
    // open message; the web button itself is visibility:hidden in the
    // native app, so the two can never show side by side or drift
    // apart — Settings sub-view heads and the timetable detail head
    // sit at different heights, which is why a fixed position was
    // wrong). The 40pt button is centred on the web button's centre.
    func positionSubViewBackButton(centerX: CGFloat, centerY: CGFloat) {
        guard let leading = subBackLeadingConstraint, let top = subBackTopConstraint else { return }
        let topBase: CGFloat = (UIDevice.current.userInterfaceIdiom == .pad) ? tabBar.frame.maxY : view.safeAreaInsets.top
        leading.constant = (centerX - 20) - view.safeAreaInsets.left
        top.constant = (centerY - 20) - topBase
        updateCityPillLeading()
    }

    // Docked position: inside the 44pt safe-area header strip — the
    // 40pt button centred in it (2pt inset), standard nav leading.
    // The top constraint is anchored to the safe area on iPhone, so
    // constant 2 centres the button in the strip; on iPad it is
    // anchored to the tab bar's bottom edge, whose strip is exactly
    // 44pt, so the same constant applies.
    func dockSubViewBackButton() {
        // Leading 22 (26C101, user: 不要太贴近安全区边缘): the button
        // breathes a little and roughly aligns with the 20pt content
        // margin instead of hugging the safe-area edge at 16.
        subBackLeadingConstraint?.constant = 22
        subBackTopConstraint?.constant = 2
        updateCityPillLeading()
    }

    func resetSubViewBackButtonPosition() {
        dockSubViewBackButton()
    }

    // Apply the header state (user 2026-11-20 22:53, superseding the
    // same-day "strip only after scrolling" design): while a sub-view
    // is open, the glass strip + centred title are always shown in the
    // safe-area header and the back button is always docked inside it
    // at the standard navigation position — the layout of the iOS
    // Settings sub-pages the user screenshotted (更新内容 / 无障碍).
    // Settings sub-views carry their title in the strip; the
    // timetable detail keeps its title in the web's .tt-title row, so
    // its strip shows no centred title but the button docks the same.
    // The strip is hidden only when no sub-view is open (handled by
    // setSubChromeVisible(false) in the subView message handler).
    func applySubScrollState(animated: Bool) {
        guard let glass = subHeaderGlass else { return }
        let chromeUp = subViewBackButton != nil && !subViewBackButton.isHidden
        // 26C102: on a static sub-view the strip never shows (see
        // subViewStatic) — the glass stays hidden at height 0 and the
        // back button floats alone over the page. Before this, the
        // glass was unhidden on every open while its height stayed at
        // the initial 44pt (the open-time refresh was skipped while
        // the button was still hidden), painting a tinted band with a
        // hard hairline edge across the status-bar zone of pages that
        // never scroll — the band the user boxed on the About page.
        let showStrip = chromeUp && !subViewStatic
        if chromeUp {
            // The title text refreshes on EVERY call while the chrome
            // is up, not only when the strip shows — together with the
            // reordered open branch this is the stale-title fix: the
            // previous page's title can no longer survive an open.
            subHeaderTitle.text = subDockTitle
            subHeaderHeightConstraint?.constant = subViewStatic ? 0 : ((UIDevice.current.userInterfaceIdiom == .pad) ? 44 : view.safeAreaInsets.top + 44)
        }
        // Visibility and alpha are owned by setSubChromeVisible (the
        // open/close fade); here we only refresh the title, the strip
        // height and the docked button position.
        if showStrip {
            glass.isHidden = false
            // 26F128 H (user: "再打开的时候不要显示安全区，滑动的时候
            // 显示安全区"): the glass backdrop + hairline ARE the
            // safe-area band — off while the page sits at its scroll
            // top (content runs flush to the top), on once scrolled.
            // The title (inside the strip) and the back button stay
            // visible either way; only the material toggles.
            glass.effect = subScrolled ? subHeaderEffect : nil
            subHeaderSep?.isHidden = !subScrolled
            self.view.bringSubviewToFront(glass)
            if let button = self.subViewBackButton { self.view.bringSubviewToFront(button) }
            self.dockSubViewBackButton()
        } else if chromeUp {
            glass.isHidden = true
            if let button = self.subViewBackButton { self.view.bringSubviewToFront(button) }
            self.dockSubViewBackButton()
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
                self.view.layoutIfNeeded()
            }
        } else {
            self.view.layoutIfNeeded()
        }
    }

    // iPad sub-view top cover (2026-11-22 fix): keep the cover's
    // colour equal to the page background underneath (rootBackground
    // is tab- and theme-aware: #f2f2f7 / #000 for Settings, #ffffff /
    // #000 for the timetable panel) and its z-order sandwiched as
    // webView < cover < tab bar < glass strip < back button, so the
    // pill keeps floating (and stays tappable) above the covered zone
    // while no web content can ever show through it. No-ops on iPhone
    // (subTopCover is nil there).
    func refreshSubTopCover() {
        guard let cover = subTopCover else { return }
        cover.backgroundColor = rootBackgroundColor()
        view.insertSubview(cover, aboveSubview: webView)
        view.bringSubviewToFront(tabBar)
        if let glass = subHeaderGlass { view.bringSubviewToFront(glass) }
        if let button = subViewBackButton { view.bringSubviewToFront(button) }
    }

    func setSubScrolled(_ scrolled: Bool) {
        guard subScrolled != scrolled else { return }
        subScrolled = scrolled
        applySubScrollState(animated: true)
    }

    // Leave sub-view mode entirely (sub-view closed): forget the
    // scroll state, dock title and frame centre. Visibility of the
    // strip and button is owned by setSubChromeVisible (the fade).
    func setSubViewHeader(title: String?) {
        if title == nil {
            subDockTitle = nil
            subTimetableMode = false
            subFrameCenter = nil
            subScrolled = false
            // 26C102: clear the label itself too — it previously kept
            // the last page's title text while hidden, and (with the
            // open-time refresh skipped) that stale text is what the
            // next page inherited.
            subHeaderTitle.text = nil
        }
    }

    // Animate the sub-view chrome (glass strip + title + back button)
    // in and out (user 2026-11-20 23:01: exiting a Settings sub-view
    // snapped shut with no animation). The web content's close slide
    // runs 0.45s ease-out (26D105: the .more-sub Vue transition's
    // leave), so the native chrome fades out over the same 0.45s.
    // Show: unhide at alpha 0, then fade to
    // 1. Hide: fade to 0, then hide for real and restore alpha 1 so
    // the next show starts clean. A re-open during the fade-out
    // cancels it (subChromeClosing flag + removing the animations).
    func setSubChromeVisible(_ visible: Bool) {
        guard let glass = subHeaderGlass, let button = subViewBackButton else { return }
        // 26E127 fix 12: the ghost "<" — the latch topChromeHidSubChrome is one-way: set when the top chrome hides while a subview is open, never cleared on close. Worse, the close branch below early-returns when the chrome is already hidden (a scroll-down hid it), so the latch survived the close — and the subView handler's setTopChromeHidden(false) right after re-showed the back button with no subview open. Reset the latch here (before the early-return guard) and track the real subview-open state for the re-show branch.
        subChromeOpen = visible
        if !visible { topChromeHidSubChrome = false }
        subViewEdgePan?.isEnabled = visible
        if visible {
            subChromeClosing = false
            glass.layer.removeAllAnimations()
            button.layer.removeAllAnimations()
            subTopCover?.layer.removeAllAnimations()
            let wasHidden = glass.isHidden && button.isHidden
            glass.isHidden = false
            button.isHidden = false
            // iPad top cover (2026-11-22 fix): show with the chrome,
            // recoloured and z-ordered under the pill/strip/button.
            if let cover = subTopCover {
                cover.isHidden = false
                refreshSubTopCover()
            }
            view.bringSubviewToFront(glass)
            view.bringSubviewToFront(button)
            if wasHidden {
                glass.alpha = 0
                button.alpha = 0
                subTopCover?.alpha = 0
                UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
                    glass.alpha = 1
                    button.alpha = 1
                    self.subTopCover?.alpha = 1
                }
            } else {
                glass.alpha = 1
                button.alpha = 1
                subTopCover?.alpha = 1
            }
        } else {
            guard !glass.isHidden || !button.isHidden else { return }
            subChromeClosing = true
            UIView.animate(withDuration: 0.45, delay: 0, options: [.curveEaseOut], animations: {
                glass.alpha = 0
                button.alpha = 0
                self.subTopCover?.alpha = 0
            }) { [weak self] _ in
                guard let self = self, self.subChromeClosing else { return }
                self.subChromeClosing = false
                glass.isHidden = true
                button.isHidden = true
                glass.alpha = 1
                button.alpha = 1
                if let cover = self.subTopCover {
                    cover.isHidden = true
                    cover.alpha = 1
                }
            }
        }
    }

    // 26E126 R + 26E127 fix 5: top chrome hides on scroll-down, returns on
    // scroll-up (user 2026-11-24). The web posts topChrome {hide}
    // from the #moreSheet scroll listener. 26E127 extends it from iPad
    // to iPhone: on iPad the pill + strip + back button hide; on iPhone
    // only the strip + back button hide — the bottom tab bar is not top
    // chrome. The splash / whatsnew gate owns visibility while either
    // page is up, so posts are ignored then. The sub-view strip is only
    // hidden when it was actually up (topChromeHidSubChrome) — on the
    // Settings root page there is no strip to hide, only the pill (iPad)
    // or nothing (iPhone). Force-shown again on sub-view open/close and
    // on every tab switch (setWebTab).
    var topChromeHidden = false
    var topChromeHidSubChrome = false
    var subChromeOpen = false // 26E127 fix 12: whether a native subview is actually open (the back-button latch above is one-way, so this is the real source of truth)
    func setTopChromeHidden(_ hidden: Bool) {
        guard !splashShowing && !whatsNewShowing else { return }
        if hidden == topChromeHidden { return }
        topChromeHidden = hidden
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if hidden {
            topChromeHidSubChrome = !(subHeaderGlass?.isHidden ?? true)
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut], animations: {
                if isPad { self.tabBar.alpha = 0 }
                self.subHeaderGlass?.alpha = 0
                self.subViewBackButton?.alpha = 0
                self.subTopCover?.alpha = 0
                if isPad { self.tabBar.transform = CGAffineTransform(translationX: 0, y: -12) }
                self.subHeaderGlass?.transform = CGAffineTransform(translationX: 0, y: -12)
                self.subViewBackButton?.transform = CGAffineTransform(translationX: 0, y: -12)
            }, completion: { _ in
                if isPad { self.tabBar.isHidden = true }
                if self.topChromeHidSubChrome {
                    self.subHeaderGlass?.isHidden = true
                    self.subViewBackButton?.isHidden = true
                    self.subTopCover?.isHidden = true
                }
            })
        } else {
            if isPad { tabBar.isHidden = false }
            if topChromeHidSubChrome && subChromeOpen {
                subHeaderGlass?.isHidden = false
                subViewBackButton?.isHidden = false
                subTopCover?.isHidden = false
                applySubScrollState(animated: false) // 26F128 H: re-assert the scroll-aware backdrop on re-show.
            } else if topChromeHidSubChrome {
                // 26E127 fix 12: stale latch (subview closed while the chrome was hidden) — drop it instead of re-showing a back button with no subview open.
                topChromeHidSubChrome = false
            }
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut], animations: {
                if isPad { self.tabBar.alpha = 1 }
                self.subHeaderGlass?.alpha = 1
                self.subViewBackButton?.alpha = 1
                self.subTopCover?.alpha = 1
                if isPad { self.tabBar.transform = .identity }
                self.subHeaderGlass?.transform = .identity
                self.subViewBackButton?.transform = .identity
            })
        }
    }

    // MARK: - Native Appearance picker (user 2026-11-19)

    // Present the native 外观 picker. Reads the current theme from the
    // web first so the picker shows the correct initial selection (which
    // card is checked, whether 自动 is ON); falls back to "system" if the
    // web is not ready. No-op if the picker is already showing.
    func presentAppearance() {
        guard appearanceView == nil else { return }
        webView.evaluateJavaScript("window.metroApp ? window.metroApp.theme : null") { [weak self] result, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.appearanceView == nil else { return }
                let theme = (result as? String).flatMap { ["system", "light", "dark"].contains($0) ? $0 : nil } ?? "system"
                let effectiveDark = self.traitCollection.userInterfaceStyle == .dark
                let picker = AppearanceView(
                    lightTitle: self.L("more.theme.light"),
                    darkTitle: self.L("more.theme.dark"),
                    autoTitle: self.L("more.theme.auto"),
                    appearanceTitle: self.L("more.appearance")
                )
                picker.onThemeChange = { [weak self] key in
                    self?.applyAppearanceTheme(key)
                }
                picker.lightPreview.refreshPoster(city: self.currentCity)
                picker.darkPreview.refreshPoster(city: self.currentCity)
                picker.configure(theme: theme, effectiveDark: effectiveDark)
                picker.translatesAutoresizingMaskIntoConstraints = false
                // Entry animation (user 2026-11-19, 进入动画优化）:
                // slide in from the right + fade, like an iOS push.
                picker.alpha = 0
                picker.transform = CGAffineTransform(translationX: 24, y: 0)
                self.view.addSubview(picker)
                NSLayoutConstraint.activate([
                    picker.topAnchor.constraint(equalTo: self.view.topAnchor),
                    picker.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                    picker.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                    picker.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
                ])
                self.appearanceView = picker
                // The native back button must stay on top of the picker
                // (the picker covers the web view, tab bar and pills).
                // Reset its position first: a frame-synced position left
                // over from a web sub-view overlaps the picker's title
                // (user 2026-11-20 screenshot: button on top of 语言).
                self.resetSubViewBackButtonPosition()
                self.setSubViewBackButtonVisible(true)
                UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                    picker.alpha = 1
                    picker.transform = .identity
                }
            }
        }
    }

    func dismissAppearance() {
        guard let picker = appearanceView else { return }
        appearanceView = nil
        setSubViewBackButtonVisible(false)
        // 26D105: slower, ease-out close (matches the shared back path).
        UIView.animate(withDuration: 0.45, delay: 0, options: [.curveEaseOut], animations: {
            picker.alpha = 0
            picker.transform = CGAffineTransform(translationX: 24, y: 0)
        }, completion: { _ in picker.removeFromSuperview() })
    }

    // MARK: - Native Language picker (user 2026-11-19)

    // The name of the system language, shown on the right of the
    // 跟随系统 row (mirrors the web's langDisplayName for the system
    // language).
    func systemLangDisplayName() -> String {
        switch Self.systemLang() {
        case "zh-Hant": return L("more.lang.hant")
        case "en": return L("more.lang.en")
        default: return L("more.lang.hans")
        }
    }

    // Present the native 语言 picker. Reads the web's langPref first so
    // the checkmark starts on the current choice; falls back to
    // "system" if the web is not ready. No-op if already showing.
    func presentLanguage() {
        guard languageView == nil else { return }
        webView.evaluateJavaScript("window.metroApp ? window.metroApp.langPref : null") { [weak self] result, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.languageView == nil else { return }
                let pref = (result as? String).flatMap { ["system", "zh-Hans", "zh-Hant", "en"].contains($0) ? $0 : nil } ?? "system"
                let picker = LanguageView(
                    pageTitle: self.L("more.lang"),
                    systemTitle: self.L("more.lang.system"),
                    hansTitle: self.L("more.lang.hans"),
                    hantTitle: self.L("more.lang.hant"),
                    enTitle: self.L("more.lang.en"),
                    systemDetail: self.systemLangDisplayName()
                )
                picker.onSelect = { [weak self] key in
                    self?.applyLanguageChoice(key)
                }
                picker.configure(selected: pref)
                picker.translatesAutoresizingMaskIntoConstraints = false
                // Entry animation: slide in from the right + fade,
                // like an iOS push (same as the Appearance picker).
                picker.alpha = 0
                picker.transform = CGAffineTransform(translationX: 24, y: 0)
                self.view.addSubview(picker)
                NSLayoutConstraint.activate([
                    picker.topAnchor.constraint(equalTo: self.view.topAnchor),
                    picker.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                    picker.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                    picker.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
                ])
                self.languageView = picker
                self.resetSubViewBackButtonPosition()
                self.setSubViewBackButtonVisible(true)
                UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                    picker.alpha = 1
                    picker.transform = .identity
                }
            }
        }
    }

    func dismissLanguage() {
        guard let picker = languageView else { return }
        languageView = nil
        setSubViewBackButtonVisible(false)
        // 26D105: slower, ease-out close (matches the shared back path).
        UIView.animate(withDuration: 0.45, delay: 0, options: [.curveEaseOut], animations: {
            picker.alpha = 0
            picker.transform = CGAffineTransform(translationX: 24, y: 0)
        }, completion: { _ in picker.removeFromSuperview() })
    }

    // Apply a language picked in the native picker. The web owns the
    // language state: its setLang() switches the UI and posts
    // langChanged, which native setLang() then persists (metro-lang /
    // metro-lang-explicit) — so do NOT persist anything here.
    func applyLanguageChoice(_ key: String) {
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setLang('\(key)')", completionHandler: nil)
    }

    // Apply a theme picked in the native picker. Reuses the web's
    // setTheme()/applyTheme() (guarded form, same as themeButtonTapped),
    // so web and native stay in sync. No local theme state is kept.
    func applyAppearanceTheme(_ key: String) {
        // 26C102: persist the choice natively too, not only via the
        // web's themeState post — the launch splash reads metro-theme
        // / metro-dark at viewDidLoad, and on device those posts
        // alone left the splash on the stale appearance.
        UserDefaults.standard.set(key, forKey: "metro-theme")
        let dark = key == "dark" || (key == "system" && traitCollection.userInterfaceStyle == .dark)
        UserDefaults.standard.set(dark, forKey: "metro-dark")
        themeResolvedThisSession = true
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setTheme('\(key)')", completionHandler: nil)
    }

    // MARK: - Native Liquid Glass top pills

    // The two top pills are native UIButtons with Apple's true Liquid
    // Glass (UIButton.Configuration.glass(), iOS 26+; a frosted blur
    // fallback on older iOS). CSS backdrop-filter can only approximate
    // Liquid Glass, which is why the web pills kept being rejected.
    // Beijing keeps its blue theme; Shenyang uses gold.
    func setupNativePills() {
        cityPill = UIButton(type: .system)
        // Map tools pill (top-right, build 74): one Liquid Glass capsule
        // with a my-location arrow + station search, matching the Apple
        // UI reference the user sent. The two icon buttons sit inside it.
        mapToolsPill = UIView()
        mapToolsPill.translatesAutoresizingMaskIntoConstraints = false
        locateButton = UIButton(type: .system)
        locateButton.translatesAutoresizingMaskIntoConstraints = false
        locateButton.setImage(UIImage(systemName: "location.fill"), for: .normal)
        locateButton.addTarget(self, action: #selector(centerOnMyLocation), for: .touchUpInside)
        searchPill = UIButton(type: .system)
        searchPill.translatesAutoresizingMaskIntoConstraints = false
        searchPill.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        searchPill.addTarget(self, action: #selector(openStationSearch), for: .touchUpInside)
        resetZoomButton = UIButton(type: .system)
        resetZoomButton.translatesAutoresizingMaskIntoConstraints = false
        resetZoomButton.setImage(UIImage(systemName: "arrow.counterclockwise"), for: .normal)
        resetZoomButton.addTarget(self, action: #selector(resetMapZoom), for: .touchUpInside)
        let divider2 = UIView()
        divider2.translatesAutoresizingMaskIntoConstraints = false
        divider2.backgroundColor = UIColor(white: 1, alpha: 0.35)
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor(white: 1, alpha: 0.35)
        mapToolsPill.addSubview(locateButton)
        mapToolsPill.addSubview(divider)
        mapToolsPill.addSubview(resetZoomButton)
        mapToolsPill.addSubview(divider2)
        mapToolsPill.addSubview(searchPill)
        cityPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cityPill)
        view.addSubview(mapToolsPill)
        // Pills sit at the top safe area on iPhone. On iPad the tab bar
        // floats at the top (build 74), so the pills sit below it.
        cityPillLeadingConstraint = cityPill.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12)
        let pillTopAnchor: NSLayoutYAxisAnchor = (UIDevice.current.userInterfaceIdiom == .pad) ? tabBar.bottomAnchor : view.safeAreaLayoutGuide.topAnchor
        NSLayoutConstraint.activate([
            cityPillLeadingConstraint!,
            cityPill.topAnchor.constraint(equalTo: pillTopAnchor, constant: 10),
            mapToolsPill.trailingAnchor.constraint(equalTo: webView.trailingAnchor, constant: -12), // The content's right edge: with the Duo sidebar active this sits just left of the sidebar; otherwise it is the screen edge (the safe area inset left it floating mid-screen on the Duo).
            mapToolsPill.topAnchor.constraint(equalTo: pillTopAnchor, constant: 10),
            mapToolsPill.heightAnchor.constraint(equalToConstant: 36),
            locateButton.leadingAnchor.constraint(equalTo: mapToolsPill.leadingAnchor, constant: 4),
            locateButton.topAnchor.constraint(equalTo: mapToolsPill.topAnchor),
            locateButton.bottomAnchor.constraint(equalTo: mapToolsPill.bottomAnchor),
            locateButton.widthAnchor.constraint(equalToConstant: 44),
            divider.leadingAnchor.constraint(equalTo: locateButton.trailingAnchor),
            divider.centerYAnchor.constraint(equalTo: mapToolsPill.centerYAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 20),
            resetZoomButton.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            resetZoomButton.topAnchor.constraint(equalTo: mapToolsPill.topAnchor),
            resetZoomButton.bottomAnchor.constraint(equalTo: mapToolsPill.bottomAnchor),
            resetZoomButton.widthAnchor.constraint(equalToConstant: 44),
            divider2.leadingAnchor.constraint(equalTo: resetZoomButton.trailingAnchor),
            divider2.centerYAnchor.constraint(equalTo: mapToolsPill.centerYAnchor),
            divider2.widthAnchor.constraint(equalToConstant: 1),
            divider2.heightAnchor.constraint(equalToConstant: 20),
            searchPill.leadingAnchor.constraint(equalTo: divider2.trailingAnchor),
            searchPill.trailingAnchor.constraint(equalTo: mapToolsPill.trailingAnchor, constant: -4),
            searchPill.topAnchor.constraint(equalTo: mapToolsPill.topAnchor),
            searchPill.bottomAnchor.constraint(equalTo: mapToolsPill.bottomAnchor),
            searchPill.widthAnchor.constraint(equalToConstant: 44),
        ])
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
        if currentCity == "cc" { return changchunRed }
        if currentCity == "sz" { return shenzhenGreen }
        if currentCity == "cd" { return chengduBlue }
        if currentCity == "qd" { return qingdaoGreen }
        if currentCity == "sjz" { return shijiazhuangRed }
        if currentCity == "tj" { return tianjinRed }
        if currentCity == "wx" { return wuxiRed }
        if currentCity == "ly" { return luoyangPink }
        if currentCity == "gz" { return guangzhouYellow }
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
        if currentCity == "cc" { return changchunRedDark }
        if currentCity == "sz" { return shenzhenGreenDark }
        if currentCity == "cd" { return chengduBlueDark }
        if currentCity == "qd" { return qingdaoGreenDark }
        if currentCity == "sjz" { return shijiazhuangRedDark }
        if currentCity == "tj" { return tianjinRedDark }
        if currentCity == "wx" { return wuxiRedDark }
        if currentCity == "ly" { return luoyangPinkDark }
        if currentCity == "gz" { return guangzhouYellowDark }
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
        if currentCity == "cc" { return changchunRed }
        if currentCity == "sz" { return shenzhenGreen }
        if currentCity == "cd" { return chengduBlue }
        if currentCity == "qd" { return qingdaoGreen }
        if currentCity == "sjz" { return shijiazhuangRed }
        if currentCity == "tj" { return tianjinRed }
        if currentCity == "wx" { return wuxiRed }
        if currentCity == "ly" { return luoyangPink }
        if currentCity == "gz" { return guangzhouYellowDark }
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
        case "cc": name = "ChangchunLogo"
        case "sz": name = "ShenzhenLogo"
        case "cd": name = "ChengduLogo"
        case "qd": name = "QingdaoLogo"
        case "sjz": name = "ShijiazhuangLogo"
        case "tj": name = "TianjinLogo"
        case "wx": name = "WuxiLogo"
        case "ly": name = "LuoyangLogo"
        case "gz": name = "GuangzhouLogo"
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
            cityPill.applyAppleCorner(radius: 18)
            cityPill.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 12)
        }
        // UIMenu anchored to this pill (top-left): tapping the pill pops
        // the city menu up right under it, not in the middle of the screen.
        cityPill.menu = cityMenu()
        cityPill.showsMenuAsPrimaryAction = true
    }

    func updateSearchPill() {
        // The tools pill is one glass capsule (shared makeGlassEffectView,
        // Liquid Glass on iOS 26+); the two icon buttons inside take the
        // city accent colour. Rebuilt each call so a city switch re-tints.
        mapToolsPill.subviews.filter { $0 is UIVisualEffectView }.forEach { $0.removeFromSuperview() }
        let effectView = makeGlassEffectView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.applyAppleCorner(radius: 18)
        mapToolsPill.insertSubview(effectView, at: 0)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: mapToolsPill.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: mapToolsPill.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: mapToolsPill.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: mapToolsPill.bottomAnchor),
        ])
        mapToolsPill.applyAppleCorner(radius: 18)
        mapToolsPill.clipsToBounds = true
        locateButton.tintColor = accentColor()
        resetZoomButton.tintColor = accentColor()
        searchPill.tintColor = accentColor()
    }

    // 26E126 J: maps on demand. The city pill menu lists all 16
    // cities; a downloaded city switches at once, an undownloaded
    // one shows a "↓" affordance and downloads first, then
    // switches (never a dead end). Beijing's default (track) map
    // comes from its own loadProd path, so 'bj' is always ready.
    // The set is fed by the web's mapState posts and is rebuilt
    // whenever it changes.
    var downloadedMapCities: Set<String> = ["bj"]
    // Line maps actually downloaded (bj counts only when its LINE
    // map is ready) — same number the web status line shows.
    var downloadedLineMapCount: Int = 0
    // 26E127 fix 6: the popover lists ONLY downloaded cities (bj always counts as downloaded) — undownloaded cities no longer appear here; download them in Settings → Switch City. (26E126 J showed all with a ↓ mark; the user changed this.)
    func cityMenu() -> UIMenu {
        let keys = ["bj", "sy", "sh", "hb", "dl", "jh", "cz", "cq", "cc", "sz", "cd", "qd", "sjz", "tj", "wx", "ly", "gz"].filter { $0 == "bj" || downloadedMapCities.contains($0) }
        var actions: [UIAction] = []
        for key in keys {
            let a = UIAction(title: L("city." + key), image: cityLogoImage(for: key)?.withRenderingMode(.alwaysOriginal)) { [weak self] _ in
                self?.pickCity(key)
            }
            actions.append(a)
        }
        return UIMenu(title: "", children: actions)
    }

    // Download one city's line map via the web (which switches to
    // it when the download lands); the web's cityChanged post then
    // mirrors the switch natively, so no local sync is needed here.
    func downloadCityMap(_ city: String) {
        webView.evaluateJavaScript("window.metroApp && window.metroApp.downloadCityMap('\(city)')", completionHandler: nil)
    }

    // Native "download all line maps" control, positioned over the
    // web's #mapsDownloadSlot in the city sub-page (same frame
    // pattern as placeSwitch: dict + webOffset, hidden unless the
    // Settings tab is up and no splash/update page is showing).
    var mapsDownloadContainer: UIView?
    var mapsDownloadButton: UIButton?
    var mapsDownloadProgress: UIProgressView?
    var mapsDownloadLabel: UILabel?
    func placeMapsDownload(frame dict: [String: Any]) {
        let x = ((dict["x"] as? Double) ?? 0) + webOffset.x
        let y = ((dict["y"] as? Double) ?? 0) + webOffset.y
        let w = (dict["width"] as? Double) ?? 0
        let h = (dict["height"] as? Double) ?? 0
        guard w > 0 && h > 0 && currentTab == "more" && !splashShowing && !whatsNewShowing else {
            mapsDownloadContainer?.isHidden = true
            return
        }
        if mapsDownloadContainer == nil {
            let c = UIView()
            c.backgroundColor = .clear
            let btn = UIButton(type: .system)
            btn.setTitle(L("map.downloadAll"), for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            btn.backgroundColor = .systemBlue
            btn.setTitleColor(.white, for: .normal)
            btn.layer.cornerRadius = 10
            btn.addTarget(self, action: #selector(mapsDownloadTapped), for: .touchUpInside)
            let prog = UIProgressView(progressViewStyle: .default)
            prog.isHidden = true
            let lbl = UILabel()
            lbl.font = .systemFont(ofSize: 13)
            lbl.textColor = .secondaryLabel
            lbl.textAlignment = .center
            lbl.text = L("map.downloaded").replacingOccurrences(of: "{n}", with: "\(downloadedLineMapCount)")
            c.addSubview(btn); c.addSubview(prog); c.addSubview(lbl)
            btn.translatesAutoresizingMaskIntoConstraints = false
            prog.translatesAutoresizingMaskIntoConstraints = false
            lbl.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                btn.topAnchor.constraint(equalTo: c.topAnchor), btn.leadingAnchor.constraint(equalTo: c.leadingAnchor), btn.trailingAnchor.constraint(equalTo: c.trailingAnchor), btn.heightAnchor.constraint(equalToConstant: 44),
                prog.topAnchor.constraint(equalTo: btn.bottomAnchor, constant: 8), prog.leadingAnchor.constraint(equalTo: c.leadingAnchor), prog.trailingAnchor.constraint(equalTo: c.trailingAnchor),
                lbl.topAnchor.constraint(equalTo: prog.bottomAnchor, constant: 6), lbl.leadingAnchor.constraint(equalTo: c.leadingAnchor), lbl.trailingAnchor.constraint(equalTo: c.trailingAnchor), lbl.bottomAnchor.constraint(equalTo: c.bottomAnchor)
            ])
            view.addSubview(c)
            mapsDownloadContainer = c; mapsDownloadButton = btn; mapsDownloadProgress = prog; mapsDownloadLabel = lbl
        }
        let rect = CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
        mapsDownloadContainer?.frame = rect
        mapsDownloadContainer?.isHidden = false
        view.bringSubviewToFront(mapsDownloadContainer!)
    }

    @objc func mapsDownloadTapped() {
        webView.evaluateJavaScript("window.metroApp && window.metroApp.downloadAllMaps()", completionHandler: nil)
    }

    func updateMapsDownloadUI(done: Int, total: Int) {
        guard let prog = mapsDownloadProgress, let lbl = mapsDownloadLabel, let btn = mapsDownloadButton else { return }
        if total > 0 && done < total {
            prog.isHidden = false
            prog.progress = Float(done) / Float(total)
            lbl.text = L("map.downloadingCount").replacingOccurrences(of: "{done}", with: "\(done)").replacingOccurrences(of: "{total}", with: "\(total)")
            btn.setTitle(L("map.downloading"), for: .normal)
            btn.isEnabled = false
        } else {
            // Finished (done == total) or nothing to do (total == 0):
            // back to the idle state with the fresh count.
            prog.isHidden = true
            lbl.text = L("map.downloaded").replacingOccurrences(of: "{n}", with: "\(downloadedLineMapCount)")
            btn.setTitle(L("map.downloadAll"), for: .normal)
            btn.isEnabled = true
        }
    }

    // MARK: - Per-city native download buttons (26E127 fix 4)

    // One small Liquid Glass button per un-downloaded city row in the
    // city sub-page (web .more-city-dl-slot), placed over the slot rect
    // the web reports via "cityDownloadFrame" (same frame pattern as
    // placeMapsDownload: dict + webOffset, zero rect hides). Tapping a
    // button runs the same download-then-switch flow as tapping the row
    // (window.metroApp.onCityRowTap); the web keeps its text span as
    // the pure-browser fallback.
    var cityDownloadButtons: [String: UIButton] = [:]
    func makeCityDownloadButton(key: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = true
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btn.accessibilityIdentifier = key
        if #available(iOS 26.0, *) {
            var cfg = UIButton.Configuration.glass()
            cfg.cornerStyle = .capsule
            cfg.baseForegroundColor = .systemBlue
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
            cfg.title = L("map.download")
            btn.configuration = cfg
        } else {
            btn.tintColor = .systemBlue
        }
        btn.setTitle(L("map.download"), for: .normal)
        btn.addTarget(self, action: #selector(cityDownloadTapped(_:)), for: .touchUpInside)
        btn.isHidden = true
        view.addSubview(btn)
        cityDownloadButtons[key] = btn
        return btn
    }

    // MARK: - Cellular path monitor (26E127 fix 7, 26F128 switch)

    // NWPathMonitor watches the network path so the web's cellularGate()
    // knows whether a download would use cellular data. The flag is
    // injected at document start (false = Wi-Fi, the safe default) and
    // re-asserted on every path change. 26F128: the once-per-session
    // prompt is gone — the web's Settings > General switch
    // (metro-allow-cellular, default on) is the control now.
    var networkMonitor: NWPathMonitor?
    func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let cellular = path.usesInterfaceType(.cellular)
            DispatchQueue.main.async {
                self?.webView?.evaluateJavaScript("window._metroIsCellular = \(cellular ? "true" : "false");", completionHandler: nil)
            }
        }
        monitor.start(queue: DispatchQueue(label: "metro.networkMonitor"))
        networkMonitor = monitor
    }

    // MARK: - Native depart-time button (26E127 fix 11, 26F128 round)

    // The web reports the .tr-time-slot rect + the current title +
    // the theme-correct walking-person icon (only when it changes).
    // 26F128 (user 2026-11-25 "改成圆形按钮 就保留图标"): the button
    // is a SOLID CIRCLE carrying only the walking-person glyph — no
    // title, no ▾ (the posted title becomes the accessibility
    // label), no glass. The web slot is square (40x40), so the
    // circle is the slot frame with cornerRadius = half the side.
    // Tap opens the same departure-time picker as the web control
    // (web showTimePicker → native timePicker).
    var departButton: UIButton?
    var departButtonIcon: UIImage?
    var departButtonIconURL = ""
    func placeDepartButton(frame dict: [String: Any]) {
        let x = ((dict["x"] as? Double) ?? 0) + webOffset.x
        let y = ((dict["y"] as? Double) ?? 0) + webOffset.y
        let w = (dict["width"] as? Double) ?? 0
        let h = (dict["height"] as? Double) ?? 0
        let title = (dict["title"] as? String) ?? ""
        guard w > 0 && h > 0 && currentTab == "transfer" && !splashShowing && !whatsNewShowing else {
            departButton?.isHidden = true
            return
        }
        let btn = departButton ?? makeDepartButton()
        if let icon = dict["icon"] as? String, !icon.isEmpty, icon != departButtonIconURL {
            departButtonIconURL = icon
            departButtonIcon = decodeDepartIcon(icon)
        }
        btn.setImage(departButtonIcon, for: .normal)
        btn.accessibilityLabel = title
        btn.backgroundColor = solidCardColor()
        btn.frame = CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
        btn.layer.cornerRadius = min(btn.frame.width, btn.frame.height) / 2
        btn.isHidden = false
        view.bringSubviewToFront(btn)
    }
    func makeDepartButton() -> UIButton {
        let btn = UIButton(type: .custom)
        btn.translatesAutoresizingMaskIntoConstraints = true
        btn.accessibilityIdentifier = "departButton"
        btn.clipsToBounds = true
        btn.backgroundColor = solidCardColor()
        btn.addTarget(self, action: #selector(departButtonTapped), for: .touchUpInside)
        btn.isHidden = true
        view.addSubview(btn)
        departButton = btn
        return btn
    }
    @objc func departButtonTapped() {
        // Same entry as the web control's tap: ask the web to open the departure-time picker (native SearchConditions sheet via the timePicker handler).
        webView?.evaluateJavaScript("window.metroApp && window.metroApp.showTimePicker()", completionHandler: nil)
    }
    func decodeDepartIcon(_ dataURL: String) -> UIImage? {
        // The web posts the themed walking-person template
        // (luminance→alpha: dark figure in light mode, light figure
        // in dark mode). Decode it as-is (alwaysOriginal — the web
        // already themed it to the app appearance, not the system
        // one) and scale it to the button height; fall back to nil
        // (title only) if the data URL is malformed.
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let b64 = String(dataURL[dataURL.index(after: comma)...])
        guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
              let img = UIImage(data: data) else { return nil }
        let target = CGSize(width: 24, height: 24) // 26F128: ~60% of the 40pt circle's diameter.
        let scaled = UIGraphicsImageRenderer(size: target).image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.withRenderingMode(.alwaysOriginal)
    }
    @objc func cityDownloadTapped(_ sender: UIButton) {
        guard let key = sender.accessibilityIdentifier, !key.isEmpty else { return }
        webView.evaluateJavaScript("window.metroApp && window.metroApp.onCityRowTap('\(key)')", completionHandler: nil)
    }
    func placeCityDownloadButtons(frames: [[String: Any]]) {
        let keys = Set(frames.compactMap { $0["key"] as? String })
        for (k, b) in cityDownloadButtons where !keys.contains(k) { b.isHidden = true }
        guard currentTab == "more" && !splashShowing && !whatsNewShowing else {
            for b in cityDownloadButtons.values { b.isHidden = true }
            return
        }
        for f in frames {
            guard let key = f["key"] as? String else { continue }
            let x = ((f["x"] as? Double) ?? 0) + webOffset.x
            let y = ((f["y"] as? Double) ?? 0) + webOffset.y
            let w = (f["width"] as? Double) ?? 0
            let h = (f["height"] as? Double) ?? 0
            let state = (f["state"] as? String) ?? "download"
            let btn = cityDownloadButtons[key] ?? makeCityDownloadButton(key: key)
            let title: String
            switch state {
            case "loading":
                title = L("map.downloadingShort")
                btn.isEnabled = false
            case "error":
                title = L("map.retry")
                btn.isEnabled = true
            default:
                title = L("map.download")
                btn.isEnabled = true
            }
            btn.configuration?.title = title
            btn.setTitle(title, for: .normal)
            if w > 0 && h > 0 {
                btn.frame = CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
                btn.isHidden = false
                view.bringSubviewToFront(btn)
            } else {
                btn.isHidden = true
            }
        }
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
            // 26E127 fix 6: only downloaded cities appear here (same rule as cityMenu) — no ↓ mark anymore; download in Settings → Switch City.
            let a = UIAlertAction(title: (currentCity == city ? "✓ " : "") + L("city." + city), style: .default) { [weak self] _ in
                self?.pickCity(city)
            }
            if let img = cityLogoImage(for: city)?.withRenderingMode(.alwaysOriginal) {
                a.setValue(img, forKey: "image")
            }
            return a
        }
        // 26E127 fix 6: same rule as cityMenu — downloaded cities only (bj always counts), so the popover never offers a city whose map is not on the device.
        for city in ["bj", "sy", "sh", "hb", "dl", "jh", "cz", "cq", "cc", "sz", "cd", "qd", "sjz", "tj", "wx", "ly", "gz"] where city == "bj" || downloadedMapCities.contains(city) {
            sheet.addAction(cityAction(city))
        }
        sheet.addAction(UIAlertAction(title: L("native.cancel"), style: .cancel))
        sheet.modalPresentationStyle = .popover
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = cityPill.frame
            pop.permittedArrowDirections = .up
        }
        present(sheet, animated: true)
    }

    // Shared city-UI refresh (build 37): back-button
    // color, pills and transfer controls for the current city. Used
    // by pickCity() (native-initiated) and the cityChanged handler
    // (web-initiated, incl. the startup restore). (The tab-bar tint
    // is NOT refreshed here any more: 26E112 pins it to system blue,
    // independent of the city.)
    func refreshCityUI() {
        backButton.layer.borderColor = accentDark().cgColor
        backButton.setTitleColor(accentDark(), for: .normal)
        updateCityPill()
        updateSearchPill()
        updateSideBarSelection()
        clearTransferFields()
        updateTransferTint()
        // 26E110 ghost fix: do NOT refresh the action pills here —
        // the cached transit label is still the OLD city's at this
        // point, so refreshing painted a stale configuration first
        // and the real one a beat later (see refreshActionButtons).
        // Hide the pills instead; the next transferFrame post from
        // the web carries the new city's settled label + icons and
        // placeTransfer refreshes the contents and unhides them in
        // the same pass. Briefly hidden beats doubled.
        hideActionButtons()
    }

    func pickCity(_ city: String) {
        // Always sync the web, even when native already thinks it is on
        // this city (build 74 fix for "切到沈阳还是北京图"): native and
        // web can drift — e.g. a switch tapped before the web finished
        // loading is skipped by the `window.metroApp &&` guard while
        // native still saves the city — and the old early return then
        // made the stuck state unfixable by re-tapping the same city.
        // The web's own guard no-ops when it is already on that city.
        let changed = city != currentCity
        currentCity = city
        UserDefaults.standard.set(city, forKey: "metro-city")
        if changed { refreshCityUI() }
        webView.evaluateJavaScript("window.metroApp && window.metroApp.switchCity('\(city)')", completionHandler: nil)
    }

    @objc func openStationSearch() {
        webView.evaluateJavaScript("window.metroApp && window.metroApp.openStations()", completionHandler: nil)
    }

    // Top-right pill location arrow: find nearby stations from the
    // user's current location (same as the Settings nearby feature).
    @objc func resetMapZoom() {
        webView.evaluateJavaScript("if (window.resetView) { window.resetView(); }", completionHandler: nil)
    }

    @objc func centerOnMyLocation() {
        requestNearbyLocation()
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
        // 26F128: solid segmented colours (user "取消玻璃效果") —
        // classic track/pill pair instead of the glass rendering.
        sortTabs.backgroundColor = solidTrackColor()
        sortTabs.selectedSegmentTintColor = solidPillColor()
        sortTabs.clipsToBounds = true
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
        // 26E126: the route-detail page covers the transfer panel —
        // its native chrome must hide while the detail is open, or
        // it floats over the detail page (user screenshot, 26E125:
        // the search card covered the detail). The web re-posts
        // detailOpen with every frame report, so the state
        // re-asserts itself after tab switches.
        if dict["detailOpen"] as? Bool == true {
            sortTabs.isHidden = true
            return
        }
        if w > 0 && h > 0 && currentTab == "transfer" {
            sortTabs.frame = CGRect(x: x + webOffset.x, y: y + webOffset.y, width: w, height: h)
            sortTabs.layer.cornerRadius = CGFloat(h) / 2 // 26F128: round the solid track to the control's capsule.
            sortTabs.isHidden = false
            if let idx = sortTabKeys.firstIndex(of: tab) {
                sortTabs.selectedSegmentIndex = idx
            }
        } else {
            sortTabs.isHidden = true
        }
    }

    // MARK: - Native structure-detail chrome (test/structure, 26E107)

    // The structure detail's 空间结构/平面示意 switch is a native
    // UISegmentedControl (Liquid Glass on iOS 26+); its header
    // carries a native circular glass 搜索 button on the right
    // (magnifyingglass only, no title since 26E109 — back to the
    // search list + focus the input) and, since 26E108, a circular
    // glass chevron 退出 button on the left — the same button as
    // every sub-view's native back button. Same overlay pattern
    // as sortTabs: the web keeps
    // invisible placeholders (.struct-seg / .struct-actions /
    // .tt-back), reports their frames via "structFrame", and the
    // native controls sit exactly on top. Both segments stay
    // enabled even when that kind has no diagram — the web then
    // shows its 正在整理 placeholder, which keeps the control's
    // behaviour predictable.
    func setupStructChrome() {
        structSeg = UISegmentedControl(items: [L("struct.spatial"), L("struct.plan")])
        structSeg.selectedSegmentIndex = 0
        structSeg.translatesAutoresizingMaskIntoConstraints = true
        structSeg.isHidden = true
        structSeg.addTarget(self, action: #selector(structSegChanged(_:)), for: .valueChanged)
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14, weight: .semibold)]
        structSeg.setTitleTextAttributes(attrs, for: .normal)
        structSeg.setTitleTextAttributes(attrs, for: .selected)
        view.addSubview(structSeg)
        // Search (26E109, user: 结构页搜索按钮只留图标): a 40pt
        // circular glass button with ONLY the magnifyingglass —
        // no 「搜索」 title — built exactly like the exit chevron
        // below (glass capsule config on iOS 26+, glass effect
        // view behind the glyph below that). It centres on the
        // web title row's .struct-actions slot, a 40x40 square
        // since 26E109 (placeStructChrome).
        structSearchButton = UIButton(type: .system)
        structSearchButton.translatesAutoresizingMaskIntoConstraints = true
        structSearchButton.isHidden = true
        structSearchButton.tintColor = .label
        let structSearchGlyph = UIImage(systemName: "magnifyingglass")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        if #available(iOS 26.0, *) {
            var searchCfg = UIButton.Configuration.glass()
            searchCfg.image = structSearchGlyph
            searchCfg.cornerStyle = .capsule
            searchCfg.baseForegroundColor = .label
            structSearchButton.configuration = searchCfg
        } else {
            structSearchButton.backgroundColor = .clear
            structSearchButton.layer.cornerRadius = 20
            structSearchButton.clipsToBounds = true
            let searchGlass = makeGlassEffectView()
            searchGlass.translatesAutoresizingMaskIntoConstraints = false
            searchGlass.layer.cornerRadius = 20
            searchGlass.clipsToBounds = true
            searchGlass.isUserInteractionEnabled = false
            structSearchButton.insertSubview(searchGlass, at: 0)
            NSLayoutConstraint.activate([
                searchGlass.leadingAnchor.constraint(equalTo: structSearchButton.leadingAnchor),
                searchGlass.trailingAnchor.constraint(equalTo: structSearchButton.trailingAnchor),
                searchGlass.topAnchor.constraint(equalTo: structSearchButton.topAnchor),
                searchGlass.bottomAnchor.constraint(equalTo: structSearchButton.bottomAnchor),
            ])
            structSearchButton.setImage(structSearchGlyph, for: .normal)
        }
        structSearchButton.addTarget(self, action: #selector(structSearchTapped), for: .touchUpInside)
        view.addSubview(structSearchButton)
        // Exit (26E108, user: 「要这样的退出按钮」 with the Siri
        // sub-page's back button circled): NOT a capsule any more —
        // a 40pt circular glass chevron, built exactly like the
        // sub-view back button (subViewBackButton): chevron.backward
        // at 18pt bold, .glass() capsule config on iOS 26+, a glass
        // effect view behind the glyph below that. It centres on the
        // web title row's .tt-back placeholder box (placeStructChrome).
        structExitButton = UIButton(type: .system)
        structExitButton.translatesAutoresizingMaskIntoConstraints = true
        structExitButton.isHidden = true
        structExitButton.tintColor = .label
        let structExitChevron = UIImage(systemName: "chevron.backward")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .bold))
        if #available(iOS 26.0, *) {
            var exitCfg = UIButton.Configuration.glass()
            exitCfg.image = structExitChevron
            exitCfg.cornerStyle = .capsule
            exitCfg.baseForegroundColor = .label
            structExitButton.configuration = exitCfg
        } else {
            structExitButton.backgroundColor = .clear
            structExitButton.layer.cornerRadius = 20
            structExitButton.clipsToBounds = true
            let exitGlass = makeGlassEffectView()
            exitGlass.translatesAutoresizingMaskIntoConstraints = false
            exitGlass.layer.cornerRadius = 20
            exitGlass.clipsToBounds = true
            exitGlass.isUserInteractionEnabled = false
            structExitButton.insertSubview(exitGlass, at: 0)
            NSLayoutConstraint.activate([
                exitGlass.leadingAnchor.constraint(equalTo: structExitButton.leadingAnchor),
                exitGlass.trailingAnchor.constraint(equalTo: structExitButton.trailingAnchor),
                exitGlass.topAnchor.constraint(equalTo: structExitButton.topAnchor),
                exitGlass.bottomAnchor.constraint(equalTo: structExitButton.bottomAnchor),
            ])
            structExitButton.setImage(structExitChevron, for: .normal)
        }
        structExitButton.addTarget(self, action: #selector(structExitTapped), for: .touchUpInside)
        view.addSubview(structExitButton)
    }

    func refreshStructChromeTitles() {
        if structSeg != nil {
            structSeg.setTitle(L("struct.spatial"), forSegmentAt: 0)
            structSeg.setTitle(L("struct.plan"), forSegmentAt: 1)
        }
        // The search and exit buttons are NOT refreshed here: both
        // are icon-only circles (magnifyingglass / chevron) whose
        // glyphs are language-independent, and re-assigning a
        // configuration would undo the circular glass style they
        // are built with in setupStructChrome (26E108/26E109).
    }

    func hideStructChrome() {
        if structSeg != nil { structSeg.isHidden = true }
        if structSearchButton != nil { structSearchButton.isHidden = true }
        if structExitButton != nil { structExitButton.isHidden = true }
    }

    // Place the native structure chrome over the web detail's reported
    // frames. Zero-size rects (list state, other tabs, release builds)
    // hide the controls. Each control is placed INDEPENDENTLY and
    // only when its reported frame is plausible (26E108 defensive
    // pass, after the 26E107 field report that the station diagram
    // was not visible under the new chrome): a frame must sit fully
    // inside the view, be a sane header size, and stay inside the
    // header zone (top 45% of the view). Any implausible frame —
    // mid-transition garbage, a scaled-viewport mismatch, a rect
    // reaching down into the diagram area — hides that control
    // instead of letting an overlay sprawl over the diagram.
    func placeStructChrome(frame dict: [String: Any]) {
        guard structSeg != nil else { return }
        func rectOf(_ key: String) -> CGRect {
            let d = dict[key] as? [String: Any] ?? [:]
            return CGRect(x: ((d["x"] as? Double) ?? 0) + webOffset.x,
                          y: ((d["y"] as? Double) ?? 0) + webOffset.y,
                          width: (d["width"] as? Double) ?? 0,
                          height: (d["height"] as? Double) ?? 0)
        }
        let segR = rectOf("seg")
        let actR = rectOf("actions")
        let extR = rectOf("exit")
        let bounds = view.bounds
        let headerLimit = bounds.height * 0.45
        func plausible(_ r: CGRect, _ minW: CGFloat, _ maxW: CGFloat, _ minH: CGFloat, _ maxH: CGFloat) -> Bool {
            return r.width >= minW && r.width <= maxW && r.height >= minH && r.height <= maxH
                && r.minX >= -2 && r.minY >= -2
                && r.maxX <= bounds.width + 2 && r.maxY <= headerLimit
        }
        // 26E112: the panel is a Settings sub-page now, so the gate
        // is the web-reported panel state ("panel" in every post),
        // no longer currentTab == "structure" (that tab is gone).
        let active = isTestBuild && ((dict["panel"] as? Bool) ?? false)
        structPanelOpen = active
        // Segmented control: full-width header row under the title.
        let segOK = active && plausible(segR, 120, max(bounds.width, 120), 24, 64)
        if segOK {
            structSeg.frame = segR
            structSeg.isHidden = false
            if let kind = dict["kind"] as? String, let idx = structKindKeys.firstIndex(of: kind) {
                structSeg.selectedSegmentIndex = idx
            }
        } else {
            structSeg.isHidden = true
        }
        // Search circle (26E109): the 40pt icon-only glass button
        // centres on the .struct-actions slot, a 40x40 square in
        // the title row since 26E109, and must sit above the seg
        // row. Same centre-on-slot placement as the exit chevron.
        let actOK = active && plausible(actR, 24, 72, 24, 72) && (!segOK || actR.maxY <= segR.minY + 6)
        if actOK {
            structSearchButton.frame = CGRect(x: actR.midX - 20, y: actR.midY - 20, width: 40, height: 40)
            structSearchButton.isHidden = false
        } else {
            structSearchButton.isHidden = true
        }
        // Exit: the 40pt circular chevron centres on the web
        // .tt-back placeholder's box in the title row.
        let extOK = active && extR.width >= 24 && extR.width <= 72 && extR.height >= 24 && extR.height <= 72
            && extR.minX >= -2 && extR.minY >= -2 && extR.maxX <= bounds.width + 2 && extR.maxY <= headerLimit
        if extOK {
            structExitButton.frame = CGRect(x: extR.midX - 20, y: extR.midY - 20, width: 40, height: 40)
            structExitButton.isHidden = false
        } else {
            structExitButton.isHidden = true
        }
    }

    @objc func structSegChanged(_ sender: UISegmentedControl) {
        let idx = sender.selectedSegmentIndex
        guard idx >= 0 && idx < structKindKeys.count else { return }
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setStructKind('\(structKindKeys[idx])')", completionHandler: nil)
    }

    @objc func structSearchTapped() {
        webView.evaluateJavaScript("window.metroApp && window.metroApp.structSearch()", completionHandler: nil)
    }

    @objc func structExitTapped() {
        webView.evaluateJavaScript("window.metroApp && window.metroApp.structExit()", completionHandler: nil)
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

    // MARK: - Native UISwitch for the Siri page (26C101)

    // The 附近车站智能显示 toggle is a real UISwitch (user: "把这个
    // 改成 Apple UI SDK 27.2"), overlaid on the web Siri page's slot
    // element — same frame-report pattern as the theme buttons. The
    // web keeps the state (Vue + localStorage 'metro-nearby-smart');
    // the switch only renders it and reports user toggles back
    // through window.__setNearbySmart.
    func setupNearbySmartSwitch() {
        let sw = NoScrollSwitch()
        sw.scrollViewToFreeze = webView?.scrollView
        nearbySmartSwitch = sw
        nearbySmartSwitch.onTintColor = .systemGreen
        nearbySmartSwitch.translatesAutoresizingMaskIntoConstraints = true
        nearbySmartSwitch.isHidden = true
        nearbySmartSwitch.addTarget(self, action: #selector(nearbySmartSwitchChanged(_:)), for: .valueChanged)
        view.addSubview(nearbySmartSwitch)
    }

    @objc func nearbySmartSwitchChanged(_ sender: UISwitch) {
        // Programmatic syncs are guarded out: only a genuine user
        // toggle reaches the web.
        guard !nearbySmartApplying else { return }
        webView.evaluateJavaScript("window.__setNearbySmart && window.__setNearbySmart(\(sender.isOn))", completionHandler: nil)
    }

    func hideNearbySmartSwitch() {
        nearbySmartSwitch?.isHidden = true
        webView?.scrollView.isScrollEnabled = true // 26F128 B: never leave the page frozen if the switch hid mid-touch.
    }

    // Place the switch over the web slot's reported frame: trailing
    // aligned inside the slot, vertically centred. A zero-size rect
    // (Siri page not visible) hides it. The posted value is applied
    // WITHOUT firing the change handler.
    func placeSwitch(frame dict: [String: Any]) {
        guard (dict["id"] as? String) == "nearbySmart", let sw = nearbySmartSwitch else { return }
        let x = ((dict["x"] as? Double) ?? 0) + webOffset.x
        let y = ((dict["y"] as? Double) ?? 0) + webOffset.y
        let w = (dict["width"] as? Double) ?? 0
        let h = (dict["height"] as? Double) ?? 0
        if w > 0 && h > 0 && currentTab == "more" && !splashShowing && !whatsNewShowing {
            let size = sw.intrinsicContentSize
            var fx = CGFloat(x) + CGFloat(w) - size.width
            // 26E121 C (native backstop): a switch must never render
            // off the right edge. The web re-reports the slot once
            // the sub-view's slide-in transition settles (the stale
            // mid-transition rect is what pushed this switch ~12pt
            // too far right in the user's screenshot), but if any
            // stale rect still lands here, clamp the frame back
            // inside the view with an 8pt margin instead of letting
            // half the switch sit off-screen.
            let maxX = view.bounds.width - 8
            if fx + size.width > maxX { fx = max(8, maxX - size.width) }
            sw.frame = CGRect(x: fx,
                              y: CGFloat(y) + (CGFloat(h) - size.height) / 2,
                              width: size.width, height: size.height)
            if let on = dict["on"] as? Bool, on != sw.isOn {
                nearbySmartApplying = true
                sw.setOn(on, animated: false)
                nearbySmartApplying = false
            }
            sw.isHidden = false
            view.bringSubviewToFront(sw)
        } else {
            sw.isHidden = true
            webView?.scrollView.isScrollEnabled = true // 26F128 B: same unfreeze as hideNearbySmartSwitch.
        }
    }


    // MARK: - Profile page native Liquid Glass (26E123 ⑤)

    // One native Liquid Glass row for the profile page: a
    // clear-glass plate (the same makeClearGlassEffectView as the
    // transfer card — real UIGlassEffect, no CSS imitation) with a
    // label and, for the redeem row, a trailing chevron mirroring
    // the web row; a clear tap button on top routes the tap back
    // into the web via window.__profileTap, where the exact method
    // the web row runs handles it — behaviour unchanged.
    func makeProfileGlassRow(chevron: Bool, action: Selector) -> (UIView, UILabel) {
        let row = UIView()
        row.layer.cornerRadius = 28
        row.clipsToBounds = true
        row.isHidden = true
        let glass = makeClearGlassEffectView()
        // 26F128: solid row (user "取消玻璃效果") — no glass effect;
        // the row's own background carries the solid colour.
        glass.effect = nil
        row.backgroundColor = solidCardColor()
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.isUserInteractionEnabled = false
        row.addSubview(glass)
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        var constraints: [NSLayoutConstraint] = [
            glass.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            glass.topAnchor.constraint(equalTo: row.topAnchor),
            glass.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ]
        if chevron {
            let chev = UIImageView(image: UIImage(systemName: "chevron.right"))
            chev.tintColor = UIColor(red: 199.0 / 255.0, green: 199.0 / 255.0, blue: 204.0 / 255.0, alpha: 1)
            chev.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(chev)
            constraints.append(label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16))
            constraints.append(chev.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16))
            constraints.append(chev.centerYAnchor.constraint(equalTo: row.centerYAnchor))
            constraints.append(chev.widthAnchor.constraint(equalToConstant: 10))
            constraints.append(chev.heightAnchor.constraint(equalToConstant: 16))
        } else {
            constraints.append(label.centerXAnchor.constraint(equalTo: row.centerXAnchor))
        }
        let tap = UIButton(type: .custom)
        tap.translatesAutoresizingMaskIntoConstraints = false
        tap.addTarget(self, action: action, for: .touchUpInside)
        row.addSubview(tap)
        constraints.append(tap.leadingAnchor.constraint(equalTo: row.leadingAnchor))
        constraints.append(tap.trailingAnchor.constraint(equalTo: row.trailingAnchor))
        constraints.append(tap.topAnchor.constraint(equalTo: row.topAnchor))
        constraints.append(tap.bottomAnchor.constraint(equalTo: row.bottomAnchor))
        NSLayoutConstraint.activate(constraints)
        view.addSubview(row)
        return (row, label)
    }

    func setupProfileControls() {
        // 26E124: the info card is a whole native component — a
        // clear-glass card (same makeClearGlassEffectView as the
        // rows below) with a stack of native rows inside, rebuilt
        // from the profileFrame payload whenever the rows change.
        profileInfoCard = UIView()
        profileInfoCard.layer.cornerRadius = 28
        profileInfoCard.clipsToBounds = true
        profileInfoCard.isHidden = true
        let cardGlass = makeClearGlassEffectView()
        // 26F128: solid card (user "取消玻璃效果") — no glass
        // effect; the card's own background carries the colour.
        cardGlass.effect = nil
        profileInfoCard.backgroundColor = solidCardColor()
        cardGlass.translatesAutoresizingMaskIntoConstraints = false
        cardGlass.isUserInteractionEnabled = false
        profileInfoCard.addSubview(cardGlass)
        profileInfoStack = UIStackView()
        profileInfoStack.axis = .vertical
        profileInfoStack.alignment = .fill
        profileInfoStack.distribution = .fillEqually
        profileInfoStack.translatesAutoresizingMaskIntoConstraints = false
        profileInfoCard.addSubview(profileInfoStack)
        NSLayoutConstraint.activate([
            cardGlass.leadingAnchor.constraint(equalTo: profileInfoCard.leadingAnchor),
            cardGlass.trailingAnchor.constraint(equalTo: profileInfoCard.trailingAnchor),
            cardGlass.topAnchor.constraint(equalTo: profileInfoCard.topAnchor),
            cardGlass.bottomAnchor.constraint(equalTo: profileInfoCard.bottomAnchor),
            profileInfoStack.leadingAnchor.constraint(equalTo: profileInfoCard.leadingAnchor, constant: 16),
            profileInfoStack.trailingAnchor.constraint(equalTo: profileInfoCard.trailingAnchor, constant: -16),
            profileInfoStack.topAnchor.constraint(equalTo: profileInfoCard.topAnchor, constant: 4),
            profileInfoStack.bottomAnchor.constraint(equalTo: profileInfoCard.bottomAnchor, constant: -4),
        ])
        view.addSubview(profileInfoCard)
        let save = makeProfileGlassRow(chevron: false, action: #selector(profileSaveTapped))
        profileSaveRow = save.0
        profileSaveLabel = save.1
        profileSaveLabel.textColor = .systemBlue
        profileSaveLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        let redeem = makeProfileGlassRow(chevron: true, action: #selector(profileRedeemTapped))
        profileRedeemRow = redeem.0
        profileRedeemLabel = redeem.1
        let logout = makeProfileGlassRow(chevron: false, action: #selector(profileLogoutTapped))
        profileLogoutRow = logout.0
        profileLogoutLabel = logout.1
        profileLogoutLabel.textColor = .systemRed
    }

    @objc func profileSaveTapped() {
        // Commit the nickname field first (same order as the old
        // web input: its value lands in profileNameDraft before
        // saveProfile reads it).
        if let tf = profileNameField, tf.isFirstResponder {
            tf.resignFirstResponder()
        }
        if let tf = profileNameField {
            pushProfileName(tf.text ?? "")
        }
        webView.evaluateJavaScript("window.__profileTap && window.__profileTap('save')", completionHandler: nil)
    }

    @objc func profileCityTapped() {
        webView.evaluateJavaScript("window.__profileTap && window.__profileTap('commonCity')", completionHandler: nil)
    }

    func pushProfileName(_ text: String) {
        webView.evaluateJavaScript("window.__profileName && window.__profileName(\(jsStringLiteral(text)))", completionHandler: nil)
    }

    @objc func profileRedeemTapped() {
        webView.evaluateJavaScript("window.__profileTap && window.__profileTap('redeem')", completionHandler: nil)
    }

    @objc func profileLogoutTapped() {
        webView.evaluateJavaScript("window.__profileTap && window.__profileTap('logout')", completionHandler: nil)
    }

    // Place the profile glass pieces over the web's reported rects
    // (profileFrame posts; same webOffset math as placeSwitch).
    // Zero rects — profile page closed, or no signed-in profile for
    // the redeem / sign-out cards — hide the matching piece.
    func placeProfile(frame dict: [String: Any]) {
        func rectOf(_ key: String) -> CGRect? {
            guard let r = dict[key] as? [String: Any],
                  let w = r["width"] as? Double, let h = r["height"] as? Double, w > 0, h > 0 else { return nil }
            return CGRect(x: ((r["x"] as? Double) ?? 0) + webOffset.x,
                          y: ((r["y"] as? Double) ?? 0) + webOffset.y,
                          width: w, height: h)
        }
        let show = currentTab == "more" && !splashShowing && !whatsNewShowing
        if show, let f = rectOf("card") {
            profileInfoCard.frame = f
            profileInfoCard.isHidden = false
            if let rows = dict["rows"] as? [[String: Any]] {
                rebuildProfileInfoRows(rows)
            }
            view.bringSubviewToFront(profileInfoCard)
        } else {
            profileInfoCard.isHidden = true
        }
        if show, let f = rectOf("save") {
            profileSaveRow.frame = f
            profileSaveRow.isHidden = false
            if let t = dict["saveLabel"] as? String, t != profileSaveLabel.text { profileSaveLabel.text = t }
            view.bringSubviewToFront(profileSaveRow)
        } else {
            profileSaveRow.isHidden = true
        }
        if show, let f = rectOf("redeem") {
            profileRedeemRow.frame = f
            profileRedeemRow.isHidden = false
            if let t = dict["redeemLabel"] as? String, t != profileRedeemLabel.text { profileRedeemLabel.text = t }
            view.bringSubviewToFront(profileRedeemRow)
        } else {
            profileRedeemRow.isHidden = true
        }
        if show, let f = rectOf("logout") {
            profileLogoutRow.frame = f
            profileLogoutRow.isHidden = false
            if let t = dict["logoutLabel"] as? String, t != profileLogoutLabel.text { profileLogoutLabel.text = t }
            view.bringSubviewToFront(profileLogoutRow)
        } else {
            profileLogoutRow.isHidden = true
        }
    }

    // 26E124: rebuild the native info card's rows from the
    // profileFrame payload. Row types: "name" (label + native
    // text field), "value" (label + value), "city" (label +
    // value + chevron, tappable). Rebuilds only when the payload
    // signature changes; the field's text is never overwritten
    // while it is being edited.
    func rebuildProfileInfoRows(_ rows: [[String: Any]]) {
        let sig = rows.map { ($0["type"] as? String ?? "") + ":" + ($0["label"] as? String ?? "") + ":" + ($0["value"] as? String ?? "") + ":" + ($0["ph"] as? String ?? "") }.joined(separator: "|")
        if sig == profileRowsSignature { return }
        profileRowsSignature = sig
        for v in profileInfoStack.arrangedSubviews {
            profileInfoStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        profileNameField = nil
        for (idx, row) in rows.enumerated() {
            let type = row["type"] as? String ?? "value"
            let container = UIView()
            let label = UILabel()
            label.font = .systemFont(ofSize: 17)
            label.textColor = .label
            label.text = row["label"] as? String ?? ""
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            var constraints: [NSLayoutConstraint] = [
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ]
            if type == "name" {
                let tf = UITextField()
                tf.font = .systemFont(ofSize: 17)
                tf.textColor = .label
                tf.textAlignment = .right
                tf.text = row["value"] as? String ?? ""
                tf.placeholder = row["ph"] as? String ?? ""
                tf.autocorrectionType = .no
                tf.autocapitalizationType = .none
                tf.spellCheckingType = .no
                tf.returnKeyType = .done
                tf.delegate = self
                tf.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(tf)
                constraints.append(tf.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12))
                constraints.append(tf.trailingAnchor.constraint(equalTo: container.trailingAnchor))
                constraints.append(tf.centerYAnchor.constraint(equalTo: container.centerYAnchor))
                profileNameField = tf
            } else {
                let value = UILabel()
                value.font = .systemFont(ofSize: 17)
                value.textColor = .label
                value.textAlignment = .right
                value.text = row["value"] as? String ?? ""
                value.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(value)
                constraints.append(value.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12))
                if type == "city" {
                    let chev = UIImageView(image: UIImage(systemName: "chevron.right"))
                    chev.tintColor = UIColor(red: 199.0 / 255.0, green: 199.0 / 255.0, blue: 204.0 / 255.0, alpha: 1)
                    chev.translatesAutoresizingMaskIntoConstraints = false
                    container.addSubview(chev)
                    constraints.append(value.trailingAnchor.constraint(equalTo: chev.leadingAnchor, constant: -6))
                    constraints.append(chev.trailingAnchor.constraint(equalTo: container.trailingAnchor))
                    constraints.append(chev.centerYAnchor.constraint(equalTo: container.centerYAnchor))
                    constraints.append(chev.widthAnchor.constraint(equalToConstant: 10))
                    constraints.append(chev.heightAnchor.constraint(equalToConstant: 16))
                    let tap = UIButton(type: .custom)
                    tap.translatesAutoresizingMaskIntoConstraints = false
                    tap.addTarget(self, action: #selector(profileCityTapped), for: .touchUpInside)
                    container.addSubview(tap)
                    constraints.append(tap.leadingAnchor.constraint(equalTo: container.leadingAnchor))
                    constraints.append(tap.trailingAnchor.constraint(equalTo: container.trailingAnchor))
                    constraints.append(tap.topAnchor.constraint(equalTo: container.topAnchor))
                    constraints.append(tap.bottomAnchor.constraint(equalTo: container.bottomAnchor))
                } else {
                    constraints.append(value.trailingAnchor.constraint(equalTo: container.trailingAnchor))
                }
                constraints.append(value.centerYAnchor.constraint(equalTo: container.centerYAnchor))
            }
            if idx < rows.count - 1 {
                let hair = UIView()
                hair.backgroundColor = .separator
                hair.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(hair)
                constraints.append(hair.leadingAnchor.constraint(equalTo: container.leadingAnchor))
                constraints.append(hair.trailingAnchor.constraint(equalTo: container.trailingAnchor))
                constraints.append(hair.bottomAnchor.constraint(equalTo: container.bottomAnchor))
                constraints.append(hair.heightAnchor.constraint(equalToConstant: 0.5))
            }
            NSLayoutConstraint.activate(constraints)
            profileInfoStack.addArrangedSubview(container)
        }
    }

    func hideProfileControls() {
        profileInfoCard?.isHidden = true
        profileSaveRow?.isHidden = true
        profileRedeemRow?.isHidden = true
        profileLogoutRow?.isHidden = true
    }

    // MARK: - Map station card (26E124)

    func setupMapCard() {
        mapCardView = UIView()
        mapCardView.layer.cornerRadius = 20
        mapCardView.clipsToBounds = true
        mapCardView.isHidden = true
        let glass = makeClearGlassEffectView()
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.isUserInteractionEnabled = false
        mapCardView.addSubview(glass)
        mapCardNameLabel = UILabel()
        mapCardNameLabel.font = .systemFont(ofSize: 17, weight: .bold)
        mapCardNameLabel.textColor = .label
        mapCardBadgeArea = UIView()
        mapCardBadgeHeight = mapCardBadgeArea.heightAnchor.constraint(equalToConstant: 0)
        func makeButton(_ color: UIColor, _ action: Selector) -> UIButton {
            let b = UIButton(type: .custom)
            b.backgroundColor = UIColor(red: 120.0 / 255.0, green: 120.0 / 255.0, blue: 128.0 / 255.0, alpha: 0.12)
            b.layer.cornerRadius = 12
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            b.setTitleColor(color, for: .normal)
            b.addTarget(self, action: action, for: .touchUpInside)
            return b
        }
        mapCardFromButton = makeButton(.systemBlue, #selector(mapCardFromTapped))
        mapCardToButton = makeButton(UIColor(red: 229.0 / 255.0, green: 72.0 / 255.0, blue: 77.0 / 255.0, alpha: 1), #selector(mapCardToTapped))
        let actions = UIStackView(arrangedSubviews: [mapCardFromButton, mapCardToButton])
        actions.axis = .horizontal
        actions.spacing = 10
        actions.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [mapCardNameLabel, mapCardBadgeArea, actions])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        mapCardView.addSubview(stack)
        mapCardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapCardView)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: mapCardView.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: mapCardView.trailingAnchor),
            glass.topAnchor.constraint(equalTo: mapCardView.topAnchor),
            glass.bottomAnchor.constraint(equalTo: mapCardView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: mapCardView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: mapCardView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: mapCardView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: mapCardView.bottomAnchor, constant: -14),
            mapCardBadgeHeight!,
            mapCardFromButton.heightAnchor.constraint(equalToConstant: 41),
            mapCardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            mapCardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            mapCardView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -84),
        ])
    }

    // One line badge at 60% of the web .ln-badge (the map card's
    // pills were the big suggestion-row badges: 54pt number,
    // 20/11pt zh/en, 10/18 padding, radius 12 — here 32pt, 12/7pt,
    // 6/11 padding, radius 7), same layout: big number left, the
    // 号线 / Line stack right; a pinned line keeps its green
    // check disc.
    func makeMapBadge(_ line: [String: Any]) -> UIView {
        let badge = UIView()
        badge.backgroundColor = colorFromHex(line["color"] as? String ?? "") ?? .systemGray
        badge.layer.cornerRadius = 7
        let fg = colorFromHex(line["text"] as? String ?? "") ?? .white
        let num = UILabel()
        num.text = line["left"] as? String ?? ""
        num.font = .systemFont(ofSize: 32, weight: .heavy)
        num.textColor = fg
        num.sizeToFit()
        let top = line["top"] as? String ?? ""
        let zh = UILabel()
        zh.text = top
        zh.font = .systemFont(ofSize: 12, weight: .bold)
        zh.textColor = fg
        zh.sizeToFit()
        let en = UILabel()
        en.text = line["bottom"] as? String ?? ""
        en.font = .systemFont(ofSize: 7, weight: .semibold)
        en.textColor = fg.withAlphaComponent(0.92)
        en.sizeToFit()
        let txtW = top.isEmpty ? en.frame.width : max(zh.frame.width, en.frame.width)
        let txtH = top.isEmpty ? en.frame.height : zh.frame.height + en.frame.height + 1
        let w = 10 + num.frame.width + 6 + txtW + 11
        let h = max(num.frame.height, txtH) + 12
        badge.frame = CGRect(x: 0, y: 0, width: w, height: h)
        num.frame.origin = CGPoint(x: 10, y: (h - num.frame.height) / 2)
        badge.addSubview(num)
        if top.isEmpty {
            en.frame.origin = CGPoint(x: 10 + num.frame.width + 6, y: (h - en.frame.height) / 2)
            badge.addSubview(en)
        } else {
            zh.frame.origin = CGPoint(x: 10 + num.frame.width + 6, y: (h - txtH) / 2)
            en.frame.origin = CGPoint(x: 10 + num.frame.width + 6, y: (h - txtH) / 2 + zh.frame.height + 1)
            badge.addSubview(zh)
            badge.addSubview(en)
        }
        if (line["pinned"] as? Bool) == true {
            let disc = UIView()
            disc.backgroundColor = UIColor(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1)
            disc.layer.cornerRadius = 6
            disc.frame = CGRect(x: w - 8, y: -4, width: 12, height: 12)
            let check = UILabel()
            check.text = "✓"
            check.font = .systemFont(ofSize: 8, weight: .heavy)
            check.textColor = .white
            check.textAlignment = .center
            check.frame = disc.bounds
            disc.addSubview(check)
            badge.addSubview(disc)
        }
        let tap = UIButton(type: .custom)
        tap.frame = badge.bounds
        tap.accessibilityIdentifier = line["key"] as? String ?? ""
        tap.addTarget(self, action: #selector(mapCardBadgeTapped(_:)), for: .touchUpInside)
        badge.addSubview(tap)
        return badge
    }

    func placeMapCard(_ dict: [String: Any]) {
        guard (dict["show"] as? Bool) == true,
              let name = dict["name"] as? String,
              let lines = dict["lines"] as? [[String: Any]],
              currentTab == "map", !splashShowing, !whatsNewShowing else {
            hideMapCard()
            return
        }
        mapCardNameLabel.text = name
        mapCardFromButton.setTitle(dict["fromLabel"] as? String ?? "", for: .normal)
        mapCardToButton.setTitle(dict["toLabel"] as? String ?? "", for: .normal)
        for v in mapCardBadgeArea.subviews { v.removeFromSuperview() }
        let avail = view.bounds.width - 64
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        if lines.count > 1 {
            for line in lines {
                let badge = makeMapBadge(line)
                if x > 0 && x + badge.frame.width > avail {
                    x = 0
                    y += rowH + 6
                    rowH = 0
                }
                badge.frame.origin = CGPoint(x: x, y: y)
                mapCardBadgeArea.addSubview(badge)
                x += badge.frame.width + 6
                rowH = max(rowH, badge.frame.height)
            }
        }
        mapCardBadgeHeight?.constant = lines.count > 1 ? y + rowH : 0
        mapCardBadgeArea.isHidden = lines.count <= 1
        mapCardView.isHidden = false
        view.bringSubviewToFront(mapCardView)
    }

    func hideMapCard() {
        mapCardView?.isHidden = true
    }

    @objc func mapCardFromTapped() {
        webView.evaluateJavaScript("window.__mapCardTap && window.__mapCardTap('from', null)", completionHandler: nil)
    }

    @objc func mapCardToTapped() {
        webView.evaluateJavaScript("window.__mapCardTap && window.__mapCardTap('to', null)", completionHandler: nil)
    }

    @objc func mapCardBadgeTapped(_ sender: UIButton) {
        let key = sender.accessibilityIdentifier ?? ""
        webView.evaluateJavaScript("window.__mapCardTap && window.__mapCardTap('pin', \(jsStringLiteral(key)))", completionHandler: nil)
    }

    // MARK: - Creator redemption (26E122)

    // The native half of the profile page's 兑换码 row: a
    // UIAlertController with a text field collects the code and the
    // entered text returns through window.__redeemEntered (null on
    // cancel). Code matching and both tables live in the web — this
    // side only collects text and presents result alerts
    // (redeemNote), so the strings stay single-sourced in the page.
    func presentRedeemInput(dict: [String: Any]) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: dict["title"] as? String ?? "",
                                      message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = dict["ph"] as? String ?? ""
            tf.autocapitalizationType = .allCharacters
            tf.autocorrectionType = .no
            tf.spellCheckingType = .no
        }
        alert.addAction(UIAlertAction(title: dict["ok"] as? String ?? "OK", style: .default, handler: { _ in
            let text = alert.textFields?.first?.text ?? ""
            self.webView.evaluateJavaScript("window.__redeemEntered && window.__redeemEntered(\(self.jsStringLiteral(text)))", completionHandler: nil)
        }))
        alert.addAction(UIAlertAction(title: dict["cancel"] as? String ?? "Cancel", style: .cancel, handler: { _ in
            self.webView.evaluateJavaScript("window.__redeemEntered && window.__redeemEntered(null)", completionHandler: nil)
        }))
        present(alert, animated: true, completion: nil)
    }

    // 26E122: the Home City picker as a native action sheet — the
    // Use-My-Location row first (its tap routes back into the web's
    // one-shot location flow via __commonCityLoc), then one action
    // per adapted city, then Cancel. The pick returns through
    // window.__commonCityPicked (null on cancel).
    func presentCommonCitySheet(dict: [String: Any]) {
        lastCommonCityPick = dict
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: dict["title"] as? String ?? "",
                                      message: nil, preferredStyle: .actionSheet)
        if let loc = dict["locLabel"] as? String, !loc.isEmpty {
            alert.addAction(UIAlertAction(title: loc, style: .default, handler: { _ in
                self.webView.evaluateJavaScript("window.__commonCityLoc && window.__commonCityLoc()", completionHandler: nil)
            }))
        }
        if let cities = dict["cities"] as? [[String: Any]] {
            for c in cities {
                guard let key = c["key"] as? String, let name = c["name"] as? String else { continue }
                alert.addAction(UIAlertAction(title: name, style: .default, handler: { _ in
                    self.webView.evaluateJavaScript("window.__commonCityPicked && window.__commonCityPicked(\(self.jsStringLiteral(key)))", completionHandler: nil)
                }))
            }
        }
        alert.addAction(UIAlertAction(title: dict["cancel"] as? String ?? "Cancel", style: .cancel, handler: { _ in
            self.webView.evaluateJavaScript("window.__commonCityPicked && window.__commonCityPicked(null)", completionHandler: nil)
        }))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = webView
            pop.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        present(alert, animated: true, completion: nil)
    }

    // JSON string literal, safe to interpolate into evaluateJavaScript.
    func jsStringLiteral(_ s: String) -> String {
        if let d = try? JSONSerialization.data(withJSONObject: [s], options: []),
           let t = String(data: d, encoding: .utf8), t.hasPrefix("["), t.hasSuffix("]") {
            return String(t.dropFirst().dropLast())
        }
        return "\"\""
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
        // 26F128: solid card (user "取消玻璃效果") — the effect view
        // stays as the content container but renders no glass; the
        // card's own background carries the solid colour.
        transferEffectView.effect = nil
        transferCard.backgroundColor = solidCardColor()
        transferEffectView.translatesAutoresizingMaskIntoConstraints = false
        transferCard.addSubview(transferEffectView)
        NSLayoutConstraint.activate([
            transferEffectView.leadingAnchor.constraint(equalTo: transferCard.leadingAnchor),
            transferEffectView.trailingAnchor.constraint(equalTo: transferCard.trailingAnchor),
            transferEffectView.topAnchor.constraint(equalTo: transferCard.topAnchor),
            transferEffectView.bottomAnchor.constraint(equalTo: transferCard.bottomAnchor),
        ])

        let content = transferEffectView.contentView

        // Two rows: dot + label + text field + line badges + clear.
        // The badge slot is a stack (26E110 P): an interchange
        // station shows one pill per line it serves.
        fromField = makeTransferField(tag: 0, placeholder: L("tr.phFrom"))
        toField = makeTransferField(tag: 1, placeholder: L("tr.phTo"))
        fromBadgeStack = makeBadgeStack()
        toBadgeStack = makeBadgeStack()
        // With several line pills in a row the station-name field is
        // the flexible element (26E110 P): it gives up width first
        // (text clips, never overflows) while the pills keep theirs.
        fromField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        fromClear = makeTransferClear(tag: 0)
        toClear = makeTransferClear(tag: 1)
        let fromRow = makeTransferRow(dotColor: UIColor(red: 34.0 / 255.0, green: 160.0 / 255.0, blue: 107.0 / 255.0, alpha: 1),
                                      labelTitle: L("tr.depart"), labelTag: 0,
                                      field: fromField, badgeStack: fromBadgeStack, clear: fromClear)
        let toRow = makeTransferRow(dotColor: UIColor(red: 229.0 / 255.0, green: 72.0 / 255.0, blue: 77.0 / 255.0, alpha: 1),
                                    labelTitle: L("tr.arrive"), labelTag: 1,
                                    field: toField, badgeStack: toBadgeStack, clear: toClear)
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

        // 26E123 ⑥: full-row tap layers. Each spans the FULL card
        // width and its row's full height band (the two bands meet
        // at the divider's centre), inserted at the BACK of the
        // card's content — under the rows, the divider and the swap
        // button — so blank-area taps focus the row's field while
        // the label button, line badges, clear button and swap
        // button (all above) keep their own taps untouched.
        fromRowTap = UIButton(type: .custom)
        fromRowTap.tag = 0
        fromRowTap.addTarget(self, action: #selector(transferRowTapTapped(_:)), for: .touchUpInside)
        fromRowTap.translatesAutoresizingMaskIntoConstraints = false
        content.insertSubview(fromRowTap, at: 0)
        toRowTap = UIButton(type: .custom)
        toRowTap.tag = 1
        toRowTap.addTarget(self, action: #selector(transferRowTapTapped(_:)), for: .touchUpInside)
        toRowTap.translatesAutoresizingMaskIntoConstraints = false
        content.insertSubview(toRowTap, at: 0)
        NSLayoutConstraint.activate([
            fromRowTap.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            fromRowTap.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            fromRowTap.topAnchor.constraint(equalTo: content.topAnchor),
            fromRowTap.bottomAnchor.constraint(equalTo: divider.centerYAnchor),
            toRowTap.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toRowTap.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            toRowTap.topAnchor.constraint(equalTo: divider.centerYAnchor),
            toRowTap.bottomAnchor.constraint(equalTo: content.bottomAnchor),
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

    func makeTransferRow(dotColor: UIColor, labelTitle: String, labelTag: Int, field: UITextField, badgeStack: UIStackView, clear: UIButton) -> UIStackView {
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
        let row = UIStackView(arrangedSubviews: [dot, label, field, badgeStack, clear])
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
        // 26E123 ⑦: NO inputAccessoryView. The app used to attach
        // makeKeyboardToolbar() here — a UIToolbar whose Done item
        // ("完成") is exactly the blue capsule the user circled
        // floating over the keyboard (26E121 misjudged it as a
        // system accessory; it was ours all along). Removed: the
        // keyboard now dismisses via the Search return key and by
        // tapping elsewhere, like the rest of the app.
        f.addTarget(self, action: #selector(transferFieldChanged(_:)), for: .editingChanged)
        return f
    }

    // Badge stack for a transfer field row (26E110 P): horizontal,
    // pills 4pt apart, vertically centred with the field; the stack
    // never compresses — the name field yields instead.
    func makeBadgeStack() -> UIStackView {
        let s = UIStackView()
        s.axis = .horizontal
        s.spacing = 4
        s.alignment = .center
        s.distribution = .fill
        s.setContentHuggingPriority(.required, for: .horizontal)
        s.setContentCompressionResistancePriority(.required, for: .horizontal)
        return s
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

    // 26E123 ⑥: a tap on a transfer row's blank area (the full-row
    // tap layer under the row contents) focuses that row's field.
    @objc func transferRowTapTapped(_ sender: UIButton) {
        if sender.tag == 0 { fromField.becomeFirstResponder() } else { toField.becomeFirstResponder() }
    }

    // Place the native transfer card + search button over the web rows'
    // reported frames, and sync the native fields with the web state.
    // The web rects are in CSS pixels; the full-screen web view maps
    // them 1:1 to points. A zero-size rect (panel hidden, or not on
    // the transfer tab) hides the controls. Field text is only copied
    // from the web while the user is NOT typing in that field, so the
    // caret never jumps.
    // 26E127 fix 10: last good transfer frame, re-applied when the transfer tab is (re-)entered (setWebTab / tabChanged). The web's post can be lost or delayed when a city switch swaps #svg8 mid-update, leaving the native card hidden on a blank page; the cache is the device-side backstop.
    var lastTransferFrame: [String: Any]?
    func placeTransfer(frame dict: [String: Any]) {
        lastTransferFrame = dict
        // 26E126: the route-detail page covers the transfer panel —
        // the native card / search button / action pills must hide
        // while the detail is open (user screenshot, 26E125: the
        // search card covered the detail page). The web re-posts
        // detailOpen with every frame report, so the state
        // re-asserts itself after tab switches.
        if dict["detailOpen"] as? Bool == true {
            transferCard.isHidden = true
            transferSearchButton.isHidden = true
            hideActionButtons()
            departButton?.isHidden = true // 26F128: the depart circle must not float over the detail page (it was missing from this list — the clipped-button screenshot).
            return
        }
        guard let f = dict["fields"] as? [String: Any],
              let s = dict["search"] as? [String: Any] else {
            transferCard.isHidden = true
            transferSearchButton.isHidden = true
            hideActionButtons()
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
            // 26E110 P: prefer the all-lines arrays (every line of
            // the picked station); fall back to the single line.
            // 26E121 G: the frame also carries the pinned line's key
            // (fromLine/toLine) so the pinned pill shows its check.
            if let lines = dict["fromLines"] as? [[String: Any]] {
                applyBadges(which: "from", lines: lines, pinnedKey: (dict["fromLine"] as? [String: Any])?["key"] as? String)
            } else {
                applyBadge(which: "from", line: dict["fromLine"] as? [String: Any])
            }
            if let lines = dict["toLines"] as? [[String: Any]] {
                applyBadges(which: "to", lines: lines, pinnedKey: (dict["toLine"] as? [String: Any])?["key"] as? String)
            } else {
                applyBadge(which: "to", line: dict["toLine"] as? [String: Any])
            }
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
        // Quick-action row (same report): the transit label and
        // the nearby loading flag are cheap and ride every post;
        // the icon data URLs only arrive when the web posts a
        // changed one, so decode + cache only then, and only
        // re-apply the button contents when something changed.
        var actionsChanged = false
        if let label = dict["transitLabel"] as? String, label != actionTransitLabel {
            actionTransitLabel = label
            actionsChanged = true
        }
        if let loading = dict["nearbyLoading"] as? Bool, loading != actionNearbyLoading {
            actionNearbyLoading = loading
            actionsChanged = true
        }
        if let icon = dict["transitIcon"] as? String, icon != actionTransitIconURL {
            actionTransitIconURL = icon
            actionTransitIcon = decodeActionIcon(icon)
            actionsChanged = true
        }
        if let icon = dict["pinIcon"] as? String, icon != actionPinIconURL {
            actionPinIconURL = icon
            actionPinIcon = decodeActionIcon(icon)
            actionsChanged = true
        }
        if actionsChanged { refreshActionButtons() }
        if let a = dict["actions"] as? [String: Any] {
            let ax = (a["x"] as? Double) ?? 0
            let ay = (a["y"] as? Double) ?? 0
            let aw = (a["width"] as? Double) ?? 0
            let ah = (a["height"] as? Double) ?? 0
            if aw > 0 && ah > 0 && currentTab == "transfer" {
                // Three equal pills with 8pt gaps — the web row's
                // flex layout (same split as placeThemeButtons).
                let gap: CGFloat = 8
                let bw = (CGFloat(aw) - gap * 2) / 3
                let row: [UIButton] = [transitAppButton, nearbyStationsButton, applePayButton]
                for (i, btn) in row.enumerated() {
                    btn.frame = CGRect(x: CGFloat(ax) + webOffset.x + CGFloat(i) * (bw + gap),
                                       y: CGFloat(ay) + webOffset.y, width: bw, height: CGFloat(ah))
                    btn.isHidden = false
                }
            } else {
                hideActionButtons()
            }
        } else {
            hideActionButtons()
        }
    }

    func updateTransferVisibility() {
        if currentTab != "transfer" {
            transferCard.isHidden = true
            transferSearchButton.isHidden = true
            hideActionButtons()
            departButton?.isHidden = true // 26E127 fix 11: the native depart button lives on the transfer tab only.
            view.endEditing(true)
        }
        // Dark-mode picker only lives on the settings tab.
        if currentTab != "more" {
            for btn in themeButtons { btn.isHidden = true }
            // 26E123 ⑤: the profile glass pieces live on the
            // settings tab too.
            hideProfileControls()
        }
    }

    // MARK: - Native Liquid Glass quick-action row (transfer page)

    // Glass button config for the quick-action pills: Liquid Glass
    // on iOS 26+, a filled capsule below (same pattern as the theme
    // picker's themeButtonConfig). The title font matches the web
    // row these pills replace (15px semibold) and imagePadding its
    // 6px icon gap; long app names truncate like the web row's
    // ellipsis.
    func actionButtonConfig() -> UIButton.Configuration {
        // 26F128: solid pills (user "取消玻璃效果") — a filled
        // capsule in the web cards' colour instead of Liquid Glass.
        var cfg = UIButton.Configuration.filled()
        cfg.baseBackgroundColor = solidCardColor()
        cfg.baseForegroundColor = .label
        cfg.cornerStyle = .capsule
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            return a
        }
        cfg.imagePadding = 6
        cfg.titleLineBreakMode = .byTruncatingTail
        return cfg
    }

    func setupActionButtons() {
        transitAppButton = UIButton(type: .system)
        transitAppButton.configuration = actionButtonConfig()
        transitAppButton.translatesAutoresizingMaskIntoConstraints = true
        transitAppButton.isHidden = true
        transitAppButton.addTarget(self, action: #selector(transitAppButtonTapped), for: .touchUpInside)
        view.addSubview(transitAppButton)

        nearbyStationsButton = UIButton(type: .system)
        nearbyStationsButton.configuration = actionButtonConfig()
        nearbyStationsButton.translatesAutoresizingMaskIntoConstraints = true
        nearbyStationsButton.isHidden = true
        nearbyStationsButton.addTarget(self, action: #selector(nearbyStationsButtonTapped), for: .touchUpInside)
        view.addSubview(nearbyStationsButton)

        applePayButton = UIButton(type: .system)
        applePayButton.configuration = actionButtonConfig()
        applePayButton.translatesAutoresizingMaskIntoConstraints = true
        applePayButton.isHidden = true
        applePayButton.addTarget(self, action: #selector(applePayButtonTapped), for: .touchUpInside)
        view.addSubview(applePayButton)

        refreshActionButtons()
    }

    // The three taps run the EXACT code paths the web buttons used:
    // the transit tap calls the same native openTransitApp() the
    // web's openTransitApp post triggered; nearby calls
    // requestNearbyLocation(), the web's requestLocation post; Apple
    // Pay goes through openExternalURL with wallet://, the web's
    // openApplePay -> openExternal('wallet://') path.
    @objc func transitAppButtonTapped() {
        openTransitApp()
    }

    @objc func nearbyStationsButtonTapped() {
        requestNearbyLocation()
    }

    @objc func applePayButtonTapped() {
        openExternalURL(dict: ["url": "wallet://", "fallback": ""])
    }

    func hideActionButtons() {
        transitAppButton?.isHidden = true
        nearbyStationsButton?.isHidden = true
        applePayButton?.isHidden = true
    }

    // Re-apply the three pills' titles + icons from the cached
    // state. The transit label prefers the web's posted label (the
    // page's own transitLabel, in the page's language) and falls
    // back to the native LANG table keyed by currentCity; the
    // nearby pill gains the web row's 定位中… suffix while a
    // location fix is in flight.
    // 26E110 ghost fix (user screenshot, Dalian switch): the middle
    // pill showed a faint doubled 「附近」 after a city switch. Cause:
    // this ran on EVERY city switch (via refreshCityUI with the
    // STALE cached label, then again via placeTransfer with the new
    // one) and re-assigned a fresh configuration to all three pills
    // even when a pill's title + icon were byte-identical — a glass
    // UIButton treats each assignment as a content transition and
    // morphs the old/new content, which reads as a ghost on the
    // full-width middle title. Now: a pill is only re-configured
    // when its title or icon actually changed, and the swap is
    // applied without animation, so content lands in one frame.
    func refreshActionButtons() {
        guard transitAppButton != nil else { return }
        let tTitle = actionTransitLabel.isEmpty ? L("transit." + currentCity) : actionTransitLabel
        let nTitle = L("tr.nearby") + (actionNearbyLoading ? " " + L("tr.nearby.locating") : "")
        let aTitle = L("tr.applepay")
        UIView.performWithoutAnimation {
            if transitAppButton.configuration?.title != tTitle || transitAppButton.configuration?.image !== actionTransitIcon {
                var tcfg = transitAppButton.configuration ?? actionButtonConfig()
                tcfg.title = tTitle
                tcfg.image = actionTransitIcon
                transitAppButton.configuration = tcfg
            }
            if nearbyStationsButton.configuration?.title != nTitle || nearbyStationsButton.configuration?.image !== actionPinIcon {
                var ncfg = nearbyStationsButton.configuration ?? actionButtonConfig()
                ncfg.title = nTitle
                ncfg.image = actionPinIcon
                nearbyStationsButton.configuration = ncfg
            }
            if applePayButton.configuration?.title != aTitle {
                var acfg = applePayButton.configuration ?? actionButtonConfig()
                acfg.title = aTitle
                applePayButton.configuration = acfg
            }
        }
    }

    // Decode a "data:image/png;base64,..." icon the web posted and
    // render it at the web row's icon size: 22x22pt with the 5pt
    // corner radius of .tr-action-btn img. A straight resize of the
    // same artwork (never redrawn). An empty or invalid string —
    // cities whose icon the web itself renders label-only — yields
    // nil, so the pill shows just its title, like the web row.
    func decodeActionIcon(_ dataURL: String) -> UIImage? {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let b64 = String(dataURL[dataURL.index(after: comma)...])
        guard let data = Data(base64Encoded: b64), let src = UIImage(data: data) else { return nil }
        let size = CGSize(width: 22, height: 22)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5).addClip()
            src.draw(in: CGRect(origin: .zero, size: size))
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

    // Line badges: small pills with each line's colour + name (same
    // style as the web .tr-line-pick). lines is an array of
    // {name, color, text} with hex strings — ALL lines serving the
    // picked station, in the city's line order (26E110 P: an
    // interchange station shows every line, not just the one whose
    // suggestion row was tapped). An empty array hides all pills.
    // fromLineInfo/toLineInfo keep the FIRST line for the existing
    // single-line consumers (line-pick state).
    func applyBadges(which: String, lines: [[String: Any]], pinnedKey: String? = nil) {
        // 26E121 G: remember the pin per end; fromLineInfo follows
        // the pinned line when there is one (the swap path uses it),
        // else the first line as before.
        if which == "from" { fromPinnedKey = pinnedKey } else { toPinnedKey = pinnedKey }
        let pinnedLine = pinnedKey.flatMap { k in lines.first { ($0["key"] as? String) == k } }
        if which == "from" { fromLineInfo = pinnedLine ?? lines.first } else { toLineInfo = pinnedLine ?? lines.first }
        guard let stack = which == "from" ? fromBadgeStack : toBadgeStack else { return }
        var pool = which == "from" ? fromBadges : toBadges
        while pool.count < lines.count {
            let b = makeTransferBadge(tag: which == "from" ? 0 : 1)
            pool.append(b)
            stack.addArrangedSubview(b)
        }
        if which == "from" { fromBadges = pool } else { toBadges = pool }
        for (i, b) in pool.enumerated() {
            guard i < lines.count,
                  let name = lines[i]["name"] as? String,
                  let colorHex = lines[i]["color"] as? String,
                  let bg = colorFromHex(colorHex) else {
                b.isHidden = true
                continue
            }
            let fg: UIColor
            if let textHex = lines[i]["text"] as? String, let c = colorFromHex(textHex) {
                fg = c
            } else {
                fg = .white
            }
            // 26E121 G: each pill remembers its line key (the tap
            // handler pins/unpins by key), and the PINNED line's
            // pill carries the check — a check prefix in the title
            // plus a ring in the pill's own text colour, so the
            // lock reads at a glance in the field, mirroring the
            // web badges' check disc.
            let key = lines[i]["key"] as? String
            b.accessibilityIdentifier = key
            let pinned = pinnedKey != nil && key != nil && key == pinnedKey
            b.setTitle(pinned ? "✓ " + name : name, for: .normal)
            b.layer.borderWidth = pinned ? 2 : 0
            b.layer.borderColor = fg.cgColor
            b.backgroundColor = bg
            b.setTitleColor(fg, for: .normal)
            b.isHidden = false
        }
    }

    // Single-line convenience (legacy posts / clears).
    func applyBadge(which: String, line: [String: Any]?) {
        applyBadges(which: which, lines: line.map { [$0] } ?? [], pinnedKey: line?["key"] as? String)
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
        // 26E124: the profile card's native nickname field.
        if let pf = profileNameField, textField === pf {
            webView.evaluateJavaScript("window.__profileNameFocus && window.__profileNameFocus(true)", completionHandler: nil)
            return
        }
        let which = textField.tag == 0 ? "from" : "to"
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setNativeFocus('\(which)')", completionHandler: nil)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        // 26E124: the nickname field commits its text to the web
        // (profileNameDraft) and reports the focus release.
        if let pf = profileNameField, textField === pf {
            pushProfileName(textField.text ?? "")
            webView.evaluateJavaScript("window.__profileNameFocus && window.__profileNameFocus(false)", completionHandler: nil)
            return
        }
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setNativeBlur()", completionHandler: nil)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // 26E124: Done on the nickname field just resigns (the
        // transfer fields keep their search-on-return behaviour).
        if let pf = profileNameField, textField === pf {
            textField.resignFirstResponder()
            return true
        }
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
        // 26E121 G: the pills are one per line now. Tapping the
        // PINNED pill unpins that end (back to by-station routing —
        // the pre-26E121 single-badge behaviour); tapping a
        // different pill moves the pin to that line. The web owns
        // the state: its clearLine / pinLine calls re-post the
        // frames, and the pills re-render with the check on the
        // right one. A pill without a key (legacy post) falls back
        // to the old clear.
        let key = sender.accessibilityIdentifier
        let pinned = which == "from" ? fromPinnedKey : toPinnedKey
        if let key = key, key != pinned {
            webView.evaluateJavaScript("window.metroApp && window.metroApp.pinLine('\(which)', \(jsString(key)))", completionHandler: nil)
        } else {
            webView.evaluateJavaScript("window.metroApp && window.metroApp.clearLine('\(which)')", completionHandler: nil)
        }
    }

    @objc func transferSearchTapped() {
        view.endEditing(true)
        webView.evaluateJavaScript("window.metroApp && window.metroApp.doSearch()", completionHandler: nil)
    }

    func updatePillVisibility() {
        let show = currentTab == "map" && !splashShowing && !whatsNewShowing
        cityPill.isHidden = !show
        mapToolsPill.isHidden = !show
        updateCityPillLeading()
    }

    // Called when the web splash finishes (or the fallback timer fires):
    // reveal the native controls.
    // (Re)pick the native splash poster for the current city and
    // appearance (2026-11-20 fix, user: "每个城市都显示北京" — both
    // splash layers showed Beijing). The launch-time pick reads
    // UserDefaults, which the web refreshes only when it reports in;
    // if the two stores ever diverge (web store reset, a switch whose
    // report never landed), the native poster stays on the default.
    // The web's launch sequence always reports themeState from
    // mounted() BEFORE it posts splashDone, so the handlers call
    // this while the splash is still up and the poster is corrected
    // in place. Falls back to the original Beijing poster if the
    // image is ever missing, so the launch screen is never blank.
    func refreshSplashImage() {
        guard splashShowing, let iv = splashImageView else { return }
        // Universal splash (26C105): ONE pair for the whole app —
        // the user-supplied 'Subway Tools' posters, picked by
        // dark/light only (no per-city selection anymore). The
        // per-city posters stay in the bundle unreferenced for a
        // possible later re-enable.
        let splashName = "SplashST"
        // Dark variant per splashDarkResolved() (26E109): this
        // session's web report once it lands; before that, the
        // scene-connection-time resolution (persisted mode + scene
        // trait) — NOT the raw persisted metro-dark flag, whose
        // staleness across appearance flips caused the one-frame
        // wrong-variant flash on cold start.
        let splashDark = splashDarkResolved()
        // The dark variant counts as present if named lookup OR the
        // explicit .jpg path finds it (26D104 — same miss that hit the
        // load chain below).
        let darkExists = UIImage(named: splashName + "Dark") != nil || Bundle.main.path(forResource: splashName + "Dark", ofType: "jpg") != nil
        let useDark = splashDark && darkExists
        let splashImageName = useDark ? splashName + "Dark" : splashName
        // Load chain (26D104): named lookup first (the bundle now also
        // carries SplashST.png / SplashSTDark.png — same bytes, .png
        // names, which named lookup resolves reliably here), then an
        // explicit-path load of the .jpg files, and only then the
        // original Beijing 'Splash' poster as the last resort. On
        // 26D103 the .jpg-named pair was missed by named lookup on
        // device, so the fallback Beijing poster is what users saw.
        var splashImg = UIImage(named: splashImageName) ?? UIImage(named: splashName)
        if splashImg == nil, let path = Bundle.main.path(forResource: splashImageName, ofType: "jpg") {
            splashImg = UIImage(contentsOfFile: path)
        }
        if splashImg == nil, splashImageName != splashName, let path = Bundle.main.path(forResource: splashName, ofType: "jpg") {
            splashImg = UIImage(contentsOfFile: path)
        }
        if splashImg == nil { splashImg = UIImage(named: "Splash") }
        if let img = splashImg {
            iv.image = img
        }
        // Background follows the poster ACTUALLY shown, not the
        // appearance flag (26C101): the light posters are white
        // edge-to-edge and the dark posters black edge-to-edge
        // (verified in the bundle), so matching the background to the
        // picked variant makes any letterbox area invisible. The old
        // code keyed the background to splashDark even when the dark
        // image was missing and the light poster was on screen.
        iv.backgroundColor = useDark ? .black : .white
        // Content mode by width class (26C101): phone widths fill —
        // the poster's 1170x2532 aspect matches phone screens to
        // within a fraction of a percent, so the crop is invisible
        // and no bars can appear. Wide screens (iPad, unfolded Duo,
        // landscape) fit, with the poster-matched background above
        // blending the margins away.
        let w = view.bounds.width
        iv.contentMode = (w > 0 && w <= 500) ? .scaleAspectFill : .scaleAspectFit
        iv.clipsToBounds = true
    }

    func splashFinished() {
        guard splashShowing else { return }
        splashShowing = false
        hideNearbySmartSwitch()
        // Remove the native launch splash WITHOUT its own fade (flash
        // fix, user 2026-11-19): splashDone is posted at the moment the
        // web overlay — the identical poster, underneath this view —
        // starts its single 0.4s fade. Fading both at once crossfaded
        // two slightly different renderings of the same poster, which
        // read as a flicker. Instant removal is invisible (the web
        // overlay is still fully opaque at that instant) and leaves
        // exactly one fade.
        if let splash = splashImageView {
            splash.removeFromSuperview()
            splashImageView = nil
        }
        // 26E125: if the web posted this build's What's New, show
        // the native page now — the chrome stays hidden until the
        // user confirms, exactly like the splash gate above.
        if pendingWhatsNew != nil {
            showWhatsNewPage()
            return
        }
        // Reveal the tab bar or the Duo sidebar, whichever the current
        // layout uses (build 63).
        updateSideBarLayout()
        updatePillVisibility()
        // 26E127 fix 8: first launch asks for location permission once, after the splash (and the What's New page, if any — that path returns above) and before the main interface is used.
        requestFirstLaunchLocation()
    }

    // MARK: - First-launch What's New, native full-screen page (26E125)

    // Show the native What's New page: title + a scrollable body +
    // a confirm button pinned above the safe area. The body scrolls;
    // the button never moves, on any screen size — the 26E124 web
    // overlay's button sat at the bottom of its card, under the
    // native tab bar, and users could not enter the app. The page
    // covers the webView and every native control (added last, on
    // top); chrome stays hidden through the whatsNewShowing gate.
    func showWhatsNewPage() {
        guard let payload = pendingWhatsNew, !whatsNewShowing else { return }
        whatsNewShowing = true
        pendingWhatsNew = nil
        let dark = splashDarkResolved()
        let page = UIView()
        page.translatesAutoresizingMaskIntoConstraints = false
        page.backgroundColor = dark ? UIColor(red: 16.0 / 255.0, green: 20.0 / 255.0, blue: 32.0 / 255.0, alpha: 1) : UIColor(red: 242.0 / 255.0, green: 242.0 / 255.0, blue: 247.0 / 255.0, alpha: 1)
        let fg: UIColor = dark ? .white : .black
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = (payload["title"] as? String) ?? ""
        titleLabel.font = .boldSystemFont(ofSize: 22)
        titleLabel.textColor = fg
        titleLabel.numberOfLines = 0
        let body = UITextView()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.isEditable = false
        body.isScrollEnabled = true
        body.backgroundColor = .clear
        body.textColor = fg
        body.font = .systemFont(ofSize: 16)
        body.text = ((payload["lines"] as? [String]) ?? []).joined(separator: "\n\n")
        body.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        body.textContainer.lineFragmentPadding = 0
        let confirmButton = UIButton(type: .system)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.setTitle((payload["confirm"] as? String) ?? "", for: .normal)
        confirmButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        confirmButton.setTitleColor(.white, for: .normal)
        confirmButton.backgroundColor = .systemBlue
        confirmButton.layer.cornerRadius = 14
        confirmButton.addTarget(self, action: #selector(dismissWhatsNewPage), for: .touchUpInside)
        page.addSubview(titleLabel)
        page.addSubview(body)
        page.addSubview(confirmButton)
        view.addSubview(page)
        view.bringSubviewToFront(page)
        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: view.topAnchor),
            page.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            page.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            titleLabel.topAnchor.constraint(equalTo: page.safeAreaLayoutGuide.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -24),
            body.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            body.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 24),
            body.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -24),
            body.bottomAnchor.constraint(equalTo: confirmButton.topAnchor, constant: -16),
            confirmButton.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 24),
            confirmButton.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -24),
            confirmButton.bottomAnchor.constraint(equalTo: page.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            confirmButton.heightAnchor.constraint(equalToConstant: 52)
        ])
        whatsNewView = page
    }

    // Confirm: record the seen build in the web store (the same key
    // the 26E124 confirm wrote), then reveal the app.
    @objc func dismissWhatsNewPage() {
        guard whatsNewShowing else { return }
        whatsNewShowing = false
        webView.evaluateJavaScript("try{localStorage.setItem('metro-lastSeenVersion','26F128')}catch(e){}", completionHandler: nil)
        whatsNewView?.removeFromSuperview()
        whatsNewView = nil
        updateSideBarLayout()
        updatePillVisibility()
        // 26E127 fix 8: the What's New page was in front of the splash — the first-launch location ask goes here, after it is dismissed.
        requestFirstLaunchLocation()
    }

    // MARK: - Search Conditions screen (build 65; wired in place
    // of the build-34 time picker, build 77)

    // The top-right 现在出发 label (web) asks the native shell for the
    // search-conditions screen: a full-screen native Apple UI page
    // (SearchConditionsViewController) with 出发 / 到达 / 首班车 /
    // 末班车, a date+time picker, a 交通卡 / 现金 row, and 现在出发 /
    // 完成. It replaces the old simple time-picker sheet (build 34),
    // whose code is removed entirely below — there is now only one
    // picker reachable.
    // The chosen mode/date/time/payment comes back through onDone.
    // NOTE: window.metroApp.applySearchConditions(...) exists on the
    // web side (build 77) and handles now/depart/arrive/first/last
    // plus payment and date. The old setDepartTime(t) fallback was
    // removed — it would have treated an arrive-by time as a
    // departure time. The payment choice never changes fares (no
    // verified card-vs-cash discount rule) and is remembered locally.
    func presentSearchConditions(current: String?) {
        let vc = SearchConditionsViewController()
        vc.labels = [
            "search.title": L("search.title"),
            "tr.depart": L("tr.depart"),
            "tr.arrive": L("tr.arrive"),
            "search.first": L("search.first"),
            "search.last": L("search.last"),
            "search.card": L("search.card"),
            "search.cash": L("search.cash"),
            "search.applepay": L("search.applepay"),
            "search.applepay.unavailable.title": L("search.applepay.unavailable.title"),
            "search.applepay.unavailable.message": L("search.applepay.unavailable.message"),
            "tr.departNow": L("tr.departNow"),
            "time.done": L("time.done"),
        ]
        vc.accent = accentColor()
        if let savedMode = UserDefaults.standard.string(forKey: "metro-search-mode"),
           ["depart", "arrive", "first", "last"].contains(savedMode) {
            vc.initialMode = savedMode
        }
        vc.initialDate = dateFromDepartTime(current) ?? Date()
        if let savedPay = UserDefaults.standard.string(forKey: "metro-payment"),
           ["card", "cash", "applepay"].contains(savedPay) {
            vc.initialPayment = savedPay
        }
        vc.localeIdentifier = currentLang == "en" ? "en_US" : (currentLang == "zh-Hant" ? "zh_TW" : "zh_CN")
        vc.onDone = { [weak self] dict in
            guard let self = self else { return }
            if let mode = dict["mode"] as? String {
                UserDefaults.standard.set(mode, forKey: "metro-search-mode")
            }
            if let payment = dict["payment"] as? String {
                UserDefaults.standard.set(payment, forKey: "metro-payment")
            }
            // Forward the full conditions (incl. payment) to the web
            // through applySearchConditions, guarded so this is a
            // no-op until the web receiver lands (same guard pattern
            // as applyDeepLink). The web stores c.payment; payment
            // never changes fares.
            if let mode = dict["mode"] as? String,
               let date = dict["date"] as? String,
               let time = dict["time"] as? String,
               let payment = dict["payment"] as? String {
                let now = dict["now"] as? Bool == true
                let js = "if(window.metroApp && window.metroApp.applySearchConditions){window.metroApp.applySearchConditions({mode:\(self.jsString(mode)),date:\(self.jsString(date)),time:\(self.jsString(time)),payment:\(self.jsString(payment)),now:\(now)})}"
                self.webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
        // Presented inside a UINavigationController so the screen
        // gets a proper navigation bar with the standard back chevron
        // (user 2026-11-19: rebuild as Apple UI SDK 27.2 — no custom
        // dark-circle back button).
        let nav = UINavigationController(rootViewController: vc)
        nav.navigationBar.prefersLargeTitles = false
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    // Parse the web's departTime ("HH:mm") into today's date at that
    // time, for the Search Conditions picker's initial date.
    private func dateFromDepartTime(_ t: String?) -> Date? {
        guard let t = t, !t.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "HH:mm"
        guard let time = fmt.date(from: t) else { return nil }
        let cal = Calendar.current
        let parts = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: Date())
    }

    // MARK: - Transit app link (build 35)

    // The transfer panel's 打开一卡通 / 打开盛京通 / 打开Metro大都会 row:
    // open the current city's transit-card app on the App Store (tap 打开
    // there if it is installed). App Store ids verified via the iTunes
    // Search API 2026-11-15: Beijing Yikatong 1071038870, Shenyang
    // Shengjing Tong 1441271928, Shanghai Metro大都会 1202750238, Dalian
    // 交通e出行 1383655806, Changchun 长春E出行 1481796811, Chengdu 成都地铁-官方APP 1303414976, Shenzhen 深圳地铁-官方APP 848926994. There
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
        case "cc": id = "1481796811"
        case "sz": id = "848926994"
        case "cd": id = "1303414976"
        case "qd": id = "1373547573"
        case "sjz": id = "6444716093"
        case "tj": id = "1445111714"
        case "wx": id = "1213366120"
        case "ly": id = "1533912596"
        case "gz": id = "580097761"
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

    // openURL (build 77): web posts {url, fallback} via
    // window.webkit.messageHandlers.openURL. WKWebView cannot open
    // window.open() or custom schemes on its own, so the native side
    // opens them. url == "app-settings" opens this app's iOS
    // Settings page (used when location permission is denied).
    func openExternalURL(dict: [String: Any]) {
        let urlStr = dict["url"] as? String ?? ""
        let fallbackStr = dict["fallback"] as? String
        if urlStr == "app-settings" {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            return
        }
        if let url = URL(string: urlStr),
           url.scheme == "http" || url.scheme == "https" {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return
        }
        if let url = URL(string: urlStr), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return
        }
        if let fb = fallbackStr, let url = URL(string: fb) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    // MARK: - Location: nearest station (build 63)

    // The user taps 附近车站 in the transfer panel. The permission
    // prompt appears ONLY here, never at launch. If already
    // authorized, fetch one location fix and hand it to the web,
    // which computes the nearest stations (haversine) from the
    // stations' lat/lng and lists them. If denied/restricted, tell
    // the web so it shows a message instead of crashing or hanging.
    // NOTE: station lat/lng is now wired in (Wikidata-verified tables
    // in web/latlng/, inlined by build_offline.py): 1524 of 1644
    // stations across 9 cities have coordinates; unmatched stations
    // are simply absent and are skipped by the nearest search.
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
        if locPermPending {
            locPermPending = false
            UserDefaults.standard.set(true, forKey: "metro-locAsked") // 26E127 fix 8: the first-launch ask is spent once the user answers.
            reportLocationPermission()
        }
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

    // 26E127 fix 8: first launch asks for location permission once, after the splash (and the What's New page, if any) and before the main interface is used. The flag is set only once the authorization actually leaves .notDetermined (in locationManagerDidChangeAuthorization), so killing the app mid-prompt does not burn the one ask. iOS itself only shows the system prompt while .notDetermined, so it can only fire once per install; the Settings location row already reports the real state.
    func requestFirstLaunchLocation() {
        guard UserDefaults.standard.object(forKey: "metro-locAsked") == nil else { return }
        requestLocationPermission()
    }

    // Location permission (Settings row): report the current state to
    // the web, or trigger the system prompt if not yet determined.
    // Never prompts twice: when already denied/restricted the web
    // shows the iOS Settings hint instead. A query (from launch)
    // only reports the state and never prompts.
    func requestLocationPermission(queryOnly: Bool = false) {
        if locationManager == nil {
            let lm = CLLocationManager()
            lm.delegate = self
            lm.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManager = lm
        }
        guard let lm = locationManager else { return }
        if lm.authorizationStatus == .notDetermined && !queryOnly {
            locPermPending = true
            lm.requestWhenInUseAuthorization()
        } else {
            reportLocationPermission()
        }
    }

    func reportLocationPermission() {
        let status: String
        if let lm = locationManager {
            switch lm.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: status = "granted"
            case .denied: status = "denied"
            case .restricted: status = "restricted"
            default: status = "unknown"
            }
        } else {
            status = "unknown"
        }
        webView.evaluateJavaScript("window.metroApp && window.metroApp.locPermStatus('\(status)')", completionHandler: nil)
    }

    // MARK: - Native tab bar -> web page

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        setWebTab(index: item.tag)
    }

    func setWebTab(index: Int) {
        guard index >= 0 && index < tabKeys.count else { return }
        let key = tabKeys[index]
        currentTab = key
        setTopChromeHidden(false) // 26E126 R: a tab switch always re-shows the top chrome.
        // 26F128 F: sub-view chrome (back button + strip) belongs to
        // the more/timetable tabs only. The re-show above can unhide
        // a latched back button before the web's subView post lands
        // (the stray "<" beside the city pill on the map tab) — force
        // it down on every other tab; the web re-asserts it when a
        // sub-view is genuinely open on return.
        if key != "more" && key != "timetable" { setSubChromeVisible(false) }
        view.backgroundColor = rootBackgroundColor() // Sidebar strip follows the tab's page background.
        updatePillVisibility()
        updateTransferVisibility()
        // 26E127 fix 10: re-apply the last transfer frame when entering the transfer tab (see lastTransferFrame).
        if key == "transfer", let f = lastTransferFrame { placeTransfer(frame: f) }
        updateSideBarSelection()
        if key != "transfer" { sortTabs.isHidden = true }
        // The structure panel lives under "more" since 26E112:
        // leaving the Settings tab hides its native chrome at once
        // (the web closes the panel in the same setTab pass and its
        // next structFrame post reports panel: false).
        if key != "more" { hideStructChrome() }
        webView.evaluateJavaScript("window.metroApp && window.metroApp.setTab('\(key)')", completionHandler: nil)
    }

    @objc func handleTabSwipe(_ gesture: UISwipeGestureRecognizer) {
        let current = tabKeys.firstIndex(of: currentTab) ?? tabBar.selectedItem?.tag ?? 1
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

        let titles = tabTitles()
        let images = tabImages()
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
            sideBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), // Real screen edge, NOT the safe area: on the unfolded Duo the safe area's trailing inset is huge and left a ~20% black strip with the sidebar floating at its inner edge (user 2026-11-21).
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
        // Semibold since 26E110 (medium before): the sidebar shares
        // tabImages(), whose glyphs are now solid (.fill variants /
        // solid PNG); semibold keeps the two stroke-based glyphs
        // (transfer arrows, magnifier — no .fill variant exists) in
        // the same solid family here too. Point size unchanged.
        cfg.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        cfg.baseForegroundColor = selected ? accentColor() : .label
        var bg = UIBackgroundConfiguration.clear()
        bg.backgroundColor = selected ? accentColor().withAlphaComponent(0.15) : .clear
        bg.cornerRadius = 10
        cfg.background = bg
        return cfg
    }

    // Root background colour: matches the CURRENT TAB's web page
    // background exactly, per appearance, so the strip beside the Duo
    // sidebar (the web view stops at the sidebar's leading edge) has
    // no seam in either theme (user 2026-11-22: in light mode the
    // strip was bright white beside Settings' lavender page). Web
    // values (web/template.html): light — #moreSheet #f2f2f7, the map
    // body and the transfer/stations/timetable panels #ffffff; dark —
    // #transferPanel/#stationPanel #101420, the map body, #moreSheet
    // and #timetablePanel #000000 (the html.dark base #0c0f16 is
    // overridden by body and every panel, so it is never the visible
    // page background). Refreshed wherever the theme refresh already
    // happens, plus on every tab change (setWebTab / tabChanged).
    func rootBackgroundColor() -> UIColor {
        let dark = splashDarkResolved()
        if dark {
            if currentTab == "transfer" || currentTab == "stations" || structPanelOpen {
                return UIColor(red: 16.0 / 255.0, green: 20.0 / 255.0, blue: 32.0 / 255.0, alpha: 1) // #101420
            }
            return .black // #000000
        }
        if currentTab == "more" {
            return UIColor(red: 242.0 / 255.0, green: 242.0 / 255.0, blue: 247.0 / 255.0, alpha: 1) // #f2f2f7
        }
        return .white // #ffffff
    }

    // 26F128: solid (non-glass) chrome colours for the transfer-page
    // header + profile page (user 2026-11-25 "取消玻璃效果", scope
    // confirmed "就这两页"). Card = the web cards' own colours:
    // white in light mode, #1c1c1e in dark. Track/pill are the
    // classic segmented-control pair for sortTabs.
    func solidCardColor() -> UIColor {
        return splashDarkResolved()
            ? UIColor(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 30.0 / 255.0, alpha: 1) // #1c1c1e
            : .white // #ffffff
    }
    func solidTrackColor() -> UIColor {
        return splashDarkResolved()
            ? UIColor(red: 44.0 / 255.0, green: 44.0 / 255.0, blue: 46.0 / 255.0, alpha: 1) // #2c2c2e
            : UIColor(red: 233.0 / 255.0, green: 233.0 / 255.0, blue: 234.0 / 255.0, alpha: 1) // #e9e9ea
    }
    func solidPillColor() -> UIColor {
        return splashDarkResolved()
            ? UIColor(red: 99.0 / 255.0, green: 99.0 / 255.0, blue: 102.0 / 255.0, alpha: 1) // #636366
            : .white // #ffffff
    }

    // Re-apply the solid colours after a theme change (the web's
    // themeState post and trait changes both land here). Only the
    // 26F128 de-glassed pieces; everything else keeps its glass.
    func refreshSolidChrome() {
        transferCard?.backgroundColor = solidCardColor()
        profileInfoCard?.backgroundColor = solidCardColor()
        profileSaveRow?.backgroundColor = solidCardColor()
        profileRedeemRow?.backgroundColor = solidCardColor()
        profileLogoutRow?.backgroundColor = solidCardColor()
        departButton?.backgroundColor = solidCardColor()
        if let st = sortTabs {
            st.backgroundColor = solidTrackColor()
            st.selectedSegmentTintColor = solidPillColor()
        }
        for b in [transitAppButton, nearbyStationsButton, applePayButton] {
            guard let b = b, var cfg = b.configuration else { continue }
            cfg.baseBackgroundColor = solidCardColor()
            b.configuration = cfg
        }
    }

    // Sidebar = iPhone Duo UNFOLDED only (user 2026-11-22: a regular
    // iPhone keeps the floating BOTTOM tab bar in landscape too — the
    // old rule, width >= 700 or portrait width >= 600, caught every
    // landscape iPhone, e.g. 874x402). The Duo's unfolded inner display
    // is >= 600pt in BOTH dimensions in either orientation (portrait
    // ~690pt wide, landscape the same canvas swapped), while a regular
    // iPhone always fails one dimension (portrait width <= 440pt;
    // landscape height <= 440pt) — and so does the folded Duo (outer
    // display fails one dimension in both orientations). iPad never
    // gets the sidebar — it keeps its top tab bar.
    func sideBarShouldShow() -> Bool {
        if UIDevice.current.userInterfaceIdiom != .phone { return false }
        let w = view.bounds.width
        let h = view.bounds.height
        return w >= 600 && h >= 600
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
        // One bar system on every device (26E115): the system
        // UITabBar is the visible bar (bottom on iPhone, top
        // capsule on iPad); the Duo sidebar replaces it on a wide
        // iPhone, and the splash gate hides both.
        tabBar.isHidden = show || splashShowing || whatsNewShowing
        sideBar.isHidden = !show || splashShowing || whatsNewShowing
        updateSideBarSelection()
        reportBarFrame()
    }

    // Report the system tab bar's REAL frame to the web (26E115):
    // the page's bottom clearances (the Settings home-lock bottom
    // padding, the timetable panel's bottom inset and its
    // background extension) are driven by a --bar-clear CSS
    // variable, so they must follow the bar the system actually
    // laid out — its height is intrinsic (never pinned) and
    // differs between portrait and landscape. The reported value
    // is the distance from the screen's bottom edge to the bar's
    // top edge; it is 0 whenever no bottom bar is on screen (iPad
    // top bar, Duo sidebar, splash), where the page's own iPad /
    // sidebar rules own the clearances. Called from
    // viewDidLayoutSubviews (every layout pass), updateSideBarLayout
    // (visibility flips) and didFinish (fresh page); unchanged
    // values are not re-posted.
    func reportBarFrame() {
        guard tabBar != nil, webView != nil else { return }
        var clearance: CGFloat = 0
        if UIDevice.current.userInterfaceIdiom == .phone && !sideBarActive && !tabBar.isHidden {
            let f = tabBar.frame
            if f.height > 0 && f.minY > 0 {
                clearance = max(0, view.bounds.height - f.minY)
            }
        }
        if abs(clearance - lastBarClearance) < 0.5 { return }
        lastBarClearance = clearance
        let v = String(format: "%.1f", clearance)
        webView.evaluateJavaScript("window._metroBarClearance = \(v); if (window.metroApp && window.metroApp.setBarClearance) { window.metroApp.setBarClearance(\(v)); }", completionHandler: nil)
    }

    // Keep the sidebar's selected highlight in sync with currentTab
    // (and with the city accent). Called by updateSideBarLayout,
    // setWebTab, the tabChanged handler and refreshCityUI.
    func updateSideBarSelection() {
        guard !sideBarButtons.isEmpty else { return }
        let idx = tabKeys.firstIndex(of: currentTab) ?? 1
        let titles = tabTitles()
        let images = tabImages()
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
        // Notifications replace the Live Activity UI (the widget
        // extension is removed, so the activity above has no Dynamic
        // Island / lock-screen UI): ask once, then alert at arrival
        // even when the activity request just failed.
        requestTripNotificationPermission()
        scheduleTripArrivalNotification(from: from, to: to, next: next, arrival: arrival)
    }

    func updateTripActivity(_ dict: [String: Any]) {
        guard #available(iOS 16.2, *) else { return }
        // Keep the arrival alert in step with the trip, even when there
        // is no Live Activity (extension removed, so tripActivity is nil).
        if let from = dict["from"] as? String, !from.isEmpty,
           let to = dict["to"] as? String, !to.isEmpty,
           let next = dict["nextStation"] as? String,
           let arrivalMs = dict["arrivalMs"] as? Double {
            let arrival = Date(timeIntervalSince1970: arrivalMs / 1000)
            scheduleTripArrivalNotification(from: from, to: to, next: next, arrival: arrival)
        }
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
        // Cancel the arrival alert so it never fires after the trip ends.
        cancelTripArrivalNotification()
        guard let activity = tripActivity as? Activity<TripAttributes> else { return }
        tripActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: - Trip arrival notification (local only, 1.0.5)

    // Local notifications replace the Live Activity UI now that the
    // widget extension is removed (全能签 cannot sign an appex, user
    // 2026-11-19). Once the user grants permission, iOS adds a
    // "Notifications" entry in Settings > Subway Tools, and the user
    // can turn alerts off there; the system then suppresses the
    // scheduled alert automatically. No remote push, no entitlements
    // file, no new .swift file. The Live Activity code above is
    // untouched and still fails silently without the extension.
    private let tripNotificationID = "metro-trip-arrival"

    // Ask for notification permission once, at trip start. Only prompts
    // when the user has not decided yet; a prior allow/deny is respected
    // and never re-prompted.
    func requestTripNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    // Schedule (or reschedule) the arrival alert for this trip. Cancels
    // any previous arrival alert first, so only one is ever pending.
    // Skips when the arrival time is already past.
    func scheduleTripArrivalNotification(from: String, to: String, next: String, arrival: Date) {
        cancelTripArrivalNotification()
        let interval = arrival.timeIntervalSinceNow
        guard interval > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = L("live.arrived")
        content.body = L("live.notifyBody")
            .replacingOccurrences(of: "{from}", with: from)
            .replacingOccurrences(of: "{to}", with: to)
            .replacingOccurrences(of: "{next}", with: next)
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: tripNotificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // Remove the pending arrival alert (trip ended or superseded).
    func cancelTripArrivalNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [tripNotificationID])
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
            view.backgroundColor = rootBackgroundColor() // Sidebar strip follows the tab's page background.
            updatePillVisibility()
            updateTransferVisibility()
            // 26E127 fix 10: same re-apply as setWebTab — the web-driven tab change can also land on transfer with a lost frame post.
            if tab == "transfer", let f = lastTransferFrame { placeTransfer(frame: f) }
            tabBar.selectedItem = tabBar.items?[idx]
            updateSideBarSelection()
            // The native Siri-page switch only exists on the
            // Settings tab (26C101).
            if tab != "more" { hideNearbySmartSwitch() }
            if tab != "map" { hideMapCard() }
        } else if message.name == "cityMenu" {
            presentCityMenuPopover()
        } else if message.name == "splashDone" {
            splashFinished()
        } else if message.name == "whatsNew" {
            // 26E125: the web posts this build's What's New entry
            // from mounted() when the stored build differs. Hold it
            // until the splash ends; if the splash is already done
            // (late post), show it at once.
            if let dict = message.body as? [String: Any] {
                pendingWhatsNew = dict
                if !splashShowing && !whatsNewShowing { showWhatsNewPage() }
            }
        } else if message.name == "splashState" {
            // 26C102: the page posts its resolved city + dark state
            // from an inline script at parse time — long before Vue
            // mounts and its cityChanged / themeState posts fire — so
            // the launch poster's persisted state gets an early,
            // independent correction even if the mounted() posts are
            // delayed or lost on device. Same keys the other handlers
            // write; the poster re-picks immediately.
            if let dict = message.body as? [String: Any] {
                if let city = dict["city"] as? String,
                   ["bj", "sy", "sh", "hb", "dl", "jh", "cz", "cq", "cc", "sz", "cd", "qd", "sjz", "tj", "wx", "ly", "gz"].contains(city) {
                    UserDefaults.standard.set(city, forKey: "metro-city")
                    currentCity = city
                }
                if let dark = dict["dark"] as? Bool {
                    UserDefaults.standard.set(dark, forKey: "metro-dark")
                    themeResolvedThisSession = true // the web's own report now outranks the launch resolution (26E109)
                }
                refreshSplashImage()
            }
        } else if message.name == "themeState" {
            // The web reports its effective appearance on every
            // applyTheme (launch + every change). Persist it so the
            // NEXT launch's native splash can pick the matching
            // light/dark poster before the page loads.
            if let dict = message.body as? [String: Any],
               let dark = dict["dark"] as? Bool {
                UserDefaults.standard.set(dark, forKey: "metro-dark")
                themeResolvedThisSession = true // the web's own report now outranks the launch resolution (26E109)
                // Also persist the web's theme MODE (system/light/dark)
                // when the report carries it, so the launch injection
                // can hand the web its exact previous appearance state.
                if let mode = dict["theme"] as? String {
                    UserDefaults.standard.set(mode, forKey: "metro-theme")
                }
                // Correct the launch poster in place if the launch
                // pick used a stale appearance (2026-11-20 fix).
                refreshSplashImage()
                view.backgroundColor = rootBackgroundColor()
                subTopCover?.backgroundColor = rootBackgroundColor() // iPad sub-view top cover follows the page background (2026-11-22).
                refreshSolidChrome() // 26F128: de-glassed pieces follow the theme.
            }
        } else if message.name == "cityChanged",
                  let dict = message.body as? [String: Any],
                  let city = dict["city"] as? String,
                  ["bj", "sy", "sh", "hb", "dl", "jh", "cz", "cq", "cc", "sz", "cd", "qd", "sjz", "tj", "wx", "ly", "gz"].contains(city) {
            // The web switched cities (user switch or the startup
            // restore). Mirror it natively; the web already switched,
            // so do NOT call switchCity here (that would loop).
            UserDefaults.standard.set(city, forKey: "metro-city")
            if city != currentCity {
                currentCity = city
                refreshCityUI()
            }
            // Correct the launch poster in place if the launch pick
            // used a stale city (2026-11-20 fix).
            refreshSplashImage()
        } else if message.name == "langChanged",
                  let dict = message.body as? [String: Any],
                  let lang = dict["lang"] as? String {
            // The web switched languages. explicit == true only when the
            // user tapped a language option (or Follow System) in the
            // in-app picker; the startup restore post has explicit false
            // and must not become an override. The web already switched,
            // so do NOT call setLang on the web here (that would loop).
            let explicit = (dict["explicit"] as? Bool) ?? false
            setLang(lang, explicit: explicit)
        } else if message.name == "tabsFrame",
                  let dict = message.body as? [String: Any] {
            placeSortTabs(frame: dict)
        } else if message.name == "structFrame",
                  let dict = message.body as? [String: Any] {
            placeStructChrome(frame: dict)
        } else if message.name == "transferFrame",
                  let dict = message.body as? [String: Any] {
            placeTransfer(frame: dict)
        } else if message.name == "themeFrame",
                  let dict = message.body as? [String: Any] {
            placeThemeButtons(frame: dict)
        } else if message.name == "switchFrame",
                  let dict = message.body as? [String: Any] {
            placeSwitch(frame: dict)
        } else if message.name == "profileFrame",
                  let dict = message.body as? [String: Any] {
            // 26E123 ⑤: profile page glass placement (info-card
            // backplate + Save / Redeem / Sign Out glass rows).
            placeProfile(frame: dict)
        } else if message.name == "mapCardFrame",
                  let dict = message.body as? [String: Any] {
            // 26E124: the map station card's state — the whole
            // card is native (placeMapCard).
            placeMapCard(dict)
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
            } else {
                toField.text = name
            }
            // 26E110 P: the post carries ALL lines of the station;
            // show one pill per line. Older posts fall back to the
            // single picked line.
            if let lines = dict["lines"] as? [[String: Any]], !lines.isEmpty {
                applyBadges(which: which, lines: lines, pinnedKey: line?["key"] as? String)
            } else {
                applyBadge(which: which, line: line)
            }
            updateClearButtons()
            view.endEditing(true)
        } else if message.name == "fastNote",
                  let dict = message.body as? [String: Any] {
            // 26E121 H: the fast-transfer note is presented as a
            // NATIVE UIAlertController — the system Liquid Glass
            // alert on iOS 26 / SDK 27.2 — instead of the web-drawn
            // card (user: 改成真·液态玻璃 Apple UI). The web sends
            // the already-localized pieces (station name, the
            // station's note text verbatim, the tag title, the OK
            // label); the title composes as "{station} · 快速换乘".
            // Appearance (light/dark) is the system's own.
            let station = dict["station"] as? String ?? ""
            let note = dict["note"] as? String ?? ""
            let tag = dict["tag"] as? String ?? ""
            let ok = dict["ok"] as? String ?? "OK"
            if !note.isEmpty && presentedViewController == nil {
                let title = tag.isEmpty ? station : station + " · " + tag
                let alert = UIAlertController(title: title, message: note, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: ok, style: .default, handler: nil))
                present(alert, animated: true, completion: nil)
            }
        } else if message.name == "redeemCode",
                  let dict = message.body as? [String: Any] {
            // 26E122: creator redemption input — a native
            // UIAlertController with a text field collects the code;
            // the entered text returns via window.__redeemEntered.
            presentRedeemInput(dict: dict)
        } else if message.name == "redeemNote",
                  let dict = message.body as? [String: Any] {
            // 26E122: creator redemption result — a native alert
            // carrying the web-composed (already localized) title
            // and message （兑换成功 / 兑换码无效）.
            let title = dict["title"] as? String ?? ""
            let msg = dict["message"] as? String ?? ""
            let ok = dict["ok"] as? String ?? "OK"
            if presentedViewController == nil {
                let alert = UIAlertController(title: title, message: msg.isEmpty ? nil : msg, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: ok, style: .default, handler: nil))
                present(alert, animated: true, completion: nil)
            }
        } else if message.name == "commonCityPick",
                  let dict = message.body as? [String: Any] {
            // 26E122: Home City picker — a native action sheet (the
            // Use-My-Location row first, then the adapted cities).
            presentCommonCitySheet(dict: dict)
        } else if message.name == "recommendCity",
                  let dict = message.body as? [String: Any] {
            // 26E122: Home City location recommendation — a native
            // confirm alert ("推荐设为 {城市名}（约 N 公里）"); only a
            // confirm writes the city (via __recommendCityConfirmed).
            if presentedViewController == nil {
                let alert = UIAlertController(title: dict["title"] as? String ?? "",
                                              message: dict["message"] as? String ?? "", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: dict["ok"] as? String ?? "OK", style: .default, handler: { _ in
                    self.webView.evaluateJavaScript("window.__recommendCityConfirmed && window.__recommendCityConfirmed(true)", completionHandler: nil)
                }))
                alert.addAction(UIAlertAction(title: dict["cancel"] as? String ?? "Cancel", style: .cancel, handler: { _ in
                    self.webView.evaluateJavaScript("window.__recommendCityConfirmed && window.__recommendCityConfirmed(false)", completionHandler: nil)
                }))
                present(alert, animated: true, completion: nil)
            }
        } else if message.name == "commonCityNote",
                  let dict = message.body as? [String: Any] {
            // 26E122: location unavailable for the Home City
            // recommendation — never silent: this alert, and on OK
            // the picker sheet comes back (the manual list).
            if presentedViewController == nil {
                let msg = dict["message"] as? String ?? ""
                let alert = UIAlertController(title: dict["title"] as? String ?? "",
                                              message: msg.isEmpty ? nil : msg, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: dict["ok"] as? String ?? "OK", style: .default, handler: { _ in
                    if let p = self.lastCommonCityPick { self.presentCommonCitySheet(dict: p) }
                }))
                present(alert, animated: true, completion: nil)
            }
        } else if message.name == "timePicker",
                  let dict = message.body as? [String: Any] {
            let current = dict["departTime"] as? String
            presentSearchConditions(current: current)
        } else if message.name == "openTransitApp" {
            openTransitApp()
        } else if message.name == "openRideCode",
                  let dict = message.body as? [String: Any] {
            openRideCode(link: dict["link"] as? String ?? "#小程序://乘车码/cZxzR2rsEppAxSv")
        } else if message.name == "requestLocation" {
            requestNearbyLocation()
        } else if message.name == "requestLocationPermission" {
            if let dict = message.body as? [String: Any], dict["query"] as? Bool == true {
                requestLocationPermission(queryOnly: true)
            } else {
                requestLocationPermission()
            }
        } else if message.name == "openURL",
                  let dict = message.body as? [String: Any] {
            openExternalURL(dict: dict)
        } else if message.name == "liveActivity",
                  let dict = message.body as? [String: Any] {
            handleLiveActivity(dict)
        } else if message.name == "clearCache" {
            clearWebCache()
        } else if message.name == "subView" {
            // Native sub-view back button (user 2026-11-18): the web posts
            // {open: Bool} whenever sub-view open-state changes — open is
            // true while any Settings sub-view or a timetable line detail
            // is open, false otherwise. It also posts {scroll: Bool}
            // while a sub-view is open (kept only as a state record now;
            // user 2026-11-20 22:53: the header is always shown while a
            // sub-view is open, scrolled or not). Malformed bodies are
            // ignored.
            if let dict = message.body as? [String: Any] {
                if let scrolled = dict["scroll"] as? Bool {
                    // A static page that actually scrolls (small
                    // screens) graduates to the normal frosted strip.
                    if scrolled { subViewStatic = false }
                    if let button = subViewBackButton, !button.isHidden {
                        setSubScrolled(scrolled)
                    }
                } else if let open = dict["open"] as? Bool {
                    if open {
                        subScrolled = (dict["scrolled"] as? Bool) ?? false
                        if let title = dict["title"] as? String, !title.isEmpty {
                            subTimetableMode = false
                            subDockTitle = title
                            subFrameCenter = nil
                        } else {
                            subTimetableMode = true
                            // The timetable detail keeps its title in the
                            // web's .tt-title row, so the native strip
                            // shows no centred title for it.
                            subDockTitle = nil
                            if let cx = dict["cx"] as? NSNumber, let cy = dict["cy"] as? NSNumber {
                                subFrameCenter = (CGFloat(cx.doubleValue), CGFloat(cy.doubleValue))
                            }
                        }
                        subViewStatic = (dict["static"] as? Bool) ?? false
                        dockSubViewBackButton()
                        // 26C102 stale-title fix: unhide the chrome
                        // BEFORE refreshing the header state.
                        // applySubScrollState refreshes the title text
                        // and strip height only while the back button
                        // is not hidden; the old order (refresh, then
                        // unhide) made the open-time refresh a no-op,
                        // so the previous page's title survived until
                        // the next scroll post — and a page that never
                        // scrolls (What's New) kept it for good.
                        setSubChromeVisible(true)
                        setTopChromeHidden(false) // 26E126 R: opening a sub-view re-shows the top chrome.
                        applySubScrollState(animated: false)
                    } else {
                        subViewStatic = false
                        setSubViewHeader(title: nil)
                        setSubChromeVisible(false)
                        setTopChromeHidden(false) // 26E126 R: closing a sub-view re-shows the top chrome.
                        // No sub-view open: the Siri page (and its
                        // native switch) is gone too (26C101). Opening
                        // a DIFFERENT sub-view posts fresh zero frames
                        // from the web, which hide it the same way.
                        hideNearbySmartSwitch()
                    }
                }
            }
        } else if message.name == "topChrome" {
            // 26E126 R: iPad scroll-hide for the top chrome.
            if let dict = message.body as? [String: Any], let hide = dict["hide"] as? Bool {
                setTopChromeHidden(hide)
            }
        } else if message.name == "mapState",
              let dict = message.body as? [String: Any],
              let downloaded = dict["downloaded"] as? [String] {
            // 26E126 J: the web reports which cities have a
            // downloaded line map. Rebuild the city pill menu so
            // its download affordances match, and refresh the
            // download button's count.
            downloadedMapCities = Set(downloaded)
            if let lm = dict["lineMaps"] as? Int { downloadedLineMapCount = lm }
            cityPill.menu = cityMenu()
            mapsDownloadLabel?.text = L("map.downloaded").replacingOccurrences(of: "{n}", with: "\(downloadedLineMapCount)")
        } else if message.name == "mapsDownloadFrame",
                  let dict = message.body as? [String: Any] {
            placeMapsDownload(frame: dict)
        } else if message.name == "cityDownloadFrame",
                  let dict = message.body as? [String: Any],
                  let cities = dict["cities"] as? [[String: Any]] {
            placeCityDownloadButtons(frames: cities)
        } else if message.name == "departFrame",
                  let dict = message.body as? [String: Any] {
            placeDepartButton(frame: dict)
        } else if message.name == "mapProgress",
                  let dict = message.body as? [String: Any],
                  let done = dict["done"] as? Int,
                  let total = dict["total"] as? Int {
            updateMapsDownloadUI(done: done, total: total)
        } else if message.name == "openLanguage" {
            // Native Language picker (user 2026-11-19): the web posts
            // here instead of opening its own 语言 sub-view (the template
            // falls back to the web sub-view if this handler is absent).
            // No body is needed.
            presentLanguage()
        } else if message.name == "openAppearance" {
            // Native Appearance picker (user 2026-11-19): the web posts
            // here instead of opening its own 外观 sub-view (the template
            // agent falls back to the web sub-view if this handler is
            // absent). No body is needed.
            presentAppearance()
        }
    }

    // Clear cache (user 2026-11-18, Settings General -> Clear cache):
    // the web posts to the "clearCache" message handler. Clears the web
    // view's HTTP disk/memory cache and the cached briefing (localStorage
    // 'metro-briefing') only. It does NOT touch UserDefaults preferences
    // (city, language, theme, search mode/payment), the web localStorage
    // search history ('metro-search-history'), city/language mirrors, or
    // the bundled offline files. A full
    // WKWebsiteDataStore.allWebsiteDataTypes() wipe is deliberately NOT
    // used: it would also erase localStorage, including search history.
    // No web callback is wired: no cacheCleared receiver exists in
    // web/template.html (checked 2026-11-18), so the web shows its own
    // confirmation after posting. The briefing re-seeds from the inlined
    // BRIEFING_SEED and re-fetches on next load.
    func clearWebCache() {
        // HTTP disk + memory cache.
        WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache],
            modifiedSince: .distantPast,
            completionHandler: {})
        // Briefing cache only (localStorage 'metro-briefing'); leave
        // metro-city / metro-lang / metro-search-history untouched.
        webView.evaluateJavaScript("try{localStorage.removeItem('metro-briefing');}catch(e){}", completionHandler: nil)
    }

    // MARK: - Siri Shortcuts + subwaymotion:// deep links
    // (user 2026-11-18, Settings -> Siri 快捷指令). The 6 intents in
    // AppIntents.swift open the app at a subwaymotion:// URL; the URLs
    // arrive here from SceneDelegate (warm open) or from the cold-launch
    // urlContexts (stashed until the page loads). Routing reuses the
    // existing native/web entry points only — no new navigation path.

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webPageReady = true
        // Fresh page: force a bar-frame report even if the value
        // has not changed since the last page (26E115).
        lastBarClearance = -1
        reportBarFrame()
        flushPendingDeepLink()
    }

    // App Intent deep link delivered in-process (26C101): route it
    // through the exact same path as a subwaymotion:// URL open, and
    // clear the UserDefaults stash so the didBecomeActive consume
    // below cannot apply it a second time.
    @objc func handleIntentDeepLink(_ note: Notification) {
        guard let url = note.userInfo?["url"] as? URL else { return }
        UserDefaults.standard.removeObject(forKey: SubwayDeepLink.pendingKey)
        handleDeepLink(url)
    }

    // Cold-start fallback for intent deep links: perform() may have
    // run before this controller registered its observer, leaving
    // only the UserDefaults stash. Consume it once on activation.
    @objc func consumePendingIntentDeepLink() {
        guard let url = SubwayDeepLink.consumePending() else { return }
        handleDeepLink(url)
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "subwaymotion" else { return }
        guard webPageReady else { pendingDeepLinkURL = url; return }
        applyDeepLink(url)
    }

    // Apply a stashed deep link once the page is ready. The Vue app
    // mounts during page parse, so window.metroApp is normally present
    // at didFinish; retry briefly if it is not there yet.
    func flushPendingDeepLink(attempt: Int = 0) {
        guard let url = pendingDeepLinkURL else { return }
        webView.evaluateJavaScript("!!(window.metroApp && window.metroApp.setTab)") { [weak self] result, _ in
            guard let self = self else { return }
            if (result as? Bool) == true {
                self.pendingDeepLinkURL = nil
                self.applyDeepLink(url)
            } else if attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.flushPendingDeepLink(attempt: attempt + 1)
                }
            } else {
                // Give up silently; the app still opens normally.
                self.pendingDeepLinkURL = nil
            }
        }
    }

    func applyDeepLink(_ url: URL) {
        guard url.scheme == "subwaymotion", let host = url.host else { return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? { query.first(where: { $0.name == name })?.value }
        switch host {
        case "open":
            setWebTab(index: 0)
        case "first-train", "last-train":
            setWebTab(index: 3)
            // The web's applySearchConditions receiver (added by the
            // template agent for the Search Conditions screen) shows
            // first/last trains; guarded so this is a no-op until it
            // lands — the timetable tab is still shown. Date is left
            // out: the receiver defaults it to today.
            let mode = host == "first-train" ? "first" : "last"
            var js = "if(window.metroApp && window.metroApp.applySearchConditions){window.metroApp.applySearchConditions({mode:'\(mode)'"
            if let station = q("station"), !station.isEmpty { js += ",station:\(jsString(station))" }
            js += "})}"
            webView.evaluateJavaScript(js, completionHandler: nil)
        case "route":
            setWebTab(index: 0)
            let from = q("from") ?? ""
            let to = q("to") ?? ""
            if !from.isEmpty {
                webView.evaluateJavaScript("window.metroApp && window.metroApp.setNativeQuery('from', \(jsString(from)))", completionHandler: nil)
            }
            if !to.isEmpty {
                webView.evaluateJavaScript("window.metroApp && window.metroApp.setNativeQuery('to', \(jsString(to)))", completionHandler: nil)
            }
            // doSearch() only when BOTH stations are given. With a
            // missing station it would run on empty fields; leave the
            // transfer tab open instead so the user can pick the
            // stations. (PlanRoute's from/to are required parameters,
            // so Siri / the Shortcuts editor prompts for them; this
            // guard is for a deep link opened without parameters.)
            // doSearch() resolves the names via resolveStation(); if a
            // name does not match a station the web shows its own error.
            if !from.isEmpty && !to.isEmpty {
                webView.evaluateJavaScript("window.metroApp && window.metroApp.doSearch()", completionHandler: nil)
            }
        case "nearby":
            setWebTab(index: 0)
            requestNearbyLocation()
        case "timetable":
            setWebTab(index: 3)
            if let line = q("line"), !line.isEmpty {
                // Filter the timetable line list to the named line.
                webView.evaluateJavaScript("window.metroApp && (window.metroApp.ttQuery = \(jsString(line)))", completionHandler: nil)
            }
        default:
            break
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "canGoBack" {
            backButton.isHidden = !webView.canGoBack
        }
    }

    deinit {
        webView.removeObserver(self, forKeyPath: "canGoBack")
        NotificationCenter.default.removeObserver(self)
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

// MARK: - iPhone floating tab bar (26E113) — RETIRED in 26E115
//
// This class is NOT instantiated anywhere since 26E115: the user
// ruled the hand-drawn bar "not Apple UI Liquid Glass, cannot
// slide", and the iPhone bottom bar is the system UITabBar again
// (see the tab bar setup in viewDidLoad). Kept only as a record of
// the 26E113–26E114 implementation; do not resurrect it as the
// visible bar.
//
// Custom-drawn replacement for the iPhone bottom UITabBar, built to
// the user's measured reference (402pt-wide device screenshot):
// capsule ≈375pt wide (13pt side margins, set by the constraints in
// viewDidLoad), 66pt tall, corner radius = half the height, floating
// 10pt above the safe-area bottom, Liquid Glass body. Inside: 5
// equal cells, each a 30pt icon above an 11pt title — content
// ≈46pt, centred, ZERO clipping by construction: every frame is
// computed from the 66pt height in layoutSubviews (icon y 10 h 30;
// title y 42 h 14; content bottom edge 56, leaving 10pt below),
// never from a system bar's internal layout (the 26E112 UITabBar
// pinned to 62pt overflowed exactly that internal layout and cut
// the titles in half).
// Selected: system-blue icon + title over a light-grey pill inset
// 4pt on each side (translucent light grey in dark mode).
// Unselected: .label (black in light mode, white in dark mode).
// iPhone only — iPad keeps its top UITabBar capsule and the Duo
// keeps its right sidebar; both are untouched.
final class PhoneTabBarView: UIView {
    var onSelect: ((Int) -> Void)?
    private(set) var selectedIndex: Int = 1

    private let iconSide: CGFloat = 30
    private let titleFont = UIFont.systemFont(ofSize: 11)
    private var titles: [String] = []
    private var images: [UIImage?] = []
    private let glassView: UIVisualEffectView
    private let pillView = UIView()
    private var buttons: [UIButton] = []
    private var iconViews: [UIImageView] = []
    private var titleLabels: [UILabel] = []

    override init(frame: CGRect) {
        if #available(iOS 26.0, *) {
            glassView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        } else {
            glassView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        }
        super.init(frame: frame)
        backgroundColor = .clear
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 6)
        glassView.layer.cornerRadius = 33
        glassView.clipsToBounds = true
        glassView.layer.borderWidth = 0.5
        glassView.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        addSubview(glassView)
        pillView.layer.cornerRadius = 27
        pillView.backgroundColor = UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.16)
                : UIColor.systemGray5
        })
        addSubview(pillView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(titles: [String], images: [UIImage?], selected: Int) {
        self.titles = titles
        self.images = images
        selectedIndex = selected
        for b in buttons { b.removeFromSuperview() }
        buttons = []
        iconViews = []
        titleLabels = []
        for i in titles.indices {
            let btn = UIButton(type: .custom)
            btn.tag = i
            btn.addTarget(self, action: #selector(cellTapped(_:)), for: .touchUpInside)
            addSubview(btn)
            buttons.append(btn)
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFit
            iv.isUserInteractionEnabled = false
            addSubview(iv)
            iconViews.append(iv)
            let lb = UILabel()
            lb.font = titleFont
            lb.textAlignment = .center
            lb.isUserInteractionEnabled = false
            addSubview(lb)
            titleLabels.append(lb)
        }
        applyContent()
        setNeedsLayout()
    }

    func reloadTitles(_ titles: [String]) {
        self.titles = titles
        applyContent()
    }

    func setSelected(_ idx: Int) {
        guard idx >= 0 && idx < titles.count else { return }
        let changed = idx != selectedIndex
        selectedIndex = idx
        applyContent()
        if changed && bounds.width > 0 {
            UIView.animate(withDuration: 0.22) { self.layoutPill() }
        } else {
            layoutPill()
        }
    }

    private func applyContent() {
        for i in titles.indices {
            let selected = i == selectedIndex
            let tint: UIColor = selected ? .systemBlue : .label
            iconViews[i].image = images[i]?.withRenderingMode(.alwaysTemplate)
            iconViews[i].tintColor = tint
            titleLabels[i].text = titles[i]
            titleLabels[i].textColor = tint
        }
    }

    @objc private func cellTapped(_ sender: UIButton) {
        onSelect?(sender.tag)
    }

    private func layoutPill() {
        guard !titles.isEmpty, bounds.width > 0 else { return }
        let cellW = bounds.width / CGFloat(titles.count)
        pillView.frame = CGRect(x: CGFloat(selectedIndex) * cellW + 4, y: 6, width: cellW - 8, height: bounds.height - 12)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassView.frame = bounds
        layoutPill()
        guard !titles.isEmpty else { return }
        let cellW = bounds.width / CGFloat(titles.count)
        // Content block: 10pt top pad + 30pt icon + 2pt gap + 14pt
        // title = 56pt of the 66pt capsule (10pt below) — computed
        // in code, so the title can never be clipped by the
        // capsule's bottom edge.
        for i in titles.indices {
            let cellX = CGFloat(i) * cellW
            buttons[i].frame = CGRect(x: cellX, y: 0, width: cellW, height: bounds.height)
            iconViews[i].frame = CGRect(x: cellX + (cellW - iconSide) / 2, y: 10, width: iconSide, height: iconSide)
            titleLabels[i].frame = CGRect(x: cellX, y: 42, width: cellW, height: 14)
        }
    }
}
