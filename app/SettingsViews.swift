import SwiftUI
import PhotosUI
import UIKit

// MARK: - Native Settings pages (SDK 27.2 Apple UI, SwiftUI)
//
// Home row order is the web #moreSheet order, unchanged (template.html
// ~2063-2110): account card first, then ONE fused card with rows in
// this order — 切换城市 → 通用 → 定位 → 功能介绍 → 即将开通 →
// 里程排名 → 轨道交通信息简报 → 车型检索 → 车站结构 → Siri快捷指令 → 关于
// (About last per user order 2026-11-24: 把关于放到卡片最下面).
// No row added, removed, reordered, or reworded in meaning.
// All strings come from SettingsStrings (the web I18N triples, verbatim).
// Logos / line marks are the original artwork only: city logos are the
// bundle <City>Logo.png files build.sh already decodes; the Siri row
// icon is the user's orb (SiriOrb / SiriOrbDark, decoded by build.sh);
// nothing is redrawn. System rows use SF Symbols (generic UI glyphs,
// not logos). Dark/light follows the system + the app's theme choice
// via the hosting controller's overrideUserInterfaceStyle.

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
    /// White or black text on a hex background (same luminance rule as the web's lineTextColor).
    static func textOn(hex: String) -> Color {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let lum = (0.299 * Double((v >> 16) & 0xFF) + 0.587 * Double((v >> 8) & 0xFF) + 0.114 * Double(v & 0xFF)) / 255
        return lum > 0.6 ? .black : .white
    }
}

struct CityLogoImage: View {
    let imageName: String
    var size: CGFloat = 28
    var body: some View {
        if let img = UIImage(named: imageName) {
            Image(uiImage: img)
                .resizable().scaledToFit().frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle().fill(Color.secondary.opacity(0.25))
                .frame(width: size, height: size)
                .overlay(Text("M").font(.system(size: size * 0.45, weight: .semibold)).foregroundColor(.secondary))
        }
    }
}

struct SiriOrbImage: View {
    @Environment(\.colorScheme) private var scheme
    var size: CGFloat = 28
    var body: some View {
        // The user's orb artwork only (build.sh decodes app/siri-icon*.b64).
        // Dark/light pair swapped by theme, like the web's siriRowIcon().
        // Fallback is Apple's own intelligence glyph, never a redraw.
        if let img = UIImage(named: scheme == .dark ? "SiriOrbDark" : "SiriOrb") {
            Image(uiImage: img).resizable().scaledToFit().frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else if let sys = UIImage(systemName: "apple.intelligence") {
            Image(uiImage: sys).resizable().scaledToFit().frame(width: size, height: size)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Home

struct SettingsHomeView: View {
    @EnvironmentObject var store: SettingsStore
    @StateObject private var briefing = BriefingStore()

    var body: some View {
        List {
            // 1. Account card (first on the home, web 26E117).
            Section {
                NavigationLink(destination: ProfileView()) {
                    HStack(spacing: 12) {
                        if let p = store.profile {
                            if let data = Data(base64Encoded: p.avatar.dataURIBody()),
                               let img = UIImage(data: data) {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 42, height: 42).clipShape(Circle())
                            } else {
                                Circle().fill(Color.accentColor).frame(width: 42, height: 42)
                                    .overlay(Text(p.initial).font(.system(size: 18, weight: .semibold)).foregroundColor(.white))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.headline)
                                Text("ID: \(p.id) · \(store.t("profile.since")): \(p.since)")
                                    .font(.subheadline).foregroundColor(.secondary)
                            }
                        } else {
                            Circle().fill(Color.secondary.opacity(0.2)).frame(width: 42, height: 42)
                                .overlay(Image(systemName: "person.fill").foregroundColor(.secondary))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.t("profile.login")).font(.headline)
                                Text(store.t("profile.tapLogin")).font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // 2. Fused card — row order identical to the web (see file header).
            Section {
                NavigationLink(destination: CityView()) {
                    HStack(spacing: 12) {
                        CityLogoImage(imageName: SettingsData.cities.first(where: { $0.key == store.city })?.logoImageName ?? "BeijingLogo")
                        Text(SettingsData.cityName(store.city, lang: store.effectiveLanguage))
                    }
                }
                NavigationLink(destination: GeneralView()) { Text(store.t("more.general")) }
                // Location row: no sub-page in the web either — tap requests
                // permission; when denied/restricted the hint shows below.
                Button(action: {
                    if store.locationStatus == .denied || store.locationStatus == .restricted {
                        // Hint is shown inline (see footer below); offer iOS Settings.
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        store.requestLocation()
                    }
                }) {
                    HStack {
                        Text(store.t("more.loc")).foregroundColor(.primary)
                        Spacer()
                        Text(store.locationStatusText()).foregroundColor(.secondary)
                    }
                }
                NavigationLink(destination: WhatsNewView()) {
                    HStack {
                        Text(store.t("more.whatsnew.title")).foregroundColor(.primary)
                        Spacer()
                        Text(store.shortVersion).foregroundColor(.secondary)
                    }
                }
                NavigationLink(destination: UpcomingView()) {
                    HStack {
                        Text(store.t("more.upcoming")).foregroundColor(.primary)
                        Spacer()
                        Text(store.t("more.upcoming.count", vars: ["n": "\(SettingsData.upcoming(for: store.city).count)"]))
                            .foregroundColor(.secondary)
                    }
                }
                NavigationLink(destination: RankingView()) { Text(store.t("more.ranking")) }
                NavigationLink(destination: BriefingView()) {
                    HStack {
                        Text(store.t("more.briefing")).foregroundColor(.primary)
                        Spacer()
                        Text(briefing.updated).foregroundColor(.secondary)
                    }
                }
                NavigationLink(destination: TrainsView()) { Text(store.t("more.trains")) }
                NavigationLink(destination: StructureView()) { Text(store.t("more.structure")) }
                NavigationLink(destination: SiriView()) {
                    HStack(spacing: 12) {
                        SiriOrbImage(size: 28)
                        Text(store.t("more.siri"))
                    }
                }
                // About last in the card (user order 2026-11-24: 关于放卡片最下面).
                NavigationLink(destination: AboutView()) { Text(store.t("more.about")) }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if store.locationStatus == .denied || store.locationStatus == .restricted {
                        Text(store.t("more.loc.hint")).font(.footnote)
                    }
                    Text(store.t("more.credit", vars: ["c": SettingsData.cityName(store.city, lang: store.effectiveLanguage)]))
                        .font(.footnote)
                }
            }
        }
        .navigationTitle(store.t("app.name"))
        .onAppear {
            store.refreshFromWeb()
            briefing.refresh()
        }
    }
}

private extension String {
    /// Body of a `data:image/...;base64,...` URI ("" when not a data URI).
    func dataURIBody() -> String {
        guard let comma = firstIndex(of: ",") else { return self }
        return String(self[index(after: comma)...])
    }
}

// MARK: - City switcher

struct CityView: View {
    @EnvironmentObject var store: SettingsStore
    @State private var bjExpanded = false
    @State private var soonNote: String? = nil

    var body: some View {
        List {
            Section(store.t("more.switchCity")) {
                ForEach(SettingsData.cities, id: \.key) { city in
                    Button(action: {
                        if city.key == "bj" {
                            // Beijing row expands to its two map types instead
                            // of switching (web onCityRowTap).
                            bjExpanded.toggle()
                        } else {
                            bjExpanded = false
                            store.setCity(city.key)
                        }
                    }) {
                        HStack(spacing: 12) {
                            CityLogoImage(imageName: city.logoImageName)
                            Text(store.effectiveLanguage == .english ? city.nameEn :
                                 (store.effectiveLanguage == .zhHant ? city.nameHant : city.nameHans))
                                .foregroundColor(.primary)
                            Spacer()
                            if store.city == city.key {
                                Image(systemName: "checkmark").foregroundColor(.accentColor)
                            } else if city.key == "bj" {
                                Image(systemName: bjExpanded ? "chevron.down" : "chevron.right")
                                    .foregroundColor(.secondary).font(.footnote)
                            }
                        }
                    }
                    if city.key == "bj" && bjExpanded {
                        // Beijing map types (web pickBjMapType): 配线图 / 线路图.
                        Button(action: { store.setBjMapType("track") }) {
                            HStack {
                                Text(store.t("map.type.track")).foregroundColor(.primary)
                                    .padding(.leading, 40)
                                Spacer()
                                if store.city == "bj" && store.bjMapType == "track" {
                                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                                }
                            }
                        }
                        Button(action: { store.setBjMapType("line") }) {
                            HStack {
                                Text(store.t("map.type.line")).foregroundColor(.primary)
                                    .padding(.leading, 40)
                                Spacer()
                                if store.city == "bj" && store.bjMapType == "line" {
                                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            Section(store.t("more.citiesSoon")) {
                ForEach(SettingsData.soonCities.indices, id: \.self) { idx in
                    let city = SettingsData.soonCities[idx]
                    Button(action: {
                        // Web showSoonCity: grey row, tap shows the note 2.5s.
                        soonNote = city.name
                        Task {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            if soonNote == city.name { soonNote = nil }
                        }
                    }) {
                        HStack(spacing: 12) {
                            if let stem = city.logoStem, let img = UIImage(named: "SoonLogo_\(stem)") {
                                Image(uiImage: img).resizable().scaledToFit().frame(width: 28, height: 28)
                                    .clipShape(Circle()).grayscale(1.0).opacity(0.6)
                            } else {
                                Circle().fill(Color.secondary.opacity(0.25)).frame(width: 28, height: 28)
                                    .overlay(Text("M").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary))
                            }
                            Text(city.name).foregroundColor(.secondary)
                        }
                    }
                }
                if let note = soonNote {
                    Text(store.t("more.citiesSoonNote", vars: ["c": note]))
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(store.t("more.switchCity"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Language (reuses the existing native LanguageView)

struct LanguagePageView: View {
    @EnvironmentObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LanguageViewHost(
            selected: store.langPref,
            pageTitle: store.t("more.lang"),
            systemTitle: store.t("more.lang.system"),
            hansTitle: store.t("more.lang.hans"),
            hantTitle: store.t("more.lang.hant"),
            enTitle: store.t("more.lang.en"),
            systemDetail: store.systemLangDisplayName()
        ) { key in
            store.setLanguage(key)
            // Web behaviour: tap a language closes the sub-page.
            dismiss()
        }
        // Empty nav title on purpose: the hosted LanguageView draws its
        // own 22pt page title (as it did as a fullscreen overlay); the
        // nav bar here only supplies the back chevron.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LanguageViewHost: UIViewRepresentable {
    var selected: String
    var pageTitle: String
    var systemTitle: String
    var hansTitle: String
    var hantTitle: String
    var enTitle: String
    var systemDetail: String
    var onSelect: (String) -> Void

    func makeUIView(context: Context) -> LanguageView {
        let view = LanguageView(
            pageTitle: pageTitle, systemTitle: systemTitle, hansTitle: hansTitle,
            hantTitle: hantTitle, enTitle: enTitle, systemDetail: systemDetail)
        view.onSelect = onSelect
        return view
    }

    func updateUIView(_ uiView: LanguageView, context: Context) {
        uiView.configure(selected: selected)
    }
}

// MARK: - Appearance (real UISegmentedControl)

struct AppearanceViewPage: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        Form {
            Section(store.t("more.theme")) {
                // Native UISegmentedControl (SwiftUI Picker, segmented
                // style). The 3 dormant glass theme buttons stay dormant.
                Picker(store.t("more.theme"), selection: Binding(
                    get: { store.theme },
                    set: { store.setTheme($0) }
                )) {
                    Text(store.t("more.theme.system")).tag("system")
                    Text(store.t("more.theme.light")).tag("light")
                    Text(store.t("more.theme.dark")).tag("dark")
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
            }
        }
        .navigationTitle(store.t("more.appearance"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - General

struct GeneralView: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        List {
            Section {
                HStack { Text(store.t("app.name")) }
                Button(action: { store.showFullVersion.toggle() }) {
                    HStack {
                        Text(store.t("more.version", vars: ["v": store.showFullVersion
                            ? "v\(store.shortVersion) (\(store.buildVersion))"
                            : store.shortVersion]))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
            }
            Section {
                NavigationLink(destination: AppearanceViewPage()) {
                    HStack(spacing: 12) {
                        // Web row icon is the user-supplied appearance artwork
                        // (app/appearance-icon.b64 -> AppearanceIcon.png).
                        if let img = UIImage(named: "AppearanceIcon") {
                            Image(uiImage: img).resizable().scaledToFit().frame(width: 28, height: 28)
                        }
                        Text(store.t("more.appearance")).foregroundColor(.primary)
                    }
                }
                NavigationLink(destination: LanguagePageView()) {
                    HStack {
                        Text(store.t("more.lang")).foregroundColor(.primary)
                        Spacer()
                        Text(store.effectiveLanguage == .english ? store.t("more.lang.en") :
                             (store.effectiveLanguage == .zhHant ? store.t("more.lang.hant") : store.t("more.lang.hans")))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section {
                Button(action: { store.clearCache() }) {
                    HStack {
                        Text(store.t("more.cache")).foregroundColor(.primary)
                        Spacer()
                        if store.cacheCleared {
                            Text(store.t("more.cache.cleared")).foregroundColor(.secondary)
                        }
                    }
                }
            } footer: {
                Text(store.t("more.cache.note")).font(.footnote)
            }
        }
        .navigationTitle(store.t("more.general"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - What's New (formal releases only)

struct WhatsNewView: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        List {
            ForEach(SettingsData.releaseNotes, id: \.version) { rel in
                NavigationLink(destination: WhatsNewDetailView(release: rel)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.t("more.rel.title", vars: ["v": rel.version])).font(.headline)
                        Text(rel.date).font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(store.t("more.whatsnew.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WhatsNewDetailView: View {
    @EnvironmentObject var store: SettingsStore
    let release: SettingsData.ReleaseNote

    var body: some View {
        List {
            ForEach(release.lines.indices, id: \.self) { i in
                Text(release.lines[i][store.effectiveLanguage.i18nIndex])
                    .font(.body).padding(.vertical, 2)
            }
        }
        .navigationTitle(store.t("more.whatsnew.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Upcoming

struct UpcomingView: View {
    @EnvironmentObject var store: SettingsStore
    private var lines: [SettingsData.UpcomingLine] { SettingsData.upcoming(for: store.city) }

    var body: some View {
        List {
            Section(SettingsData.cityName(store.city, lang: store.effectiveLanguage)) {
                if lines.isEmpty {
                    Text(store.t("more.upcoming.none")).foregroundColor(.secondary)
                }
                ForEach(lines, id: \.key) { line in
                    HStack(spacing: 12) {
                        Text(line.badge)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color.textOn(hex: line.colorHex))
                            .frame(minWidth: 34, minHeight: 28)
                            .background(Color(hex: line.colorHex))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.t("upcoming.\(line.key)")).font(.headline)
                            Text(metaText(for: line)).font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(store.t("upcoming.date.\(line.dateKey)"))
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            if store.city == "bj" {
                Section { Text(store.t("upcoming.note.bjjx")).font(.footnote).foregroundColor(.secondary) }
            }
            if store.city == "sh" {
                Section { Text(store.t("upcoming.note.sh22")).font(.footnote).foregroundColor(.secondary) }
            }
        }
        .navigationTitle(store.t("more.upcoming"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metaText(for line: SettingsData.UpcomingLine) -> String {
        var parts: [String] = []
        if !line.km.isEmpty { parts.append("\(line.km) km") }
        if !line.stations.isEmpty {
            parts.append(store.t("upcoming.meta.stations", vars: ["n": line.stations]))
        }
        if !line.interchanges.isEmpty {
            parts.append(store.t("upcoming.meta.interchanges", vars: ["n": line.interchanges]))
        }
        if line.approx, let first = parts.first { parts[0] = "≈" + first }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Mileage ranking

struct RankingView: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        List {
            ForEach(SettingsData.ranking, id: \.rank) { row in
                HStack(spacing: 12) {
                    Text("\(row.rank)").font(.headline).frame(width: 28, alignment: .trailing)
                        .foregroundColor(row.rank <= 3 ? .accentColor : .primary)
                    if let key = row.cityKey.isEmpty ? nil : row.cityKey,
                       let city = SettingsData.cities.first(where: { $0.key == key }) {
                        CityLogoImage(imageName: city.logoImageName, size: 28)
                    } else if let stem = SettingsData.soonCities.first(where: { $0.name == row.name })?.logoStem,
                              let img = UIImage(named: "SoonLogo_\(stem)") {
                        // Web rankLogoFor: cities without a supported key
                        // show their More-cities logo, greyed.
                        Image(uiImage: img).resizable().scaledToFit().frame(width: 28, height: 28)
                            .clipShape(Circle()).grayscale(1.0).opacity(0.6)
                    } else {
                        Circle().fill(Color.secondary.opacity(0.25)).frame(width: 28, height: 28)
                            .overlay(Text("M").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.cityKey.isEmpty ? row.name : SettingsData.cityName(row.cityKey, lang: store.effectiveLanguage))
                            .font(.headline)
                        Text(store.t("ranking.src", vars: ["s": row.source, "d": row.date])
                             + (row.note.isEmpty ? "" : " · \(row.note)"))
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(store.t("ranking.km", vars: ["n": row.km])).font(.headline)
                }
                .padding(.vertical, 2)
            }
            Section {
                Text(store.t("ranking.note")).font(.footnote).foregroundColor(.secondary)
            }
        }
        .navigationTitle(store.t("more.ranking"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Briefing

struct BriefingView: View {
    @EnvironmentObject var store: SettingsStore
    @StateObject private var briefing = BriefingStore()
    private var items: [BriefingItem] { briefing.items(for: store.city) }

    var body: some View {
        List {
            if items.isEmpty {
                Text(store.t("more.briefing.empty")).foregroundColor(.secondary)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: item.color)).frame(width: 10, height: 10)
                        Text(item.text(item.title, item.title_en, lang: store.effectiveLanguage))
                            .font(.headline)
                    }
                    Text(item.text(item.summary, item.summary_en, lang: store.effectiveLanguage))
                        .font(.subheadline).foregroundColor(.secondary)
                    let srcText = item.text(item.source ?? "", item.source_en, lang: store.effectiveLanguage)
                    if !srcText.isEmpty {
                        Text(store.t("more.briefing.source", vars: ["s": srcText])).font(.footnote).foregroundColor(.secondary)
                    }
                    Text(item.text(item.date, item.date_en, lang: store.effectiveLanguage))
                        .font(.footnote).foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section {
                Text(store.t("more.briefing.updated", vars: ["d": briefing.updated]))
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
        .navigationTitle(store.t("more.briefing"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { briefing.refresh() }
    }
}

// MARK: - Train search

struct TrainsView: View {
    @EnvironmentObject var store: SettingsStore
    @StateObject private var trains = TrainsStore()
    @State private var query = ""

    private var groups: [(city: TrainCity, trains: [TrainEntry])] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : trains.results(for: query)
    }

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(store.t("more.trains.hint")).foregroundColor(.secondary)
            } else if groups.isEmpty {
                Text(store.t("more.trains.none")).foregroundColor(.secondary)
            }
            ForEach(groups.indices, id: \.self) { gi in
                let group = groups[gi]
                Section(store.effectiveLanguage == .english ? (group.city.name_en ?? group.city.name) : group.city.name) {
                    ForEach(group.trains, id: \.model) { tr in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr.model).font(.headline)
                            Text("\(tr.maker) · \(tr.line)").font(.subheadline).foregroundColor(.secondary)
                            if let spec = tr.spec {
                                Text(spec).font(.footnote).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Section {
                Text(store.t("more.trains.source")).font(.footnote).foregroundColor(.secondary)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: store.t("more.trains.ph"))
        .navigationTitle(store.t("more.trains"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { trains.refresh() }
    }
}

// MARK: - Station structure

struct StructureView: View {
    @EnvironmentObject var store: SettingsStore
    @StateObject private var structStore = StructureStore()
    @State private var query = ""
    @State private var stations: [SettingsStore.WebStation] = []
    @State private var selected: String? = nil

    private var filtered: [String] {
        let names: [String]
        if stations.isEmpty {
            // Fallback when the web is not ready: stations that have diagrams.
            names = structStore.stationsWithDiagrams(city: store.city)
        } else {
            names = stations.map { $0.n }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return Array(names.prefix(200)) }
        let byName = names.filter { $0.lowercased().contains(q) }
        let byPy = stations.filter { $0.py.lowercased().contains(q) || $0.ini.lowercased().contains(q) }.map { $0.n }
        var seen = Set<String>()
        return (byName + byPy).filter { seen.insert($0).inserted }.prefix(200).map { $0 }
    }

    var body: some View {
        List {
            ForEach(filtered, id: \.self) { name in
                NavigationLink(destination: StructureDetailView(station: name)) {
                    HStack {
                        Text(name).foregroundColor(.primary)
                        Spacer()
                        if structStore.entry(city: store.city, station: name) == nil {
                            Text(store.t("struct.pendingShort")).font(.footnote).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: store.t("search.ph"))
        .navigationTitle(store.t("more.structure"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.fetchWebStations { list in
                // Keep the web's line order (stations arrive in line order).
                stations = list
            }
        }
    }
}

struct StructureDetailView: View {
    @EnvironmentObject var store: SettingsStore
    @StateObject private var structStore = StructureStore()
    let station: String
    @State private var kind: String = "spatial" // spatial | plan
    @State private var image: UIImage? = nil
    @State private var loadState: String = "idle" // idle | loading | ready | error
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var entry: StructEntry? { structStore.entry(city: store.city, station: station) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $kind) {
                Text(store.t("struct.spatial")).tag("spatial")
                Text(store.t("struct.plan")).tag("plan")
            }
            .pickerStyle(.segmented)
            .padding()
            .onChange(of: kind) { _ in load() }

            if fileForKind == nil {
                // No diagram on record for this station + kind: the
                // "being prepared" placeholder (never the error state).
                Text(kind == "spatial" ? store.t("struct.pendingSpatial") : store.t("struct.pendingPlan"))
                    .foregroundColor(.secondary).padding()
                Spacer()
            } else if loadState == "loading" || (loadState == "idle" && image == nil) {
                ProgressView(store.t("struct.loading")).padding()
                Spacer()
            } else if loadState == "error" || image == nil {
                VStack(spacing: 12) {
                    Text(store.t("struct.loadFailed")).foregroundColor(.secondary)
                    Button(store.t("struct.retry")) { load() }
                }
                .padding()
                Spacer()
            } else if let img = image {
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(width: geo.size.width * scale, height: geo.size.height * scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { v in scale = max(0.5, min(6.0, lastScale * v)) }
                                    .onEnded { _ in lastScale = scale }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { v in offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) }
                                    .onEnded { _ in lastOffset = offset }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation { scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero }
                            }
                    }
                }
            }
            if let src = sourceLabel(), !src.isEmpty {
                HStack {
                    Text(store.t("struct.source")).foregroundColor(.secondary)
                    Text(src).foregroundColor(.secondary)
                    Spacer()
                }
                .font(.footnote).padding()
            }
        }
        .navigationTitle(station)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
    }

    private var fileForKind: String? {
        guard let e = entry else { return nil }
        return kind == "spatial" ? e.spatial : e.plan
    }

    private func load() {
        image = nil
        scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
        guard let file = fileForKind, let url = entry?.urls?[kind] else {
            loadState = "idle"
            return
        }
        loadState = "loading"
        structStore.image(for: file, url: url) { img in
            if let img = img { image = img; loadState = "ready" }
            else { loadState = "error" }
        }
    }

    /// Same display mapping as the web (template.html structSourceLabel):
    /// user-photo stays labelled, otherwise the source host's known name.
    private func sourceLabel() -> String? {
        guard let e = entry, let raw = e.sources?[kind], !raw.isEmpty else { return nil }
        if raw == "user-photo" { return store.t("struct.src.userphoto") }
        guard let host = URL(string: raw)?.host else { return raw }
        let names: [String: String] = [
            "service.shmetro.com": "上海地铁官网",
            "cdnwww.mtr.bj.cn": "京港地铁官网",
            "upload.wikimedia.org": "维基百科照片（官方站内示意图，CC BY-SA 3.0）",
            "zrzyj.shenyang.gov.cn": "沈阳市自然资源局公示",
            "static.wikia.nocookie.net": "深圳交通百科",
            "www.jhmtr.net": "金华轨道交通官网",
            "imgcdn.scol.com.cn": "四川在线",
            "imgbdb3.bendibao.com": "本地宝",
            "imgbdb4.bendibao.com": "本地宝",
        ]
        return names[host] ?? host
    }
}

// MARK: - Siri

private struct SiriShortcut: Hashable {
    let id: String; let nameKey: String; let descKey: String; let voiceKey: String
}

struct SiriView: View {
    @EnvironmentObject var store: SettingsStore
    private let shortcuts: [SiriShortcut] = [
        SiriShortcut(id: "openApp", nameKey: "siri.openApp", descKey: "siri.openApp.desc", voiceKey: "siri.openApp.voice"),
        SiriShortcut(id: "firstTrain", nameKey: "siri.firstTrain", descKey: "siri.firstTrain.desc", voiceKey: "siri.firstTrain.voice"),
        SiriShortcut(id: "lastTrain", nameKey: "siri.lastTrain", descKey: "siri.lastTrain.desc", voiceKey: "siri.lastTrain.voice"),
        SiriShortcut(id: "planRoute", nameKey: "siri.planRoute", descKey: "siri.planRoute.desc", voiceKey: "siri.planRoute.voice"),
        SiriShortcut(id: "nearestStation", nameKey: "siri.nearestStation", descKey: "siri.nearestStation.desc", voiceKey: "siri.nearestStation.voice"),
        SiriShortcut(id: "timetable", nameKey: "siri.timetable", descKey: "siri.timetable.desc", voiceKey: "siri.timetable.voice"),
    ]

    var body: some View {
        List {
            Section {
                // Real UISwitch (SwiftUI Toggle renders as UISwitch).
                // No web slot, no frame sync — this is the class of bug
                // the 26E124 slot fix addressed; it cannot occur here.
                Toggle(store.t("siri.nearbySmart"), isOn: Binding(
                    get: { store.nearbySmart },
                    set: { store.setNearbySmart($0) }
                ))
            } footer: {
                Text(store.t("siri.nearbySmart.desc")).font(.footnote)
            }
            Section {
                Text(store.t("more.siri.note")).font(.footnote).foregroundColor(.secondary)
            }
            Section {
                ForEach(shortcuts, id: \.id) { s in
                    Button(action: { store.addShortcut(s.id) }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.t(s.nameKey)).font(.headline).foregroundColor(.primary)
                            Text(store.t(s.descKey)).font(.subheadline).foregroundColor(.secondary)
                            Text(store.t(s.voiceKey)).font(.subheadline).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(store.t("more.siri"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Profile (local only)

struct ProfileView: View {
    @EnvironmentObject var store: SettingsStore
    @State private var nameDraft: String = ""
    @State private var avatarDraft: String = ""
    @State private var showPicker = false
    @State private var logoutArmed = false

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Button(action: { showPicker = true }) {
                            avatarView(size: 88)
                        }
                        .buttonStyle(.plain)
                        Text(store.t("profile.avatarHint")).font(.footnote).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            Section {
                HStack {
                    Text(store.t("profile.name"))
                    TextField(store.t("profile.namePh"), text: $nameDraft)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: nameDraft) { v in
                            if v.count > 24 { nameDraft = String(v.prefix(24)) }
                        }
                }
                HStack {
                    Text("ID")
                    Spacer()
                    Text(store.profile?.id ?? store.t("profile.idAuto")).foregroundColor(.secondary)
                }
                if let p = store.profile {
                    HStack {
                        Text(store.t("profile.since"))
                        Spacer()
                        Text(p.since).foregroundColor(.secondary)
                    }
                }
            }
            Section {
                Button(action: { store.saveProfile(name: nameDraft, avatarDataURI: avatarDraft) }) {
                    HStack { Spacer(); Text(store.profile == nil ? store.t("profile.login") : store.t("profile.save")); Spacer() }
                }
            }
            if store.profile != nil {
                Section {
                    Button(action: {
                        if !logoutArmed {
                            logoutArmed = true
                            Task {
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                logoutArmed = false
                            }
                        } else {
                            logoutArmed = false
                            store.logoutProfile()
                            nameDraft = ""
                            avatarDraft = ""
                        }
                    }) {
                        HStack { Spacer(); Text(logoutArmed ? store.t("profile.logoutConfirm") : store.t("profile.logout")).foregroundColor(.red); Spacer() }
                    }
                }
            }
        }
        .navigationTitle(store.t("profile.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nameDraft = store.profile?.name ?? ""
            avatarDraft = store.profile?.avatar ?? ""
        }
        .sheet(isPresented: $showPicker) {
            AvatarPicker { dataURI in avatarDraft = dataURI }
        }
    }

    private func avatarView(size: CGFloat) -> some View {
        Group {
            if let data = Data(base64Encoded: avatarDraft.dataURIBody()), let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else if let p = store.profile, !p.avatar.isEmpty,
                      let data = Data(base64Encoded: p.avatar.dataURIBody()), let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else if let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? store.profile?.name : nameDraft,
                      !name.isEmpty {
                Circle().fill(Color.accentColor).frame(width: size, height: size)
                    .overlay(Text(String(name.prefix(1))).font(.system(size: size * 0.4, weight: .semibold)).foregroundColor(.white))
            } else {
                Circle().fill(Color.secondary.opacity(0.2)).frame(width: size, height: size)
                    .overlay(Image(systemName: "person.fill").font(.system(size: size * 0.45)).foregroundColor(.secondary))
            }
        }
    }
}

/// PHPicker (PhotosUI, no photo-library permission needed) — same
/// downscale as the web's onAvatarFile: max 256px, JPEG 0.85, white
/// background, returned as a data URI.
struct AvatarPicker: UIViewControllerRepresentable {
    var onPick: (String) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (String) -> Void
        init(onPick: @escaping (String) -> Void) { self.onPick = onPick }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                // Downscale to <=256px on a white background, JPEG 0.85.
                let maxSide: CGFloat = 256
                let scale = min(1.0, maxSide / max(image.size.width, image.size.height))
                let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
                let renderer = UIGraphicsImageRenderer(size: size)
                let resized = renderer.image { _ in
                    UIColor.white.setFill()
                    UIRectFill(CGRect(origin: .zero, size: size))
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                guard let data = resized.jpegData(compressionQuality: 0.85) else { return }
                DispatchQueue.main.async {
                    self?.onPick("data:image/jpeg;base64," + data.base64EncodedString())
                }
            }
        }
    }
}

// MARK: - About

struct AboutView: View {
    @EnvironmentObject var store: SettingsStore
    @Environment(\.colorScheme) private var scheme

    private var appIcon: UIImage? {
        // Loose bundle files (decoded by build.sh from app/icons.json).
        // Dark variant by theme; light artwork as fallback.
        if scheme == .dark, let dark = UIImage(named: "AppIcon60x60@3x~dark") { return dark }
        return UIImage(named: "AppIcon60x60@3x")
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    if let icon = appIcon {
                        Image(uiImage: icon).resizable().scaledToFit().frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    Text(store.t("app.name")).font(.headline)
                    Text(store.t("more.about.desc")).font(.subheadline).foregroundColor(.secondary)
                    Button(action: { store.showFullVersion.toggle() }) {
                        Text(store.t("more.version", vars: ["v": store.showFullVersion
                            ? "v\(store.shortVersion) (\(store.buildVersion))"
                            : store.shortVersion]))
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                Text(store.t("more.about.disclaimer")).font(.footnote).foregroundColor(.secondary)
            }
            Section {
                Button(action: { store.openRepo() }) {
                    HStack { Text(store.t("more.repo")).foregroundColor(.primary); Spacer(); Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary) }
                }
                Button(action: { store.openRepo() }) {
                    HStack { Text(store.t("more.about.github")).foregroundColor(.primary); Spacer(); Text("Andy-transport").foregroundColor(.secondary); Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary) }
                }
                Button(action: { store.openDouyin(userID: "351453703") }) {
                    HStack { Text(store.t("more.about.compile")).foregroundColor(.primary); Spacer(); Text("351453703").foregroundColor(.secondary); Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary) }
                }
                Button(action: { store.openDouyin(userID: "xlcty199") }) {
                    HStack { Text(store.t("more.about.test")).foregroundColor(.primary); Spacer(); Text("xlcty199").foregroundColor(.secondary); Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary) }
                }
                Button(action: { store.openDouyin(userID: "75387112248") }) {
                    HStack { Text(store.t("more.about.debug")).foregroundColor(.primary); Spacer(); Text("75387112248").foregroundColor(.secondary); Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary) }
                }
            }
        }
        .navigationTitle(store.t("more.about"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
