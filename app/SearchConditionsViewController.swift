import UIKit

// Search Conditions screen (build 65): native Apple UI (SDK 27.2).
// The user asked for the "搜索条件" screen from the reference app,
// built NATIVELY — not a web page. It replaces the old simple time
// picker sheet (build 34): tapping the transfer panel's time control
// now opens this screen.
//
// Layout (matches the reference):
//   - circular back button (top-left) + title "搜索条件"
//   - 4-option pill row: 出发 / 到达 / 首班车 / 末班车
//     (4 separate Liquid Glass buttons, no sliding — same pattern as
//     the dark-mode picker; selected = accent-tinted glass)
//   - UIDatePicker, wheels style, date + time (date only for
//     首班车 / 末班车, where the time comes from the timetable)
//   - payment row: card icon + current payment label + 3-option pill
//     交通卡 / 现金 / Apple Pay (Apple Pay jumps to the Wallet app;
//     no real payment sheet — the app processes no payments)
//   - bottom: 现在出发 (dark) and 完成 (city-theme accent)
// Behaviour: 完成 passes {mode, date, time, payment} back to the
// AppDelegate, which forwards it to the web via
// window.metroApp.applySearchConditions(...). 现在出发 applies
// "depart now" (same dict plus now: true, so the shell clears the
// chosen time instead of setting a fixed time). Back dismisses
// without applying anything.
// The payment choice is recorded and passed through; fares are NOT
// changed — no per-city card-vs-cash subway discount rule has been
// verified, so no discount is invented (standard fare stays).
// All .glass() calls sit inside `if #available(iOS 26.0, *)`
// (deployment target is iOS 16.0).
final class SearchConditionsViewController: UIViewController {

    // Inputs, set by AppDelegate before presenting.
    var labels: [String: String] = [:]
    var accent: UIColor = .systemBlue
    var initialMode: String = "depart"   // depart | arrive | first | last
    var initialDate: Date = Date()
    var initialPayment: String = "cash"  // card | cash | applepay
    var localeIdentifier: String = "zh_CN"
    var onDone: (([String: Any]) -> Void)?

    private var mode: String = "depart"
    private var payment: String = "cash"
    private var picker: UIDatePicker!
    private var modeButtons: [UIButton] = []
    private var payButtons: [UIButton] = []
    private var payLabel: UILabel!

    private let modeKeys = ["depart", "arrive", "first", "last"]
    private let payKeys = ["card", "cash", "applepay"]

    private func L(_ key: String) -> String {
        return labels[key] ?? key
    }

    // Glass button config, mirroring AppDelegate.themeButtonConfig():
    // Liquid Glass on iOS 26+, filled capsule below.
    private func glassConfig(fontSize: CGFloat) -> UIButton.Configuration {
        var cfg: UIButton.Configuration
        if #available(iOS 26.0, *) {
            cfg = UIButton.Configuration.glass()
        } else {
            cfg = UIButton.Configuration.filled()
        }
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            return a
        }
        cfg.cornerStyle = .capsule
        return cfg
    }

    private func styleOptionButtons(_ buttons: [UIButton], selected idx: Int) {
        for (i, btn) in buttons.enumerated() {
            var cfg = btn.configuration ?? glassConfig(fontSize: 15)
            if i == idx {
                cfg.baseForegroundColor = accent
                cfg.baseBackgroundColor = accent.withAlphaComponent(0.15)
            } else {
                cfg.baseForegroundColor = .label
                cfg.baseBackgroundColor = nil
            }
            btn.configuration = cfg
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        mode = modeKeys.contains(initialMode) ? initialMode : "depart"
        payment = payKeys.contains(initialPayment) ? initialPayment : "cash"

        // Top row: circular back button (left) + centred title.
        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.tintColor = .label
        back.backgroundColor = .secondarySystemBackground
        back.layer.cornerRadius = 18
        back.clipsToBounds = true
        back.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(back)

        let title = UILabel()
        title.text = L("search.title")
        title.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        title.textColor = .label
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        // 4-option mode pill row.
        let modeTitles = [L("tr.depart"), L("tr.arrive"), L("search.first"), L("search.last")]
        let modeStack = UIStackView()
        modeStack.axis = .horizontal
        modeStack.distribution = .fillEqually
        modeStack.spacing = 8
        modeStack.translatesAutoresizingMaskIntoConstraints = false
        for (i, t) in modeTitles.enumerated() {
            let btn = UIButton(type: .system)
            var cfg = glassConfig(fontSize: 15)
            cfg.title = t
            btn.configuration = cfg
            btn.tag = i
            btn.addTarget(self, action: #selector(modeTapped(_:)), for: .touchUpInside)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.heightAnchor.constraint(equalToConstant: 46).isActive = true
            modeStack.addArrangedSubview(btn)
            modeButtons.append(btn)
        }
        view.addSubview(modeStack)

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

        // Payment row: card icon + current payment label + 2-option pill.
        let payRow = UIStackView()
        payRow.axis = .horizontal
        payRow.alignment = .center
        payRow.spacing = 10
        payRow.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: "creditcard"))
        icon.tintColor = accent
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 26).isActive = true
        payRow.addArrangedSubview(icon)
        payLabel = UILabel()
        payLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        payLabel.textColor = .label
        payRow.addArrangedSubview(payLabel)
        let payStack = UIStackView()
        payStack.axis = .horizontal
        payStack.distribution = .fillEqually
        payStack.spacing = 8
        let payTitles = [L("search.card"), L("search.cash"), L("search.applepay")]
        for (i, t) in payTitles.enumerated() {
            let btn = UIButton(type: .system)
            var cfg = glassConfig(fontSize: 13)
            cfg.title = t
            // "Apple Pay" is wider than 交通卡 / 现金: keep the 76pt
            // button but tighten the insets so the label is not clipped.
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
            btn.configuration = cfg
            btn.tag = i
            btn.addTarget(self, action: #selector(payTapped(_:)), for: .touchUpInside)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.heightAnchor.constraint(equalToConstant: 40).isActive = true
            btn.widthAnchor.constraint(equalToConstant: 76).isActive = true
            payStack.addArrangedSubview(btn)
            payButtons.append(btn)
        }
        payRow.addArrangedSubview(payStack)
        view.addSubview(payRow)

        // Bottom: 现在出发 (dark) + 完成 (city-theme accent).
        let bottomStack = UIStackView()
        bottomStack.axis = .horizontal
        bottomStack.distribution = .fillEqually
        bottomStack.spacing = 12
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        let nowButton = UIButton(type: .system)
        nowButton.setTitle(L("tr.departNow"), for: .normal)
        nowButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        nowButton.setTitleColor(.white, for: .normal)
        nowButton.backgroundColor = UIColor(white: 0.13, alpha: 1)
        nowButton.layer.cornerRadius = 14
        nowButton.addTarget(self, action: #selector(nowTapped), for: .touchUpInside)
        nowButton.translatesAutoresizingMaskIntoConstraints = false
        nowButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        bottomStack.addArrangedSubview(nowButton)
        let doneButton = UIButton(type: .system)
        doneButton.setTitle(L("time.done"), for: .normal)
        doneButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.backgroundColor = accent
        doneButton.layer.cornerRadius = 14
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        bottomStack.addArrangedSubview(doneButton)
        view.addSubview(bottomStack)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            back.topAnchor.constraint(equalTo: g.topAnchor, constant: 8),
            back.widthAnchor.constraint(equalToConstant: 36),
            back.heightAnchor.constraint(equalToConstant: 36),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            modeStack.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            modeStack.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            modeStack.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 20),
            picker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            picker.topAnchor.constraint(equalTo: modeStack.bottomAnchor, constant: 12),
            payRow.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            payRow.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            payRow.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 16),
            bottomStack.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            bottomStack.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            bottomStack.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -12),
        ])

        refreshSelection()
    }

    private func refreshSelection() {
        if let idx = modeKeys.firstIndex(of: mode) {
            styleOptionButtons(modeButtons, selected: idx)
        }
        if let idx = payKeys.firstIndex(of: payment) {
            styleOptionButtons(payButtons, selected: idx)
        }
        payLabel.text = payment == "card" ? L("search.card") : (payment == "applepay" ? L("search.applepay") : L("search.cash"))
        // First/last train: the date matters, the time comes from the
        // timetable, so the picker shows date only.
        picker.datePickerMode = (mode == "first" || mode == "last") ? .date : .dateAndTime
    }

    @objc private func modeTapped(_ sender: UIButton) {
        guard sender.tag >= 0 && sender.tag < modeKeys.count else { return }
        mode = modeKeys[sender.tag]
        refreshSelection()
    }

    @objc private func payTapped(_ sender: UIButton) {
        guard sender.tag >= 0 && sender.tag < payKeys.count else { return }
        payment = payKeys[sender.tag]
        refreshSelection()
        // Apple Pay: jump to the Wallet app so the user can use/manage
        // Apple Pay. The app processes no real payments, so there is no
        // PKPaymentAuthorizationViewController sheet — this is a jump
        // to Wallet, not a checkout.
        if payment == "applepay" {
            openWallet()
        }
    }

    // Jump to the Wallet app (wallet://). Uses open() directly, not
    // canOpenURL (which would need the scheme in
    // LSApplicationQueriesSchemes); if Wallet cannot be opened the
    // completion reports failure and we show a short message instead
    // of failing silently.
    private func openWallet() {
        guard let url = URL(string: "wallet://") else { return }
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            guard let self = self else { return }
            if !success {
                self.showWalletUnavailable()
            }
        }
    }

    private func showWalletUnavailable() {
        let alert = UIAlertController(
            title: L("search.applepay.unavailable.title"),
            message: L("search.applepay.unavailable.message"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("time.done"), style: .default))
        present(alert, animated: true)
    }

    @objc private func backTapped() {
        dismiss(animated: true)
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
