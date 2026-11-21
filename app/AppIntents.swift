import AppIntents
import Foundation

// Subway tools — Siri Shortcuts via App Intents (user 2026-11-18,
// "在设置里面加入Siri快捷指令功能").
//
// This is the iPhone's own Siri / Shortcuts app integration. There is
// NO in-app AI search box or voice parser here: each intent brings
// the app to the foreground and hands MapViewController the same
// subwaymotion:// deep link the URL scheme would have delivered, and
// MapViewController.handleDeepLink (AppDelegate.swift) routes it to
// the right tab / web action. The 6 ids below are the contract with
// the web Settings UI: the web posts {id} to the native "addShortcut"
// handler, and SubwayToolsShortcuts exposes the same 6 intents to
// Siri and the Shortcuts app.
//
// Style (26C101, following the user's supplied sample): plain
// AppIntent structs with title / IntentDescription / @Parameter and
// an in-process perform() — NOT OpenURLIntent. The old version used
// OpenURLIntent, which needs iOS 18.0+, so every intent and the
// provider carried a blanket @available(iOS 18.0, *). Plain
// AppIntent only needs iOS 16.0 (the app's deployment target), so
// the gate is gone. Foreground behaviour is declared both ways:
// openAppWhenRun (iOS 16+) and, where the SDK provides it,
// supportedModes = .foreground (iOS 26+; the property is
// availability-scoped so the file still compiles for a 16.0 target).

// The 6 shortcut ids (do not change — the web side posts these exact
// strings to the "addShortcut" message handler).
enum SubwayShortcutID: String, CaseIterable {
    case openApp
    case firstTrain
    case lastTrain
    case planRoute
    case nearestStation
    case timetable

    /// A fresh instance of the AppIntent for this shortcut, used for
    /// donation from the "addShortcut" handler.
    func makeIntent() -> any AppIntent {
        switch self {
        case .openApp: return OpenSubwayToolsIntent()
        case .firstTrain: return FirstTrainIntent()
        case .lastTrain: return LastTrainIntent()
        case .planRoute: return PlanRouteIntent()
        case .nearestStation: return NearestStationIntent()
        case .timetable: return TimetableIntent()
        }
    }

    /// Display name for the in-app "add to Siri" alert. Matches the
    /// shortTitles in SubwayToolsShortcuts below.
    var displayTitle: String {
        switch self {
        case .openApp: return "打开城轨通"
        case .firstTrain: return "查询首班车"
        case .lastTrain: return "查询末班车"
        case .planRoute: return "规划路线"
        case .nearestStation: return "最近的车站"
        case .timetable: return "查看时刻表"
        }
    }
}

// Builds a subwaymotion:// deep link and delivers it in-process.
// Query values are percent-encoded by URLComponents (station names
// are Chinese). The hosts are fixed ASCII strings, so the fallback
// bare URL cannot fail either.
//
// Delivery mirrors the URL-open path exactly, so both entry points
// converge on MapViewController.handleDeepLink:
// - the running app is notified immediately (NotificationCenter);
// - the URL is also stashed in UserDefaults, and
//   MapViewController consumes the stash on didBecomeActive — this
//   covers a cold start, where perform() can run before the view
//   controller has registered its observer.
enum SubwayDeepLink {
    static let notification = Notification.Name("SubwayToolsDeepLink")
    static let pendingKey = "metro-pending-deeplink"

    static func url(host: String, query: [String: String] = [:]) -> URL {
        var components = URLComponents()
        components.scheme = "subwaymotion"
        components.host = host
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url ?? URL(string: "subwaymotion://\(host)")!
    }

    /// Hand a deep link to the app (called from each intent's
    /// perform()).
    static func open(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: pendingKey)
        NotificationCenter.default.post(name: notification, object: nil, userInfo: ["url": url])
    }

    /// Read and clear the stashed deep link, if any.
    static func consumePending() -> URL? {
        guard let string = UserDefaults.standard.string(forKey: pendingKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        return URL(string: string)
    }
}

struct OpenSubwayToolsIntent: AppIntent {
    static var title: LocalizedStringResource = "打开城轨通"
    static var description = IntentDescription("打开城轨通")

    // 如果需要打开App，设置为 .foreground
    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        SubwayDeepLink.open(SubwayDeepLink.url(host: "open"))
        return .result()
    }
}

struct FirstTrainIntent: AppIntent {
    static var title: LocalizedStringResource = "查询首班车"
    static var description = IntentDescription("查询所选车站的首班车时间")

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground
    static var openAppWhenRun: Bool = true

    // 如果操作需要用户输入，用 @Parameter 定义参数
    @Parameter(title: "车站")
    var station: String?

    func perform() async throws -> some IntentResult {
        var query: [String: String] = [:]
        if let station = station, !station.isEmpty { query["station"] = station }
        SubwayDeepLink.open(SubwayDeepLink.url(host: "first-train", query: query))
        return .result()
    }
}

struct LastTrainIntent: AppIntent {
    static var title: LocalizedStringResource = "查询末班车"
    static var description = IntentDescription("查询所选车站的末班车时间")

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground
    static var openAppWhenRun: Bool = true

    @Parameter(title: "车站")
    var station: String?

    func perform() async throws -> some IntentResult {
        var query: [String: String] = [:]
        if let station = station, !station.isEmpty { query["station"] = station }
        SubwayDeepLink.open(SubwayDeepLink.url(host: "last-train", query: query))
        return .result()
    }
}

struct PlanRouteIntent: AppIntent {
    static var title: LocalizedStringResource = "规划路线"
    static var description = IntentDescription("规划从出发站到到达站的地铁路线")

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground
    static var openAppWhenRun: Bool = true

    @Parameter(title: "出发站")
    var from: String

    @Parameter(title: "到达站")
    var to: String

    func perform() async throws -> some IntentResult {
        let url = SubwayDeepLink.url(host: "route", query: ["from": from, "to": to])
        SubwayDeepLink.open(url)
        return .result()
    }
}

struct NearestStationIntent: AppIntent {
    static var title: LocalizedStringResource = "最近的车站"
    static var description = IntentDescription("查找离你最近的地铁站")

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        SubwayDeepLink.open(SubwayDeepLink.url(host: "nearby"))
        return .result()
    }
}

struct TimetableIntent: AppIntent {
    static var title: LocalizedStringResource = "查看时刻表"
    static var description = IntentDescription("查看线路时刻表")

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground
    static var openAppWhenRun: Bool = true

    @Parameter(title: "线路")
    var line: String?

    func perform() async throws -> some IntentResult {
        var query: [String: String] = [:]
        if let line = line, !line.isEmpty { query["line"] = line }
        SubwayDeepLink.open(SubwayDeepLink.url(host: "timetable", query: query))
        return .result()
    }
}

// Exposes the 6 intents to Siri and the Shortcuts app. No donation is
// needed for these to appear: AppShortcutsProvider entries are listed
// under the app in the Shortcuts app automatically.
struct SubwayToolsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSubwayToolsIntent(),
            phrases: ["打开 \(.applicationName)", "打开城轨通", "打开地铁工具"],
            shortTitle: "打开城轨通",
            systemImageName: "app"
        )
        AppShortcut(
            intent: FirstTrainIntent(),
            phrases: ["\(.applicationName)首班车几点", "首班车几点", "查询首班车", "首班车时间"],
            shortTitle: "查询首班车",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: LastTrainIntent(),
            phrases: ["\(.applicationName)末班车几点", "末班车几点", "查询末班车", "末班车时间"],
            shortTitle: "查询末班车",
            systemImageName: "clock.fill"
        )
        AppShortcut(
            intent: PlanRouteIntent(),
            phrases: ["用 \(.applicationName) 规划路线", "规划路线", "规划地铁路线"],
            shortTitle: "规划路线",
            systemImageName: "arrow.triangle.2.circlepath"
        )
        AppShortcut(
            intent: NearestStationIntent(),
            phrases: ["\(.applicationName)最近的地铁站", "最近的地铁站", "离我最近的地铁站", "最近的车站"],
            shortTitle: "最近的车站",
            systemImageName: "location"
        )
        AppShortcut(
            intent: TimetableIntent(),
            phrases: ["\(.applicationName)查看时刻表", "查看时刻表", "时刻表"],
            shortTitle: "查看时刻表",
            systemImageName: "calendar"
        )
    }
}
