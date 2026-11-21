import UIKit

// Search Conditions screen (build 65; rebuilt as standard Apple UI
// SDK 27.2, user 2026-11-19): a full-screen native page presented
// inside a UINavigationController. The user circled the old custom
// dark-circle back button and asked for proper Apple UI, so every
// custom-styled control is replaced with a standard UIKit component:
//   - UINavigationBar with the standard back chevron (a plain
//     UIBarButtonItem with the chevron.backward SF Symbol — no
//     custom circle, no custom background) + the title "搜索条件"
//   - UISegmentedControl for 出发 / 到达 / 首班车 / 末班车
//   - UIDatePicker, wheels style, date + time (date only for
//     首班车 / 末班车, where the time comes from the timetable)
//   - payment: a creditcard icon + current-payment label, then a
//     UISegmentedControl for 交通卡 / 现金 only. (Apple Pay was
//     removed from this screen, user 2026-11-19 — it lives as a
//     button on the Transfer tab instead, not here.)
//   - bottom: 现在出发 (standard system-grey button) and 完成
//     (standard filled button in the city-theme accent — the
//     primary action)
// Behaviour is unchanged: 完成 passes {mode, date, time, payment}
// back to the AppDelegate, which forwards it to the web via
// window.metroApp.applySearchConditions(...). 现在出发 applies
// "depart now" (same dict plus now: true, so the shell clears the
// chosen time instead of setting a fixed time). Back dismisses
// without applying anything.
// The payment choice is recorded and passed through; fares are NOT
// changed — no per-city card-vs-cash subway discount rule has been
// verified, so no discount is invented (standard fare stays).
// All colours and fonts are system values, so the screen follows
// light and dark mode automatically, on iPhone and iPad.
final class SearchConditionsViewController: UIViewController {

    // Inputs, set by AppDelegate before presenting.
    var labels: [String: String] = [:]
    var accent: UIColor = .systemBlue
    var initialMode: String = "depart"   // depart | arrive | first | last
    var initialDate: Date = Date()
    var initialPayment: String = "cash"  // card | cash
    var localeIdentifier: String = "zh_CN"
    var onDone: (([String: Any]) -> Void)?

    private var mode: String = "depart"
    private var payment: String = "cash"
    private var picker: UIDatePicker!
    private var modeControl: UISegmentedControl!
    private var payControl: UISegmentedControl!
    private var payLabel: UILabel!

    private let modeKeys = ["depart", "arrive", "first", "last"]
    private let payKeys = ["card", "cash"]

    private func L(_ key: String) -> String {
        return labels[key] ?? key
    }

    // Light-mode legibility (user 2026-11-19 "适配一下浅色模式").
    // The city accent is a FIXED colour in both modes, so anything
    // drawn on it (or tinted with it) must be judged from the
    // accent's own luminance, not from the interface style.
    // Relative luminance (WCAG) of a colour.
    private static func luminance(of color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }
        func lin(_ c: CGFloat) -> CGFloat {
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    // Text colour for the 完成 button: white text on Shenyang gold
    // #D4B686 is ~1.9:1 and illegible, so light accents get black
    // text; every other city accent is dark enough for white text.
    // Fixed black/white (not .label) because the accent background
    // is the same in both modes.
    private func doneButtonTitleColor() -> UIColor {
        return Self.luminance(of: accent) > 0.35 ? .black : .white
    }

    // Accent tint for the payment icon: a light accent is too pale
    // on a white background, so in light mode it is darkened; in
    // dark mode the raw accent reads fine on black. A dynamic colour
    // re-evaluates when the trait changes. The provider captures
    // only the accent value (no self), so there is no retain cycle.
    private func adaptiveAccentTint() -> UIColor {
        UIColor { [accent] trait in
            let base = accent.resolvedColor(with: trait)
            guard trait.userInterfaceStyle == .light else { return base }
            guard Self.luminance(of: base) > 0.35 else { return base }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard base.getRed(&r, green: &g, blue: &b, alpha: &a) else { return base }
            return UIColor(red: r * 0.55, green: g * 0.55, blue: b * 0.55, alpha: a)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // Left-edge swipe-back (26D104, restored): same action as the
        // back button (backTapped). UIScreenEdgePan begins only from
        // the left edge, so the pickers and controls are unaffected.
        let edgePan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgePanBack(_:)))
        edgePan.edges = .left
        view.addGestureRecognizer(edgePan)
        mode = modeKeys.contains(initialMode) ? initialMode : "depart"
        payment = payKeys.contains(initialPayment) ? initialPayment : "cash"

        // Standard navigation bar: title + the standard back chevron
        // (a plain bar button item — no custom circle, no custom
        // background). This VC is presented inside a
        // UINavigationController by AppDelegate.presentSearchConditions.
        navigationItem.title = L("search.title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.backward"),
            style: .plain, target: self, action: #selector(backTapped))

        // Mode: standard segmented control (出发 / 到达 / 首班车 / 末班车).
        let modeTitles = [L("tr.depart"), L("tr.arrive"), L("search.first"), L("search.last")]
        modeControl = UISegmentedControl(items: modeTitles)
        modeControl.selectedSegmentIndex = modeKeys.firstIndex(of: mode) ?? 0
        modeControl.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeControl)

        // Date/time picker (wheels). Date only for first/last train,
        // where the time comes from the timetable.
        picker = UIDatePicker()
        picker.datePickerMode = (mode == "first" || mode == "last") ? .date : .dateAndTime
        if #available(iOS 13.4, *) { picker.preferredDatePickerStyle = .wheels }
        picker.locale = Locale(identifier: localeIdentifier)
        picker.date = initialDate
        picker.minimumDate = Calendar.current.startOfDay(for: Date())
        picker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker)

        // Payment header: card icon + current payment label.
        let payHeader = UIStackView()
        payHeader.axis = .horizontal
        payHeader.alignment = .center
        payHeader.spacing = 10
        payHeader.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: "creditcard"))
        icon.tintColor = adaptiveAccentTint()
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 26).isActive = true
        payHeader.addArrangedSubview(icon)
        payLabel = UILabel()
        payLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        payLabel.textColor = .label
        payHeader.addArrangedSubview(payLabel)
        view.addSubview(payHeader)

        // Payment: standard segmented control (交通卡 / 现金 only).
        let payTitles = [L("search.card"), L("search.cash")]
        payControl = UISegmentedControl(items: payTitles)
        payControl.selectedSegmentIndex = payKeys.firstIndex(of: payment) ?? 1
        payControl.addTarget(self, action: #selector(payChanged(_:)), for: .valueChanged)
        payControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(payControl)

        // Bottom: 现在出发 (standard system-grey button) + 完成
        // (standard filled button in the city accent — the primary action).
        let bottomStack = UIStackView()
        bottomStack.axis = .horizontal
        bottomStack.distribution = .fillEqually
        bottomStack.spacing = 12
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        let nowButton = UIButton(type: .system)
        var nowCfg = UIButton.Configuration.gray()
        nowCfg.title = L("tr.departNow")
        nowCfg.cornerStyle = .large
        nowCfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 17, weight: .bold)
            return a
        }
        nowButton.configuration = nowCfg
        nowButton.addTarget(self, action: #selector(nowTapped), for: .touchUpInside)
        nowButton.translatesAutoresizingMaskIntoConstraints = false
        nowButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        bottomStack.addArrangedSubview(nowButton)
        let doneButton = UIButton(type: .system)
        var doneCfg = UIButton.Configuration.filled()
        doneCfg.title = L("time.done")
        doneCfg.baseBackgroundColor = accent
        doneCfg.baseForegroundColor = doneButtonTitleColor()
        doneCfg.cornerStyle = .large
        doneCfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 17, weight: .bold)
            return a
        }
        doneButton.configuration = doneCfg
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        bottomStack.addArrangedSubview(doneButton)
        view.addSubview(bottomStack)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            modeControl.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            modeControl.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            modeControl.topAnchor.constraint(equalTo: g.topAnchor, constant: 16),
            picker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            picker.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 12),
            payHeader.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            payHeader.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            payHeader.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 16),
            payControl.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            payControl.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            payControl.topAnchor.constraint(equalTo: payHeader.bottomAnchor, constant: 10),
            bottomStack.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            bottomStack.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            bottomStack.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -12),
        ])

        refreshSelection()
    }

    private func refreshSelection() {
        modeControl.selectedSegmentIndex = modeKeys.firstIndex(of: mode) ?? 0
        payControl.selectedSegmentIndex = payKeys.firstIndex(of: payment) ?? 1
        payLabel.text = payment == "card" ? L("search.card") : L("search.cash")
        // First/last train: the date matters, the time comes from the
        // timetable, so the picker shows date only.
        picker.datePickerMode = (mode == "first" || mode == "last") ? .date : .dateAndTime
    }

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        guard sender.selectedSegmentIndex >= 0 && sender.selectedSegmentIndex < modeKeys.count else { return }
        mode = modeKeys[sender.selectedSegmentIndex]
        refreshSelection()
    }

    @objc private func payChanged(_ sender: UISegmentedControl) {
        guard sender.selectedSegmentIndex >= 0 && sender.selectedSegmentIndex < payKeys.count else { return }
        payment = payKeys[sender.selectedSegmentIndex]
        refreshSelection()
    }

    @objc private func backTapped() {
        dismiss(animated: true)
    }

    @objc private func edgePanBack(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        if recognizer.state == .began { backTapped() }
    }

    private func condDict(date: Date, time: Date, now: Bool = false) -> [String: Any] {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: date)
        df.dateFormat = "HH:mm"
        let timeStr = df.string(from: time)
        return ["mode": mode, "date": dateStr, "time": timeStr, "payment": payment, "now": now]
    }

    @objc private func nowTapped() {
        // 现在出发: depart now, keeping the current payment choice.
        let now = Date()
        mode = "depart"
        dismiss(animated: true)
        onDone?(condDict(date: now, time: now, now: true))
    }

    @objc private func doneTapped() {
        let d = picker.date
        dismiss(animated: true)
        onDone?(condDict(date: d, time: d))
    }
}
