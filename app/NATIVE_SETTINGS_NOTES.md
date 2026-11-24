# 原生设置页（Native Settings）— 设计与验证说明

> 位置：本副本 `~/workspace/metro-ios-native/`（与测试版 `~/workspace/metro-ios/` 完全分离）。
> 状态（2026-11-24）：代码已写完、自查已完成；**未在本机编译**（Linux VM 无 Swift 工具链），**未推 GitHub、未构建、未发 IPA**。
> 范围：只重写设置页（底栏「设置」）。其余 4 个页（换乘 / 线路图 / 搜索 / 时刻表）一律不动，仍走网页。

## 1. 改了哪些文件

| 文件 | 变化 | 行数 |
| --- | --- | --- |
| `app/SettingsStore.swift` | 新增 | 556 |
| `app/SettingsStrings.swift` | 新增（192 个 i18n 键，中/繁/英三语，逐字取自网页 `I18N`） | 210 |
| `app/SettingsData.swift` | 新增（15 城、44 个未开通城市、11 条即将开通线路、42 行里程排名、2 条正式版更新说明） | 163 |
| `app/SettingsSeedData.swift` | 新增（简报 / 车型 / 车站结构索引 JSON 原文，`#"""..."""#` 原样嵌入） | 14（3 个大 JSON 字符串） |
| `app/SettingsViews.swift` | 新增（设置首页 + 13 个子页，SwiftUI） | 1065 |
| `app/SettingsHosting.swift` | 新增（`SettingsHostingController` + `MapViewController: SettingsBridge` + `presentNativeSettings()` / `dismissNativeSettings()`） | 208 |
| `app/AppDelegate.swift` | 修改（+约 22 行，见 §2） | 4686 → 4708 |
| `build.sh` | 修改（6 个新文件进 `SWIFT_SOURCES`；加 `-framework SwiftUI -framework PhotosUI`；解码 `SiriOrb[.Dark].png` 与 `SoonLogo_*.png` 进 bundle） | — |

隔离验证：`diff -rq metro-ios metro-ios-native` 只显示以上 2 个修改文件 + 6 个新增文件，其余全部一致。

## 2. 接入方式（原生壳改动最小）

- `MapViewController` 新增属性 `settingsStore / settingsHosting / settingsActive`（AppDelegate.swift:195–197）。
- `setWebTab(index:)`（AppDelegate.swift:3666–3693）：离开设置时先 `dismissNativeSettings()`；点「设置」（key `"more"`）时调 `presentNativeSettings()`，**不再**调网页 `setTab('more')`，网页 `#moreSheet` 永不显示；其余 4 个 tab 原样走 `window.metroApp.setTab(...)`。
- `applyLanguage()`（AppDelegate.swift:855）：语言切换后 `settingsStore?.reloadFromDefaults()`，原生页即时跟随。
- 呈现：`SettingsHostingController`（`UIHostingController<AnyView>`）作为子视图盖在 WKWebView 之上，网页保持加载（`evaluateJavaScript` 仍可用），底栏 `bringSubviewToFront(tabBar)` 保持在最上。离开时移除宿主、恢复网页显示。
- 布局（防遮挡，见 custom skill `native_fullscreen_gating_pages`）：宿主内 SwiftUI 内容——iPhone：顶 = 安全区顶，底 = 底栏顶 − 8；iPad：顶 = 顶部胶囊底栏底 + 8，底 = 安全区底；Duo 展开（右侧 64pt 侧栏）：右 = 侧栏左 − 8。`viewDidLayoutSubviews` 重算。主题只作用于设置页（`overrideUserInterfaceStyle` 跟随 store）。

## 3. 状态同步（单一事实来源 = UserDefaults，与网页双向同步）

网页 `file:// localStorage` 在真机上不可靠（AppDelegate.swift:896–904 注释），原生注入 `_metroInitCity/_metroInitTheme/_metroInitDark` 是事实来源。原生设置页沿用同一套：

| 状态 | 原生写哪里 | 如何通知网页 |
| --- | --- | --- |
| 城市 `metro-city` | UserDefaults | 先写 UserDefaults，再 `pickCity` 同款 JS 调网页 `switchCity()` |
| 主题 `metro-theme` / `metro-dark` | UserDefaults | 先写 UserDefaults，再调 `applyAppearanceTheme` 同款 `setTheme()` |
| 语言 `metro-lang` / `metro-lang-explicit` | UserDefaults（沿用原生不对称设计：`applyLanguageChoice` 不直接持久化，网页 `langChanged` 回调后原生 `setLang()` 才持久化，AppDelegate.swift:795） | 调网页 `setLang()` |
| 附近车站智能显示 `metro-nearby-smart` | 读网页 JS、写 `window.__setNearbySmart`（template.html:7105）；原生开关是 SwiftUI `Toggle`（= UISwitch），位置由布局决定，**不用** `getBoundingClientRect`（26E124 已修过的坑） |
| 个人资料 `metro-profile` | UserDefaults（同键名），首次使用时迁移一次网页现有资料；保存/退出时镜像回写网页 localStorage | — |
| 北京地图类型 `metro-bj-maptype` | UserDefaults（同键名）+ 写网页 localStorage + 调 `pickBjMapType()` | — |

进入设置时 `store.refreshFromWeb()` 从网页再读一次当前值（防两边漂移）。

## 4. 首页行顺序（逐行核对，与网页 #moreSheet 一致）

账号卡（头像/昵称/ID/登录日期；未登录显示「登录后可设置头像与昵称」）→ 融合大卡：切换城市 → 通用 → 关于 → 定位 → 功能介绍（右侧正式版短版本 `1.0.0`）→ 即将开通（当前城市条数）→ 里程排名 → 轨道交通信息简报（右侧简报日期）→ 车型检索 → 车站结构 → Siri快捷指令。

## 5. 子页状态（13 个，全部已实现代码，需真机验）

切换城市 / 语言（复用 `LanguageView.swift`，`LanguageViewHost` 包装；导航栏只提供返回，页内标题由 `LanguageView` 自绘）/ 功能介绍（**仅正式版条目**：A26108、A26107；无测试版内容）/ 即将开通 / 里程排名 / 简报 / 外观（SwiftUI 分段 `跟随系统/浅色/深色`；3 个玻璃主题按钮保持废弃；`AppearanceView.swift` 原样保留）/ 通用（App 名 + 版本，点版本号切换显示 `v1.0.0 (A26108)`）/ 车型检索 / 车站结构 / Siri（6 条指令点按调现有 `presentShortcutSetup(for:)`；附近车站智能显示为原生 Toggle；定位行走 `requestLocationPermission()`，拒绝时显示 `more.loc.hint` 并提供系统设置入口）/ 个人资料（PHPicker 选头像，≤256px JPEG 0.85 白底；ID 规则 `CT` + 10 位随机数字；`since` 为首次保存日期；退出登录需 3 秒内双击）/ 关于（项目主页 / 作者 GitHub = `Andy-transport/Subway-Tools`；编译 `351453703` / 测试 `xlcty199` / 调试 `75387112248`，抖音深链 `snssdk1128://user/profile/<id>`，失败回退网页搜索）。

数据页在线刷新走与网页相同的 URL（`raw.githubusercontent.com/Andy-transport/Subway-Tools/main/web/briefing.json`、`trains.json`），缓存键名与网页一致；车站结构图按需从 jsDelivr 新仓库名 + 固定 SHA `e1703fda…` 拉取（base64 文本解码为 UIImage，与网页 `loadStructImg` 同源）。

## 6. 本地验证结果（2026-11-24，Linux VM）

- 5 个手写 Swift 文件括号/圆括号/方括号全部平衡；`SettingsSeedData.swift` 的 3 个 JSON 字符串经 Python `json.loads` 逐个验证通过（简报 18 条、车型 15 城 / 371 条、结构索引 394 站）；粗糙 stripper 曾报的括号不平衡是检查器误报（字符串内的括号），已证伪。
- i18n 键覆盖：`SettingsStrings` 定义 192 键，视图/Store/Hosting 共用 67 键，**无缺失**。
- 16 个视图结构体、11 个首页行键全部存在；无 TODO/占位符；新文件无对原目录的引用。
- `diff -rq` 证明隔离（见 §1）。
- **无法本地编译**：VM 上无 Swift 工具链（`which swiftc xcodebuild swift` 无结果，`/usr/lib/swift` 不存在）。未谎称编过。

## 7. 还缺什么才能出真机 IPA

1. **CI 构建**：推到 GitHub 后由 `.github/workflows/build-ipa.yml`（`xcode-27` runner，跑 `bash build.sh`）编译；这是下一个门禁。注意：`build.sh` 目前优先 Xcode **27.3 beta** 再 27.2/27.1/27.0，与用户「全部用 SDK 27.2」规则冲突——构建前需决定是否把 `build.sh` 钉到 27.2。
2. **真机验证**：13 个子页逐个在 iPhone / iPad / Duo 展开三形态下点一遍（切城、语言、主题、Siri 注册、定位权限、个人资料、结构图加载、在线刷新）。
3. **版本号决定**（见 §8）：plist 未改，仍是 `1.0.0 (A26108)`。

## 8. 版本号建议（未执行，等决定）

建议：**保持 `CFBundleShortVersionString = 1.0.0`，`CFBundleVersion` 升为 `A26109`**，作为本副本的下一个正式候选（接在已发的正式版 A26108 之后）。不要用测试版号：测试线已在 26E126，26E127 已排给洛阳接入，用 26E 系会撞号。若走测试流程，需另定不冲突的编号。plist 本次未改。

## 9. 已知未实现 / 差异（不藏着）

- **26E128（测试线 item J）未实现**：切换城市只列已下载城市、未下载城市需从设置页下载——本副本 15 城全部内置打包，城市列表即全部 15 城，无下载机制。这是新功能，不属本次「重写设置页」范围；若要对齐测试线，需另做。
- **测试线 iPad item R**（去掉 iPad 子页顶安全区、按钮滑动隐藏）未实现——测试线范围，不属本副本。
- 完整 5 页全原生重写：用户 2026-11-24 22:57 在测试版对话里已说「先不做」（保持 hybrid）；本工作是用户在另一对话里单独决定「做，先从设置页开始」的隔离副本，**不要**据此重新提案全页重写。
- 北京站数：本副本为 **417**（测试线 421 是另一条线的状态，不要混用）。
- **切城后落点（已按网页行为实现）**：网页点城市后落到换乘 tab；原生版 `setCity` 后经 `settingsCitySwitched()` 关闭整个设置页，用户同样落在换乘页（新增桥方法，见 `SettingsStore.swift` / `SettingsHosting.swift`）。
- **定位行（有意的偏离，已记录）**：网页该行点按是直接跳系统设置本 App 页（`openExternal('app-settings')`）；原生版改为：未请求/已允许时先在应用内弹系统授权框（走 `requestLocationPermission` 桥），仅拒绝/受限时才跳系统设置并在行下显示 `more.loc.hint`。这更符合 brief「走系统权限流程」的要求；如需与网页完全一致，改回一律跳转即可。
- **雄安（以副本代码为准）**：切换城市子页里雄安与其它 43 个未开通城市行为完全一致（灰色行，点后 2.5 秒提示「即将支持，敬请期待」），**不是**不可点占位。记忆中「雄安不可点」与本副本代码不符，原生版按代码实现。
- **Siri 深浅图标实为同一文件**：`app/siri-icon.b64` 与 `app/siri-icon-dark.b64` 解码后字节完全相同（SHA-256 前缀 `57fef347…`，各 38,976 字节），深浅切换无视觉差别——与网页行为一致，不改。
- **通用页外观行图标**：已补为用户提供的 `app/appearance-icon.b64`（18,499 字节 PNG，`build.sh` 解码为 `AppearanceIcon.png`），与网页一致。
- **车型检索无结果文案沿用原文**：`more.trains.none` 仍写「仅支持…13 个城市」，而 `trains.json` 实际已有 15 城——这是网页原文滞后，按 brief「不改文案含义」原样保留，未擅自改写。
- 未开通城市数：代码实为 **44 条（含雄安）**，不是任务初稿说的 46；以代码为准。
