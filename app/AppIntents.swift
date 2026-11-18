import AppIntents
import Foundation

// Subway tools — Siri Shortcuts via App Intents (user 2026-11-18,
// "在设置里面加入Siri快捷指令功能").
//
// This is the iPhone's own Siri / Shortcuts app integration. There is
// NO in-app AI search box or voice parser here: each intent simply
// opens the app at a subwaymotion:// deep link, and
// MapViewController.handleDeepLink (AppDelegate.swift) routes it to
// the right tab / web action. The 6 ids below are the contract with
// the web Settings UI: the web posts {id} to the native "addShortcut"
// handler, and SubwayToolsShortcuts exposes the same 6 intents to Siri
// and the Shortcuts app.
//
// AppIntents is available from iOS 16.0 (the app's deployment target),
// so no availability gating is needed here.

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
}

// Builds a subwaymotion:// deep link. Query values are percent-encoded
// by URLComponents (station names are Chinese). The hosts are fixed
// ASCII strings, so the fallback bare URL cannot fail either.
enum SubwayDeepLink {
    static func url(host: String, query: [String: String] = [:]) -> URL {
        var components = URLComponents()
        components.scheme = "subwaymotion"
        components.host = host
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url ?? URL(string: "subwaymotion://\(host)")!
    }
}

struct OpenSubwayToolsIntent: AppIntent {
    static var title: LocalizedStringResource = "打开 Subway tools"
    static var description = IntentDescription("打开 Subway tools")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        return .result(opensIntent: OpenURLIntent(SubwayDeepLink.url(host: "open")))
    }
}

struct FirstTrainIntent: AppIntent {
    static var title: LocalizedStringResource = "查询首班车"
    static var description = IntentDescription("查询所选车站的首班车时间")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "车站")
    var station: String? = nil

    func perform() async throws -> some IntentResult & OpensIntent {
        var query: [String: String] = [:]
        if let station = station, !station.isEmpty { query["station"] = station }
        return .result(opensIntent: OpenURLIntent(SubwayDeepLink.url(host: "first-train", query: query)))
    }
}

struct LastTrainIntent: AppIntent {
    static var title: LocalizedStringResource = "查询末班车"
    static var description = IntentDescription("查询所选车站的末班车时间")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "车站")
    var station: String? = nil

    func perform() async throws -> some IntentResult & OpensIntent {
        var query: [String: String] = [:]
        if let station = station, !station.isEmpty { query["station"] = station }
        return .result(opensIntent: OpenURLIntent(SubwayDeepLink.url(host: "last-train", query: query)))
    }
}

struct PlanRouteIntent: AppIntent {
    static var title: LocalizedStringResource = "规划路线"
    static var description = IntentDescription("规划从出发站到到达站的地铁路线")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "出发站")
    var from: String

    @Parameter(title: "到达站")
    var to: String

    func perform() async throws -> some IntentResult & OpensIntent {
        let url = SubwayDeepLink.url(host: "route", query: ["from": from, "to": to])
        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct NearestStationIntent: AppIntent {
    static var title: LocalizedStringResource = "最近的车站"
    static var description = IntentDescription("查找离你最近的地铁站")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        return .result(opensIntent: OpenURLIntent(SubwayDeepLink.url(host: "nearby")))
    }
}

struct TimetableIntent: AppIntent {
    static var title: LocalizedStringResource = "查看时刻表"
    static var description = IntentDescription("查看线路时刻表")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "线路")
    var line: String? = nil

    func perform() async throws -> some IntentResult & OpensIntent {
        var query: [String: String] = [:]
        if let line = line, !line.isEmpty { query["line"] = line }
        return .result(opensIntent: OpenURLIntent(SubwayDeepLink.url(host: "timetable", query: query)))
    }
}

// Exposes the 6 intents to Siri and the Shortcuts app. No donation is
// needed for these to appear: AppShortcutsProvider entries are listed
// under Subway tools in the Shortcuts app automatically.
struct SubwayToolsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSubwayToolsIntent(),
            phrases: ["打开 Subway tools", "打开地铁工具"],
            shortTitle: "打开 Subway tools",
            systemImageName: "app"
        )
        AppShortcut(
            intent: FirstTrainIntent(),
            phrases: ["首班车几点", "查询首班车", "首班车时间"],
            shortTitle: "查询首班车",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: LastTrainIntent(),
            phrases: ["末班车几点", "查询末班车", "末班车时间"],
            shortTitle: "查询末班车",
            systemImageName: "clock.fill"
        )
        AppShortcut(
            intent: PlanRouteIntent(),
            phrases: ["规划路线", "规划地铁路线"],
            shortTitle: "规划路线",
            systemImageName: "arrow.triangle.2.circlepath"
        )
        AppShortcut(
            intent: NearestStationIntent(),
            phrases: ["最近的地铁站", "离我最近的地铁站", "最近的车站"],
            shortTitle: "最近的车站",
            systemImageName: "location"
        )
        AppShortcut(
            intent: TimetableIntent(),
            phrases: ["查看时刻表", "时刻表"],
            shortTitle: "查看时刻表",
            systemImageName: "calendar"
        )
    }
}
