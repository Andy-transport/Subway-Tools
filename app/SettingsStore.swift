import Foundation
import Combine
import UIKit
import CoreLocation

// MARK: - Native Settings state (Settings tab, SDK 27.2 Apple UI)
//
// Single source of truth (evidence, all in this copy):
//  * city / theme / language live in UserDefaults — AppDelegate.swift
//    ~896-904: "UserDefaults is now the single source of truth" (the
//    web's file:// localStorage did not survive on the user's device,
//    so the native side injects _metroInitCity/_metroInitTheme/
//    _metroInitDark at document start and the web prefers them).
//  * Theme: applyAppearanceTheme (AppDelegate ~1749) writes
//    metro-theme + metro-dark to UserDefaults FIRST, then calls the
//    web's setTheme(). The web's themeState post only re-persists.
//  * City: pickCity (AppDelegate ~2117) writes metro-city to
//    UserDefaults FIRST, then calls the web's switchCity().
//  * Language is the one asymmetric case, by design (AppDelegate
//    ~1742 comment): applyLanguageChoice does NOT persist natively —
//    it calls the web's setLang(), the web posts langChanged, and
//    native setLang() (~795) persists metro-lang / metro-lang-explicit.
//    This store preserves that exact flow: setLanguage() only calls
//    the web, and refreshFromNative() picks up the persisted result.
//  * nearbySmart lives ONLY in the web (Vue + localStorage
//    'metro-nearby-smart', default on, template.html ~3238/~5435).
//    There is no UserDefaults key for it. The native Siri page reads
//    it through the web and writes it through window.__setNearbySmart,
//    which is the web's own setter (template.html ~7105).
//  * Beijing map type lives ONLY in the web (localStorage
//    'metro-bj-maptype', default 'track', template.html ~3250).
//    The native City page mirrors it in UserDefaults under the same
//    key name AND writes the web's localStorage + pickBjMapType()
//    through JS, so the two can never drift apart.
//  * Profile lives ONLY in the web (localStorage 'metro-profile',
//    {name, avatar, id, since}, template.html ~3260s). The native
//    Profile page owns it in UserDefaults under the same key name
//    (it survives, unlike file:// localStorage) and mirrors every
//    save/logout back into the web's localStorage. On first use it
//    migrates any profile already saved by the web.

enum SettingsLanguage: String, CaseIterable {
    case system
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case english = "en"

    /// Index into the web I18N triples (0 = zh-Hans, 1 = zh-Hant, 2 = en).
    var i18nIndex: Int {
        switch self {
        case .zhHans, .system: return 0 // resolved by effectiveLanguage
        case .zhHant: return 1
        case .english: return 2
        }
    }

    static func systemLanguage() -> SettingsLanguage {
        switch MapViewController.systemLang() {
        case "zh-Hant": return .zhHant
        case "en": return .english
        default: return .zhHans
        }
    }
}

/// The narrow bridge the native Settings pages use to reach the
/// MapViewController (city/theme/language application, Siri, location,
/// cache, external URLs, JS evaluation). Implemented by
/// MapViewController in SettingsHosting.swift so the store never
/// retains the controller and never touches the web view directly.
protocol SettingsBridge: AnyObject {
    var settingsCurrentCity: String { get }
    func settingsPickCity(_ key: String)
    /// Called after a city switch: the web lands on the transfer tab
    /// (web onCityRowTap), so the native Settings page closes too.
    func settingsCitySwitched()
    var settingsThemePref: String { get }
    func settingsApplyTheme(_ key: String)
    var settingsLangPref: String { get }
    func settingsApplyLanguage(_ key: String)
    func settingsEvaluateJS(_ js: String, completion: ((Any?) -> Void)?)
    func settingsPresentShortcut(_ id: String)
    func settingsRequestLocationPermission()
    func settingsClearCache()
    func settingsOpenExternal(_ url: URL, fallback: URL?)
}

struct UserProfile: Codable, Equatable {
    var name: String
    var avatar: String // JPEG data URI (<=256px, q0.85 on white), "" = none
    var id: String     // "CT" + 10 digits, minted at first save
    var since: String  // yyyy-MM-dd of first save

    var initial: String { name.isEmpty ? "" : String(name.prefix(1)) }
}

final class SettingsStore: ObservableObject {
    weak var bridge: SettingsBridge?

    // Published state — the single values the whole native Settings UI reads.
    @Published var city: String = "bj"
    @Published var langPref: String = "system"
    @Published var theme: String = "system"
    @Published var nearbySmart: Bool = true
    @Published var bjMapType: String = "track"
    @Published var profile: UserProfile?
    @Published var cacheCleared: Bool = false
    @Published var showFullVersion: Bool = false

    /// Effective language for strings (Follow System resolves to the iOS language).
    var effectiveLanguage: SettingsLanguage {
        if langPref == "system" { return SettingsLanguage.systemLanguage() }
        return SettingsLanguage(rawValue: langPref) ?? .zhHans
    }

    /// Name of the iOS system language, for the 跟随系统 row
    /// (mirrors the web's langDisplayName for the system language).
    func systemLangDisplayName() -> String {
        switch SettingsLanguage.systemLanguage() {
        case .zhHant: return t("more.lang.hant")
        case .english: return t("more.lang.en")
        default: return t("more.lang.hans")
        }
    }

    var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? SettingsData.formalShortVersion
    }
    var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? SettingsData.formalBuild
    }

    func t(_ key: String, vars: [String: String] = [:]) -> String {
        SettingsStrings.t(key, lang: effectiveLanguage, vars: vars)
    }

    init() {
        reloadFromDefaults()
    }

    // MARK: - Load / refresh

    /// Read the UserDefaults-owned values (city/theme/language). Called
    /// at init and after the native side persists a language change.
    func reloadFromDefaults() {
        let d = UserDefaults.standard
        if let c = d.string(forKey: "metro-city"), SettingsData.cities.contains(where: { $0.key == c }) {
            city = c
        }
        if let th = d.string(forKey: "metro-theme"), ["system", "light", "dark"].contains(th) {
            theme = th
        }
        // Language: only an explicit choice is stored (metro-lang-explicit).
        if d.bool(forKey: "metro-lang-explicit"), let l = d.string(forKey: "metro-lang") {
            langPref = l
        } else {
            langPref = "system"
        }
        if let m = d.string(forKey: "metro-bj-maptype"), ["track", "line"].contains(m) {
            bjMapType = m
        }
        if let data = d.data(forKey: "metro-profile"),
           let p = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = p
        }
    }

    /// Pull the web-only values (nearbySmart, bjMapType, profile
    /// migration) from the running web page. No-ops gracefully when the
    /// web is not ready yet — the UserDefaults values above stand.
    func refreshFromWeb() {
        bridge?.settingsEvaluateJS("window.metroApp ? window.metroApp.nearbySmart : null") { [weak self] result in
            if let v = result as? Bool { DispatchQueue.main.async { self?.nearbySmart = v } }
        }
        bridge?.settingsEvaluateJS("window.metroApp ? window.metroApp.bjMapType : null") { [weak self] result in
            if let v = result as? String, ["track", "line"].contains(v) {
                DispatchQueue.main.async {
                    self?.bjMapType = v
                    UserDefaults.standard.set(v, forKey: "metro-bj-maptype")
                }
            }
        }
        // One-time profile migration: if native has no profile yet, adopt
        // whatever the web already saved (then native owns it from here on).
        if profile == nil {
            bridge?.settingsEvaluateJS("try{window.localStorage.getItem('metro-profile')}catch(e){null}") { [weak self] result in
                guard let s = result as? String, let data = s.data(using: .utf8),
                      let p = try? JSONDecoder().decode(UserProfile.self, from: data) else { return }
                DispatchQueue.main.async {
                    self?.profile = p
                    self?.saveProfileToDefaults(p)
                }
            }
        }
    }

    /// Called after native setLang() persists a language change
    /// (web langChanged post). AppDelegate.applyLanguage() also calls
    /// reloadFromDefaults() on the store, so SwiftUI re-renders in the
    /// new language; this is just the store-side half of that.
    func refreshFromNative() {
        reloadFromDefaults()
    }

    // MARK: - Actions (each preserves the existing sync flow)

    func setCity(_ key: String) {
        guard SettingsData.cities.contains(where: { $0.key == key }) else { return }
        city = key
        bridge?.settingsPickCity(key) // writes metro-city, then web switchCity()
        bridge?.settingsCitySwitched() // web lands on the transfer tab -> close Settings
    }

    func setTheme(_ key: String) {
        guard ["system", "light", "dark"].contains(key) else { return }
        theme = key
        bridge?.settingsApplyTheme(key) // writes metro-theme/metro-dark, then web setTheme()
    }

    func setLanguage(_ key: String) {
        guard ["system", "zh-Hans", "zh-Hant", "en"].contains(key) else { return }
        langPref = key
        bridge?.settingsApplyLanguage(key) // web setLang() -> langChanged -> native persists
    }

    func setNearbySmart(_ on: Bool) {
        nearbySmart = on
        // The web owns this value; __setNearbySmart calls its setNearbySmart(),
        // which writes localStorage 'metro-nearby-smart'.
        bridge?.settingsEvaluateJS("window.__setNearbySmart && window.__setNearbySmart(\(on))", completion: nil)
    }

    func setBjMapType(_ type: String) {
        let t = (type == "line") ? "line" : "track"
        bjMapType = t
        UserDefaults.standard.set(t, forKey: "metro-bj-maptype")
        // Write the web's localStorage too, then run its picker so an
        // already-Beijing map re-applies at once (web pickBjMapType).
        bridge?.settingsEvaluateJS(
            "try{window.localStorage.setItem('metro-bj-maptype','\(t)')}catch(e){};" +
            "window.metroApp && window.metroApp.pickBjMapType && window.metroApp.pickBjMapType('\(t)')",
            completion: nil)
    }

    // MARK: - Profile (local only, no server)

    func saveProfile(name: String, avatarDataURI: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = cleanName.isEmpty ? t("profile.defaultName") : cleanName
        let id = profile?.id ?? genAppUid()
        let since = profile?.since ?? fmtDate(Date())
        let p = UserProfile(name: finalName, avatar: avatarDataURI, id: id, since: since)
        profile = p
        saveProfileToDefaults(p)
        // Mirror into the web's localStorage so the two stores agree.
        if let data = try? JSONEncoder().encode(p), let json = String(data: data, encoding: .utf8) {
            let escaped = json.replacingOccurrences(of: "'", with: "\\'")
            bridge?.settingsEvaluateJS("try{window.localStorage.setItem('metro-profile','\(escaped)')}catch(e){}", completion: nil)
        }
    }

    func logoutProfile() {
        profile = nil
        UserDefaults.standard.removeObject(forKey: "metro-profile")
        bridge?.settingsEvaluateJS("try{window.localStorage.removeItem('metro-profile')}catch(e){}", completion: nil)
    }

    private func saveProfileToDefaults(_ p: UserProfile) {
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: "metro-profile")
        }
    }

    private func genAppUid() -> String {
        // Same scheme as the web (template.html genAppUid): "CT" + 10 digits.
        var s = "CT"
        for _ in 0..<10 { s += String(Int.random(in: 0...9)) }
        return s
    }

    private func fmtDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - Location / Siri / cache / links

    var locationStatus: CLAuthorizationStatus { CLLocationManager.authorizationStatus() }

    func locationStatusText() -> String {
        switch locationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return t("more.loc.granted")
        case .denied: return t("more.loc.denied")
        case .restricted: return t("more.loc.restricted")
        default: return t("more.loc.unknown")
        }
    }

    func requestLocation() {
        bridge?.settingsRequestLocationPermission()
    }

    func addShortcut(_ id: String) {
        bridge?.settingsPresentShortcut(id)
    }

    func clearCache() {
        bridge?.settingsClearCache()
        // Native briefing/trains caches live in UserDefaults too; clear them.
        UserDefaults.standard.removeObject(forKey: "metro-briefing")
        UserDefaults.standard.removeObject(forKey: "metro-trains")
        cacheCleared = true
    }

    func openRepo() {
        bridge?.settingsOpenExternal(URL(string: "https://github.com/Andy-transport/Subway-Tools")!, fallback: nil)
    }

    func openDouyin(userID: String) {
        // Same mechanism as the web (template.html openDouyin*): try the
        // Douyin app scheme, fall back to the web search page.
        let appURL = URL(string: "snssdk1128://user/profile/\(userID)")
        let webURL = URL(string: "https://www.douyin.com/search/\(userID)")
        if let appURL = appURL, UIApplication.shared.canOpenURL(appURL) {
            bridge?.settingsOpenExternal(appURL, fallback: webURL)
        } else if let webURL = webURL {
            bridge?.settingsOpenExternal(webURL, fallback: nil)
        }
    }

    // MARK: - Web station list (for the Structure page)

    struct WebStation: Decodable, Hashable { let n: String; let py: String; let ini: String }

    /// Station names for the current city, read from the running web page
    /// (same source the web's own structure search uses). Falls back to
    /// the structure-index station names when the web is not ready.
    func fetchWebStations(completion: @escaping ([WebStation]) -> Void) {
        bridge?.settingsEvaluateJS(
            "JSON.stringify((window.metroApp && window.metroApp.stations ? window.metroApp.stations : []).map(function(s){return {n:s.n,py:(s.py||''),ini:(s.ini||'')}}))") { result in
            guard let s = result as? String, let data = s.data(using: .utf8),
                  let list = try? JSONDecoder().decode([WebStation].self, from: data), !list.isEmpty else {
                completion([])
                return
            }
            completion(list)
        }
        if bridge == nil { completion([]) }
    }
}

// MARK: - Briefing / trains / structure seed stores
//
// Seeds are the verbatim JSON embedded in SettingsSeedData.swift (the
// JSON files themselves are not bundle resources — build.sh copies only
// web/offline/index.html). Online refresh uses the same URLs as the web
// (raw.githubusercontent.com/Andy-transport/Subway-Tools/main/web/...)
// and caches under the same key names the web uses in localStorage,
// but in UserDefaults (the native store).

struct BriefingItem: Decodable, Identifiable, Hashable {
    let id: String
    let city: String?
    let color: String
    let date: String
    let date_en: String?
    let source: String?
    let source_en: String?
    let title: String
    let title_en: String?
    let summary: String
    let summary_en: String?
    func text(_ zh: String, _ en: String?, lang: SettingsLanguage) -> String {
        lang == .english ? (en ?? zh) : zh
    }
}

struct BriefingSeed: Decodable { let items: [BriefingItem]; let updated: String? }

final class BriefingStore: ObservableObject {
    @Published var items: [BriefingItem] = []
    @Published var updated: String = ""
    private let refreshURL = URL(string: "https://raw.githubusercontent.com/Andy-transport/Subway-Tools/main/web/briefing.json")!

    init() {
        loadSeed()
        if let data = UserDefaults.standard.data(forKey: "metro-briefing"),
           let seed = try? JSONDecoder().decode(BriefingSeed.self, from: data), !seed.items.isEmpty {
            items = seed.items
            updated = seed.updated ?? updated
        }
    }

    func loadSeed() {
        guard let data = SettingsSeedData.briefingJSON.data(using: .utf8),
              let seed = try? JSONDecoder().decode(BriefingSeed.self, from: data) else { return }
        if items.isEmpty { items = seed.items }
        if updated.isEmpty { updated = seed.updated ?? "" }
    }

    func items(for cityKey: String) -> [BriefingItem] {
        items.filter { (($0.city ?? String(($0.id).prefix(2))).lowercased() == cityKey) }
    }

    /// Same refresh as the web (template.html refreshBriefing): fetch,
    /// replace, cache. Offline keeps the seed/cached copy.
    func refresh() {
        URLSession.shared.dataTask(with: refreshURL) { [weak self] data, response, _ in
            guard let data = data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let seed = try? JSONDecoder().decode(BriefingSeed.self, from: data), !seed.items.isEmpty else { return }
            DispatchQueue.main.async {
                self?.items = seed.items
                self?.updated = seed.updated ?? ""
                UserDefaults.standard.set(data, forKey: "metro-briefing")
            }
        }.resume()
    }
}

struct TrainEntry: Decodable, Hashable {
    let model: String; let maker: String; let line: String; let spec: String?
}
struct TrainCity: Decodable, Hashable {
    let key: String; let name: String; let name_en: String?; let trains: [TrainEntry]
}
struct TrainsSeed: Decodable { let cities: [TrainCity]; let updated: String?; let source: String? }

final class TrainsStore: ObservableObject {
    @Published var cities: [TrainCity] = []
    @Published var updated: String = ""
    private let refreshURL = URL(string: "https://raw.githubusercontent.com/Andy-transport/Subway-Tools/main/web/trains.json")!

    init() {
        loadSeed()
        if let data = UserDefaults.standard.data(forKey: "metro-trains"),
           let seed = try? JSONDecoder().decode(TrainsSeed.self, from: data), !seed.cities.isEmpty {
            cities = seed.cities
            updated = seed.updated ?? updated
        }
    }

    func loadSeed() {
        guard let data = SettingsSeedData.trainsJSON.data(using: .utf8),
              let seed = try? JSONDecoder().decode(TrainsSeed.self, from: data) else { return }
        if cities.isEmpty { cities = seed.cities }
        if updated.isEmpty { updated = seed.updated ?? "" }
    }

    /// Same matching as the web (template.html trainResults): strip
    /// 地铁/轨道交通/城市轨道交通 + whitespace, then city-name hit shows
    /// the whole city, city+line narrows by line, else model/maker/line hit.
    func results(for rawQuery: String) -> [(city: TrainCity, trains: [TrainEntry])] {
        var q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return [] }
        q = q.replacingOccurrences(of: "城市轨道交通", with: "").replacingOccurrences(of: "轨道交通", with: "")
            .replacingOccurrences(of: "地铁", with: "").replacingOccurrences(of: " ", with: "")
        if q.isEmpty { return [] }
        var out: [(TrainCity, [TrainEntry])] = []
        for c in cities {
            let cn = c.name.lowercased(), en = (c.name_en ?? "").lowercased()
            let cityHit = (!cn.isEmpty && cn.contains(q)) || (!en.isEmpty && en.contains(q))
            var trains: [TrainEntry] = []
            if cityHit {
                trains = c.trains
            } else if (!cn.isEmpty && q.contains(cn)) || (!en.isEmpty && q.contains(en)) {
                var rest = q
                if !cn.isEmpty { rest = rest.replacingOccurrences(of: cn, with: "") }
                if !en.isEmpty { rest = rest.replacingOccurrences(of: en, with: "") }
                trains = c.trains.filter { lineMatches(rest, line: $0.line) }
            } else {
                trains = c.trains.filter {
                    (($0.model + " " + $0.maker + " " + $0.line).lowercased().contains(q))
                }
            }
            if !trains.isEmpty { out.append((c, trains)) }
        }
        return out
    }

    private func lineMatches(_ rest: String, line: String) -> Bool {
        // Verbatim web rule (template.html lineMatches): a purely numeric
        // remainder matches only a line whose LEADING number equals it
        // (so "1" does not also match 10/11/12/13/16/17/18/19); otherwise
        // either string containing the other matches.
        let r = rest.lowercased(), l = line.lowercased()
        guard !r.isEmpty, !l.isEmpty else { return false }
        if r.allSatisfy({ $0.isNumber }) {
            let leading = l.prefix(while: { $0.isNumber })
            return !leading.isEmpty && String(leading) == r
        }
        return l.contains(r) || r.contains(l)
    }

    func refresh() {
        URLSession.shared.dataTask(with: refreshURL) { [weak self] data, response, _ in
            guard let data = data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let seed = try? JSONDecoder().decode(TrainsSeed.self, from: data), !seed.cities.isEmpty else { return }
            DispatchQueue.main.async {
                self?.cities = seed.cities
                self?.updated = seed.updated ?? ""
                UserDefaults.standard.set(data, forKey: "metro-trains")
            }
        }.resume()
    }
}

struct StructEntry: Decodable {
    let spatial: String?
    let plan: String?
    let sources: [String: String]?
    let urls: [String: String]?
}

final class StructureStore: ObservableObject {
    @Published var index: [String: StructEntry] = [:]
    @Published var imageCache: [String: UIImage] = [:]
    @Published var loadingKeys: Set<String> = []

    init() {
        guard let data = SettingsSeedData.structureIndexJSON.data(using: .utf8),
              let idx = try? JSONDecoder().decode([String: StructEntry].self, from: data) else { return }
        index = idx
    }

    func entry(city: String, station: String) -> StructEntry? { index["\(city):\(station)"] }

    func stationsWithDiagrams(city: String) -> [String] {
        index.keys.compactMap { k -> String? in
            guard k.hasPrefix(city + ":") else { return nil }
            return String(k.dropFirst(city.count + 1))
        }.sorted()
    }

    /// Fetch a structure image: the jsDelivr URL returns base64 text
    /// (same as the web's loadStructImg), decoded to a UIImage.
    func image(for file: String, url: String, completion: @escaping (UIImage?) -> Void) {
        if let img = imageCache[file] { completion(img); return }
        guard let u = URL(string: url) else { completion(nil); return }
        DispatchQueue.main.async { self.loadingKeys.insert(file) }
        URLSession.shared.dataTask(with: u) { [weak self] data, response, _ in
            DispatchQueue.main.async { self?.loadingKeys.remove(file) }
            guard let data = data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let b64 = text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            guard let raw = Data(base64Encoded: b64), let img = UIImage(data: raw) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async {
                self?.imageCache[file] = img
                completion(img)
            }
        }.resume()
    }
}
