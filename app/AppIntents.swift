import AppIntents
import CoreLocation
import Foundation

// Subway tools — Siri Shortcuts via App Intents (user 2026-11-18,
// "在设置里面加入Siri快捷指令功能").
//
// This is the iPhone's own Siri / Shortcuts app integration. There is
// NO in-app AI search box or voice parser here.
//
// 26E113 REWRITE — why the shortcuts were all dead, and what changed.
// Root cause (found 2026-11-22 by unzipping the shipped 26E112 IPA):
// the intents were compiled in (the binary carries every intent type)
// and appintentsmetadataprocessor produced a COMPLETE
// extract.actionsdata (all 6 actions, phrases, provider) — but
// build.sh passed --output "<App>.app/Metadata.appintents" and the
// processor treats --output as a PARENT directory, so the bundle
// shipped Metadata.appintents/Metadata.appintents/extract.actionsdata,
// one level deeper than the path iOS reads
// (<App>.app/Metadata.appintents/extract.actionsdata). The
// AppShortcutsProvider therefore never registered: the Shortcuts app
// listed no actions for this app, and every Settings Siri row led to
// a donation + an alert describing steps that could not work.
// build.sh now flattens the layout and FAILS THE BUILD if the
// canonical files or any intent are missing.
//
// Behaviour (26E113): the query intents (FirstTrain / LastTrain /
// Timetable / NearestStation) now ANSWER IN PLACE from the app's own
// data — perform() reads the bundled copies of the very same
// web/timetable/*.json and web/latlng/*.json files the web pages use
// (build.sh step 3b copies them verbatim and generates a small
// lines/stations index from the same routes/stations sources; no
// second hand-copied dataset) and returns the answer as the intent's
// dialog, without opening the app and without any web search.
// PlanRoute keeps the deep-link form: the routing engine lives in
// the web layer, so the intent opens the app with from/to applied
// and the search run (MapViewController.handleDeepLink, host
// "route": setNativeQuery x2 + doSearch when both are present).
// OpenSubwayTools just opens the app.
//
// The 6 shortcut ids below are the contract with the web Settings
// UI: the web posts {id} to the native "addShortcut" handler, and
// SubwayToolsShortcuts exposes the same 6 intents to Siri and the
// Shortcuts app.
//
// Style (26C101, following the user's supplied sample): plain
// AppIntent structs with title / IntentDescription / @Parameter and
// an in-process perform() — NOT OpenURLIntent (which needs iOS
// 18.0+). Plain AppIntent only needs iOS 16.0 (the app's deployment
// target), so there is no version gate: on iOS 16/17 the intents run
// the same way; openAppWhenRun (iOS 16+) and, where the SDK provides
// it, supportedModes (iOS 26+; availability-scoped) declare the
// foreground/background behaviour.

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

    /// Display name for the in-app "add to Siri" flow. Matches the
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

// MARK: - Bundled timetable / lat-lng data (single source: web/)

/// Reads the bundled copies of web/timetable/*.json (the same files
/// the web timetable page inlines), web/latlng/latlng-*.json, and the
/// build-generated timetable/index.json (city names, line display
/// names and station lists derived by build.sh from the same
/// routes.json / stations.json sources). Loaded lazily, once, per
/// process. A city whose timetable file is absent or empty simply
/// has no entries — answers then say so instead of inventing times.
enum SubwayTimetable {
    struct DirEntry {
        let dir: String
        let first: String?
        let last: String?
    }

    static let cityOrder = ["bj", "sy", "sh", "hb", "dl", "jh", "cz", "cq", "cc", "sz", "cd", "qd", "sjz", "tj", "wx", "ly"]
    private static var loaded = false
    private static var cityNames: [String: String] = [:]
    private static var lineNames: [String: [String: String]] = [:]
    private static var cityStations: [String: [String]] = [:]
    private static var timetables: [String: [String: [String: [DirEntry]]]] = [:]
    private static var coords: [(city: String, station: String, lat: Double, lng: Double)] = []

    static func load() {
        guard !loaded else { return }
        loaded = true
        if let url = Bundle.main.url(forResource: "index", withExtension: "json", subdirectory: "timetable"),
           let data = try? Data(contentsOf: url),
           let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for (city, raw) in root {
                guard let entry = raw as? [String: Any] else { continue }
                cityNames[city] = entry["name"] as? String ?? city
                lineNames[city] = (entry["lines"] as? [String: String]) ?? [:]
                cityStations[city] = (entry["stations"] as? [String]) ?? []
            }
        }
        for city in cityOrder {
            if let url = Bundle.main.url(forResource: city, withExtension: "json", subdirectory: "timetable"),
               let data = try? Data(contentsOf: url),
               let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                var stations: [String: [String: [DirEntry]]] = [:]
                for (station, rawLines) in root {
                    guard let lines = rawLines as? [String: Any] else { continue }
                    var byLine: [String: [DirEntry]] = [:]
                    for (lineKey, rawDirs) in lines {
                        guard let dirs = rawDirs as? [[String: Any]] else { continue }
                        byLine[lineKey] = dirs.map { d in
                            DirEntry(dir: (d["dir"] as? String) ?? "",
                                     first: d["first"] as? String,
                                     last: d["last"] as? String)
                        }
                    }
                    stations[station] = byLine
                }
                if !stations.isEmpty { timetables[city] = stations }
            }
            if let url = Bundle.main.url(forResource: "latlng-\(city)", withExtension: "json", subdirectory: "latlng"),
               let data = try? Data(contentsOf: url),
               let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                for (station, raw) in root {
                    if let pair = raw as? [NSNumber], pair.count == 2 {
                        coords.append((city: city, station: station, lat: pair[0].doubleValue, lng: pair[1].doubleValue))
                    }
                }
            }
        }
    }

    static func currentCity() -> String {
        let saved = UserDefaults.standard.string(forKey: "metro-city") ?? "bj"
        return cityOrder.contains(saved) ? saved : "bj"
    }

    static func cityName(_ city: String) -> String { cityNames[city] ?? city }

    static func lineName(city: String, key: String) -> String {
        lineNames[city]?[key] ?? key
    }

    /// Line keys in display order: numeric keys ascending first,
    /// then the rest alphabetically (JSON object order is not kept).
    static func sortedLineKeys(_ keys: [String]) -> [String] {
        keys.sorted { a, b in
            switch (Int(a), Int(b)) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a < b
            }
        }
    }

    /// Name variants to try for a spoken/typed station name: as
    /// given, and without a trailing 站 (users say "西局站"; the data
    /// keys are "西局").
    static func candidates(_ name: String) -> [String] {
        var out = [name]
        if name.hasSuffix("站"), name.count > 1 {
            out.append(String(name.dropLast()))
        }
        return out
    }

    // MARK: Station query — first/last per line and direction

    static func stationAnswer(_ rawName: String) -> String {
        load()
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "请告诉我要查询的车站名称。" }
        let cur = currentCity()
        let ordered = [cur] + cityOrder.filter { $0 != cur }
        var matches: [(city: String, station: String)] = []
        for city in ordered {
            guard let tt = timetables[city] else { continue }
            for cand in candidates(name) where tt[cand] != nil {
                matches.append((city: city, station: cand))
                break
            }
        }
        if matches.isEmpty {
            // A real station of the 13 cities, but with no timetable
            // rows (its city has no data yet, or the station itself
            // is one of the known gaps — e.g. Qingdao Line 6 middle
            // stations): say so plainly, never invent times.
            for city in cityOrder {
                let list = cityStations[city] ?? []
                if candidates(name).contains(where: { list.contains($0) }) {
                    return "「\(name)」是\(cityName(city))的车站，这个站的时刻表数据暂时还没有，查不到首末班车。"
                }
            }
            return "没有找到「\(name)」这个车站，请确认站名后再试一次。"
        }
        let sections = matches.map {
            sectionText(city: $0.city, station: $0.station, noteCity: matches.count > 1 || $0.city != cur)
        }
        return sections.joined(separator: " ")
    }

    private static func sectionText(city: String, station: String, noteCity: Bool) -> String {
        let lines = timetables[city]?[station] ?? [:]
        var parts: [String] = []
        for key in sortedLineKeys(Array(lines.keys)) {
            for d in lines[key] ?? [] {
                if let f = d.first, let l = d.last {
                    parts.append("\(lineName(city: city, key: key))往\(d.dir)方向，首班车\(f)，末班车\(l)")
                } else if let l = d.last {
                    parts.append("\(lineName(city: city, key: key))往\(d.dir)方向，末班车\(l)（首班时间暂无记录）")
                } else if let f = d.first {
                    parts.append("\(lineName(city: city, key: key))往\(d.dir)方向，首班车\(f)")
                }
                // Both null = that direction does not run from this
                // station (the outward direction at a terminus) —
                // skipped, exactly as the web timetable page shows.
            }
        }
        let head = noteCity ? "\(cityName(city)) · \(station)站：" : "\(station)站："
        if parts.isEmpty {
            return head + "这个站的时刻表数据暂时还没有。"
        }
        return head + parts.joined(separator: "；") + "。"
    }

    // MARK: Line query — first/last from the line's termini

    /// TimetableIntent entry point: the parameter accepts a line
    /// ("1号线" / "大兴机场线" / "1") or a station name. A line match
    /// (current city first, then the other 12) wins; otherwise the
    /// text is treated as a station query.
    static func lineOrStationAnswer(_ raw: String) -> String {
        load()
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return "请告诉我要查询的线路或车站名称。" }
        let cur = currentCity()
        for city in [cur] + cityOrder.filter({ $0 != cur }) {
            if let key = matchLineKey(city: city, query: q) {
                return lineSummary(city: city, key: key)
            }
        }
        return stationAnswer(q)
    }

    private static func matchLineKey(city: String, query: String) -> String? {
        let names = lineNames[city] ?? [:]
        for (key, name) in names where name == query || key == query {
            return key
        }
        if query.hasSuffix("号线") {
            let bare = String(query.dropLast(2))
            if names[bare] != nil { return bare }
        }
        return nil
    }

    private static func lineSummary(city: String, key: String) -> String {
        let name = lineName(city: city, key: key)
        guard let tt = timetables[city], !tt.isEmpty else {
            return "\(cityName(city))的时刻表正在整理，暂时还查不到\(name)的首末班车。"
        }
        // Termini = the direction targets used by this line.
        var termini: [String] = []
        for (_, lines) in tt {
            for d in lines[key] ?? [] where !termini.contains(d.dir) {
                termini.append(d.dir)
            }
        }
        var parts: [String] = []
        if !termini.isEmpty, termini.allSatisfy({ $0 == "内环" || $0 == "外环" }) {
            // Loop line: report one real station's two directions.
            let sample = tt.keys.filter { tt[$0]?[key] != nil }.sorted().first
            if let s = sample {
                for d in tt[s]?[key] ?? [] {
                    if let f = d.first, let l = d.last {
                        parts.append("\(d.dir)方向，首班车\(f)，末班车\(l)")
                    }
                }
                if !parts.isEmpty {
                    return "\(cityName(city))\(name)（环线），以\(s)站为例：" + parts.joined(separator: "；") + "。"
                }
            }
        }
        for t in termini.sorted() {
            for d in tt[t]?[key] ?? [] {
                if let f = d.first, let l = d.last {
                    parts.append("从\(t)站开往\(d.dir)方向，首班车\(f)，末班车\(l)")
                } else if let l = d.last {
                    parts.append("从\(t)站开往\(d.dir)方向，末班车\(l)（首班时间暂无记录）")
                }
            }
        }
        if parts.isEmpty {
            return "\(cityName(city))\(name)的时刻表数据暂时还没有。"
        }
        return "\(cityName(city))\(name)首末班车：" + parts.joined(separator: "；") + "。"
    }

    // MARK: Nearest station (lat/lng, same data as the web 附近车站）

    static func nearestAnswer(location: CLLocation) -> String {
        load()
        var best: (city: String, station: String, distance: CLLocationDistance)?
        for c in coords {
            let d = location.distance(from: CLLocation(latitude: c.lat, longitude: c.lng))
            if best == nil || d < best!.distance {
                best = (city: c.city, station: c.station, distance: d)
            }
        }
        guard let b = best else {
            return "暂时查不到附近的车站，请打开城轨通查看附近车站。"
        }
        let distText: String
        if b.distance < 1000 {
            distText = "约\(Int((b.distance / 10).rounded() * 10))米"
        } else {
            distText = String(format: "约%.1f公里", b.distance / 1000)
        }
        return "离你最近的车站是\(cityName(b.city))的\(b.station)站，\(distText)。"
    }
}

// MARK: - One-shot location for NearestStationIntent

/// CLLocationManager one-shot fetch with a 12 s timeout. All manager
/// interaction happens on the main queue (its delegate callbacks are
/// delivered there). The static `active` box keeps the instance
/// alive until the continuation resumes.
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private let lock = NSLock()
    private static var active: OneShotLocation?

    static var authorizationStatus: CLAuthorizationStatus {
        CLLocationManager().authorizationStatus
    }

    static func fetch() async -> CLLocation? {
        let box = OneShotLocation()
        active = box
        return await withCheckedContinuation { cont in
            box.begin(cont)
        }
    }

    private func begin(_ cont: CheckedContinuation<CLLocation?, Never>) {
        continuation = cont
        DispatchQueue.main.async { [self] in
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            manager.requestLocation()
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            self?.finish(nil)
        }
    }

    private func finish(_ location: CLLocation?) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        OneShotLocation.active = nil
        cont?.resume(returning: location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            finish(nil)
        }
    }
}

// MARK: - Intents

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
    static var description = IntentDescription("用城轨通内置时刻表数据，直接报出所查车站各条线路、各方向的首班车和末班车时间")

    // 直接在 Siri 里回答，不打开 App。
    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .background
    static var openAppWhenRun: Bool = false

    // 如果操作需要用户输入，用 @Parameter 定义参数
    @Parameter(title: "车站")
    var station: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = SubwayTimetable.stationAnswer(station)
        return .result(value: text, dialog: IntentDialog("\(text)"))
    }
}

struct LastTrainIntent: AppIntent {
    static var title: LocalizedStringResource = "查询末班车"
    static var description = IntentDescription("用城轨通内置时刻表数据，直接报出所查车站各条线路、各方向的首班车和末班车时间")

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .background
    static var openAppWhenRun: Bool = false

    @Parameter(title: "车站")
    var station: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = SubwayTimetable.stationAnswer(station)
        return .result(value: text, dialog: IntentDialog("\(text)"))
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
        // The routing engine lives in the web layer; the deep link
        // lands on the transfer tab with both stations applied and
        // the search already run (handleDeepLink, host "route").
        let url = SubwayDeepLink.url(host: "route", query: ["from": from, "to": to])
        SubwayDeepLink.open(url)
        return .result()
    }
}

struct NearestStationIntent: AppIntent {
    static var title: LocalizedStringResource = "最近的车站"
    static var description = IntentDescription("用定位和城轨通内置的车站坐标，直接报出离你最近的车站和距离")

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .background
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text: String
        let status = OneShotLocation.authorizationStatus
        if status == .denied || status == .restricted {
            text = "定位权限未开启，查不到最近的车站。请在系统设置里允许城轨通使用定位，或打开城轨通查看附近车站。"
        } else if let location = await OneShotLocation.fetch() {
            text = SubwayTimetable.nearestAnswer(location: location)
        } else {
            text = "暂时取不到当前位置，查不到最近的车站。请打开城轨通查看附近车站。"
        }
        return .result(value: text, dialog: IntentDialog("\(text)"))
    }
}

struct TimetableIntent: AppIntent {
    static var title: LocalizedStringResource = "查看时刻表"
    static var description = IntentDescription("用城轨通内置时刻表数据，直接报出一条线路的首末班车，或一个车站各方向的首末班车")

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .background
    static var openAppWhenRun: Bool = false

    @Parameter(title: "线路或车站")
    var query: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = SubwayTimetable.lineOrStationAnswer(query)
        return .result(value: text, dialog: IntentDialog("\(text)"))
    }
}

// Exposes the 6 intents to Siri and the Shortcuts app. No donation is
// needed for these to appear: AppShortcutsProvider entries are listed
// under the app in the Shortcuts app automatically (which is why the
// Metadata.appintents layout fixed in build.sh 26E113 matters —
// without registration at the canonical path, none of this exists
// on device).
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
            phrases: ["\(.applicationName)首班车几点", "查询车站首班车时间", "首班车几点", "查询首班车", "首班车时间"],
            shortTitle: "查询首班车",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: LastTrainIntent(),
            phrases: ["\(.applicationName)末班车几点", "查询车站末班车时间", "用 \(.applicationName) 查询车站末班车时间", "末班车几点", "查询末班车", "末班车时间"],
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
            phrases: ["\(.applicationName)查看时刻表", "查询车站首末班车时间", "查看时刻表", "时刻表"],
            shortTitle: "查看时刻表",
            systemImageName: "calendar"
        )
    }
}
