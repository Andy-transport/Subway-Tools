import UIKit

// Native Language picker (user 2026-11-19, 语言 → Apple UI SDK 27.2,
// the same treatment as the Appearance picker): an inset-grouped list
// in a card — 跟随系统 (with the current system language shown on the
// right), 简体中文, 繁體中文, English — with a checkmark on the current
// choice. All strings are localized by the caller (AppDelegate.L) and
// can be re-localized in place when the language changes while the
// picker is open.
final class LanguageView: UIView {

    var onSelect: ((String) -> Void)?

    private let keys = ["system", "zh-Hans", "zh-Hant", "en"]
    private var selectedKey: String = "system"

    private let titleLabel = UILabel()
    private let cardView = UIView()
    private var nameLabels: [UILabel] = []
    private var checkViews: [UIImageView] = []
    private let systemDetailLabel = UILabel()

    init(pageTitle: String, systemTitle: String, hansTitle: String, hantTitle: String, enTitle: String, systemDetail: String) {
        super.init(frame: .zero)
        backgroundColor = .systemBackground

        titleLabel.text = pageTitle
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .label

        cardView.backgroundColor = .secondarySystemBackground
        cardView.applyAppleCorner(radius: 28)
        cardView.clipsToBounds = true

        let titles = [systemTitle, hansTitle, hantTitle, enTitle]
        var rows: [UIView] = []
        for (i, key) in keys.enumerated() {
            let row = UIView()
            row.tag = i
            row.isUserInteractionEnabled = true
            row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(rowTapped(_:))))

            let name = UILabel()
            name.text = titles[i]
            name.font = UIFont.systemFont(ofSize: 17, weight: .regular)
            name.textColor = .label
            name.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(name)
            nameLabels.append(name)

            let check = UIImageView()
            check.image = UIImage(systemName: "checkmark")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
            check.tintColor = .systemBlue
            check.contentMode = .scaleAspectFit
            check.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(check)
            checkViews.append(check)

            NSLayoutConstraint.activate([
                name.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 24),
                name.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                name.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -12),
                check.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -24),
                check.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                check.widthAnchor.constraint(equalToConstant: 18),
                check.heightAnchor.constraint(equalToConstant: 18),
            ])

            if key == "system" {
                systemDetailLabel.text = systemDetail
                systemDetailLabel.font = UIFont.systemFont(ofSize: 17, weight: .regular)
                systemDetailLabel.textColor = .secondaryLabel
                systemDetailLabel.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(systemDetailLabel)
                NSLayoutConstraint.activate([
                    systemDetailLabel.trailingAnchor.constraint(equalTo: check.leadingAnchor, constant: -10),
                    systemDetailLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                    name.trailingAnchor.constraint(lessThanOrEqualTo: systemDetailLabel.leadingAnchor, constant: -12),
                ])
            }
            rows.append(row)
        }

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        addSubview(cardView)

        var constraints: [NSLayoutConstraint] = [
            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 64),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),
            cardView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ]
        for (i, row) in rows.enumerated() {
            row.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview(row)
            constraints.append(row.leadingAnchor.constraint(equalTo: cardView.leadingAnchor))
            constraints.append(row.trailingAnchor.constraint(equalTo: cardView.trailingAnchor))
            constraints.append(row.heightAnchor.constraint(equalToConstant: 52))
            if i == 0 {
                constraints.append(row.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8))
            } else {
                constraints.append(row.topAnchor.constraint(equalTo: rows[i - 1].bottomAnchor))
            }
            if i < rows.count - 1 {
                let sep = UIView()
                sep.backgroundColor = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                cardView.addSubview(sep)
                constraints.append(contentsOf: [
                    sep.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
                    sep.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
                    sep.topAnchor.constraint(equalTo: row.bottomAnchor),
                    sep.heightAnchor.constraint(equalToConstant: 0.5),
                ])
            } else {
                constraints.append(row.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -8))
            }
        }
        NSLayoutConstraint.activate(constraints)
        updateChecks()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Initial selection: the web's langPref ("system" | "zh-Hans" |
    // "zh-Hant" | "en").
    func configure(selected: String) {
        selectedKey = keys.contains(selected) ? selected : "system"
        updateChecks()
    }

    // Re-apply localized strings after a language change made from this
    // picker (AppDelegate.applyLanguage calls this while it is open).
    func relocalize(pageTitle: String, systemTitle: String, hansTitle: String, hantTitle: String, enTitle: String, systemDetail: String) {
        titleLabel.text = pageTitle
        let titles = [systemTitle, hansTitle, hantTitle, enTitle]
        for (i, label) in nameLabels.enumerated() where i < titles.count { label.text = titles[i] }
        systemDetailLabel.text = systemDetail
    }

    @objc private func rowTapped(_ gesture: UITapGestureRecognizer) {
        guard let row = gesture.view, keys.indices.contains(row.tag) else { return }
        let key = keys[row.tag]
        selectedKey = key
        updateChecks()
        onSelect?(key)
    }

    private func updateChecks() {
        for (i, key) in keys.enumerated() {
            checkViews[i].isHidden = key != selectedKey
        }
    }
}
