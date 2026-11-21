import UIKit

// Native Appearance picker (user 2026-11-19, 外观 → Apple UI SDK 27.2):
// two preview cards (Light / Dark) side by side with radio circles below,
// plus an 自动 (Automatic) row with a UISwitch. The preview cards show
// the universal launch splash poster (26C105: one 'Subway Tools' pair
// for the whole app — the light card the light poster, the dark card
// the dark poster), loaded from the same bundle images the launch
// splash uses.
// The view's own background follows the current appearance
// (.systemBackground); the two preview cards are FIXED light/dark so
// they show what each mode looks like.
final class AppearanceView: UIView {

    var onThemeChange: ((String) -> Void)?

    private var autoMode: Bool = true
    private var selectedKey: String = "dark"

    private let titleLabel = UILabel()
    private let cardView = UIView()
    private let lightColumn = UIView()
    private let darkColumn = UIView()
    let lightPreview = PreviewCardView(dark: false)
    let darkPreview = PreviewCardView(dark: true)
    private let lightNameLabel = UILabel()
    private let darkNameLabel = UILabel()
    private let lightRadio = UIButton(type: .system)
    private let darkRadio = UIButton(type: .system)
    private let divider = UIView()
    private let autoRow = UIView()
    private let autoLabel = UILabel()
    private let autoSwitch = UISwitch()

    init(lightTitle: String, darkTitle: String, autoTitle: String, appearanceTitle: String) {
        super.init(frame: .zero)
        backgroundColor = .systemBackground

        titleLabel.text = appearanceTitle
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .label

        cardView.backgroundColor = .secondarySystemBackground
        cardView.applyAppleCorner(radius: 28)
        cardView.clipsToBounds = true

        lightNameLabel.text = lightTitle
        darkNameLabel.text = darkTitle
        for nameLabel in [lightNameLabel, darkNameLabel] {
            nameLabel.font = UIFont.systemFont(ofSize: 17, weight: .regular)
            nameLabel.textColor = .label
            nameLabel.textAlignment = .center
        }

        for radio in [lightRadio, darkRadio] {
            radio.layer.cornerRadius = 14
            radio.layer.masksToBounds = true
            radio.layer.borderWidth = 2
            radio.addTarget(self, action: #selector(radioTapped(_:)), for: .touchUpInside)
        }
        lightRadio.tag = 0
        darkRadio.tag = 1

        divider.backgroundColor = .separator

        autoLabel.text = autoTitle
        autoLabel.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        autoLabel.textColor = .label
        autoSwitch.onTintColor = .systemGreen
        autoSwitch.addTarget(self, action: #selector(autoSwitchChanged), for: .valueChanged)

        lightColumn.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(lightColumnTapped)))
        darkColumn.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(darkColumnTapped)))

        for v in [titleLabel, cardView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        for v in [lightColumn, darkColumn, divider, autoRow] { v.translatesAutoresizingMaskIntoConstraints = false; cardView.addSubview(v) }
        for v in [lightPreview, lightNameLabel, lightRadio] { v.translatesAutoresizingMaskIntoConstraints = false; lightColumn.addSubview(v) }
        for v in [darkPreview, darkNameLabel, darkRadio] { v.translatesAutoresizingMaskIntoConstraints = false; darkColumn.addSubview(v) }
        for v in [autoLabel, autoSwitch] { v.translatesAutoresizingMaskIntoConstraints = false; autoRow.addSubview(v) }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: UIDevice.current.userInterfaceIdiom == .pad ? 132 : 64), // iPad: the top tab bar + native header strip occupy ~106pt, so the title starts below them (user 2026-11-21).
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),

            cardView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 600), // Wide screens (iPad / Duo): cap the card so the 1.9-aspect previews fit the screen height; iPhone widths are under the cap and unchanged (user 2026-11-21).

            lightColumn.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 24),
            lightColumn.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            lightColumn.trailingAnchor.constraint(equalTo: darkColumn.leadingAnchor, constant: -16),
            lightColumn.widthAnchor.constraint(equalTo: darkColumn.widthAnchor),

            darkColumn.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 24),
            darkColumn.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            lightPreview.topAnchor.constraint(equalTo: lightColumn.topAnchor),
            lightPreview.leadingAnchor.constraint(equalTo: lightColumn.leadingAnchor),
            lightPreview.trailingAnchor.constraint(equalTo: lightColumn.trailingAnchor),
            lightPreview.heightAnchor.constraint(equalTo: lightPreview.widthAnchor, multiplier: 1.9),

            darkPreview.topAnchor.constraint(equalTo: darkColumn.topAnchor),
            darkPreview.leadingAnchor.constraint(equalTo: darkColumn.leadingAnchor),
            darkPreview.trailingAnchor.constraint(equalTo: darkColumn.trailingAnchor),
            darkPreview.heightAnchor.constraint(equalTo: darkPreview.widthAnchor, multiplier: 1.9),

            lightNameLabel.topAnchor.constraint(equalTo: lightPreview.bottomAnchor, constant: 12),
            lightNameLabel.leadingAnchor.constraint(equalTo: lightColumn.leadingAnchor),
            lightNameLabel.trailingAnchor.constraint(equalTo: lightColumn.trailingAnchor),

            darkNameLabel.topAnchor.constraint(equalTo: darkPreview.bottomAnchor, constant: 12),
            darkNameLabel.leadingAnchor.constraint(equalTo: darkColumn.leadingAnchor),
            darkNameLabel.trailingAnchor.constraint(equalTo: darkColumn.trailingAnchor),

            lightRadio.topAnchor.constraint(equalTo: lightNameLabel.bottomAnchor, constant: 10),
            lightRadio.centerXAnchor.constraint(equalTo: lightColumn.centerXAnchor),
            lightRadio.widthAnchor.constraint(equalToConstant: 28),
            lightRadio.heightAnchor.constraint(equalToConstant: 28),
            lightRadio.bottomAnchor.constraint(equalTo: lightColumn.bottomAnchor),

            darkRadio.topAnchor.constraint(equalTo: darkNameLabel.bottomAnchor, constant: 10),
            darkRadio.centerXAnchor.constraint(equalTo: darkColumn.centerXAnchor),
            darkRadio.widthAnchor.constraint(equalToConstant: 28),
            darkRadio.heightAnchor.constraint(equalToConstant: 28),
            darkRadio.bottomAnchor.constraint(equalTo: darkColumn.bottomAnchor),

            divider.topAnchor.constraint(equalTo: lightColumn.bottomAnchor, constant: 24),
            divider.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            divider.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            autoRow.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),
            autoRow.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            autoRow.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            autoRow.heightAnchor.constraint(equalToConstant: 56),
            autoRow.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),

            autoLabel.leadingAnchor.constraint(equalTo: autoRow.leadingAnchor),
            autoLabel.centerYAnchor.constraint(equalTo: autoRow.centerYAnchor),
            autoSwitch.trailingAnchor.constraint(equalTo: autoRow.trailingAnchor),
            autoSwitch.centerYAnchor.constraint(equalTo: autoRow.centerYAnchor),
        ])

        updateRadios()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Initial state from the web's theme ("system" | "light" | "dark").
    // When the theme is "system", the checked card is the effective
    // (system) appearance, passed in as effectiveDark.
    func configure(theme: String, effectiveDark: Bool) {
        if theme == "light" || theme == "dark" {
            autoMode = false
            selectedKey = theme
        } else {
            autoMode = true
            selectedKey = effectiveDark ? "dark" : "light"
        }
        updateRadios()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // System appearance changed while 自动 is ON: the checked card
        // follows the new effective appearance.
        if autoMode, previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            selectedKey = effectiveKey()
            updateRadios()
        }
    }

    private func effectiveKey() -> String {
        return traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
    }

    private func selectCard(_ key: String) {
        autoMode = false
        selectedKey = key
        updateRadios()
        onThemeChange?(key)
    }

    @objc private func radioTapped(_ sender: UIButton) {
        selectCard(sender.tag == 0 ? "light" : "dark")
    }

    @objc private func lightColumnTapped() { selectCard("light") }
    @objc private func darkColumnTapped() { selectCard("dark") }

    @objc private func autoSwitchChanged() {
        autoMode = autoSwitch.isOn
        if autoMode {
            onThemeChange?("system")
            selectedKey = effectiveKey()
        } else {
            // Turning 自动 off keeps the current look as the explicit
            // choice, so the appearance does not jump.
            let key = effectiveKey()
            selectedKey = key
            onThemeChange?(key)
        }
        updateRadios()
    }

    private func updateRadios() {
        styleRadio(lightRadio, selected: selectedKey == "light")
        styleRadio(darkRadio, selected: selectedKey == "dark")
        autoSwitch.isOn = autoMode
    }

    private func styleRadio(_ radio: UIButton, selected: Bool) {
        if selected {
            radio.backgroundColor = .systemBlue
            radio.layer.borderWidth = 0
            radio.layer.borderColor = nil
            let check = UIImage(systemName: "checkmark")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
            radio.setImage(check, for: .normal)
            radio.tintColor = .white
        } else {
            radio.backgroundColor = .clear
            radio.layer.borderWidth = 2
            radio.layer.borderColor = UIColor.systemGray3.cgColor
            radio.setImage(nil, for: .normal)
        }
    }
}

// One Light/Dark preview card: the universal splash poster for this
// mode, filling the whole card. The image is the same bundle asset
// the launch splash shows (SplashST / SplashSTDark since 26C105),
// so the card always matches what starting the app in that mode
// looks like.
final class PreviewCardView: UIView {
    private let dark: Bool
    private let posterView = UIImageView()

    init(dark: Bool) {
        self.dark = dark
        super.init(frame: .zero)
        backgroundColor = dark ? .black : .white
        applyAppleCorner(radius: 20)
        clipsToBounds = true

        posterView.contentMode = .scaleAspectFill
        posterView.clipsToBounds = true
        posterView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(posterView)
        NSLayoutConstraint.activate([
            posterView.topAnchor.constraint(equalTo: topAnchor),
            posterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            posterView.trailingAnchor.constraint(equalTo: trailingAnchor),
            posterView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        refreshPoster()
    }

    // Load this card's poster, mirroring refreshSplashImage()'s
    // naming: since 26C105 the splash is ONE universal pair
    // (SplashST / SplashSTDark) for the whole app, so the city key
    // callers still pass no longer selects anything. Dark prefers
    // SplashSTDark and falls back to the light poster, then the
    // original Beijing poster.
    func refreshPoster(city: String = "bj") {
        let base = "SplashST"
        if dark, let img = UIImage(named: base + "Dark") {
            posterView.image = img
        } else {
            posterView.image = UIImage(named: base) ?? UIImage(named: "Splash")
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
