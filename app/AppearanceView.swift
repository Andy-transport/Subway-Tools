import UIKit

// Native Appearance picker (user 2026-11-19, 外观 → Apple UI SDK 27.2):
// two preview cards (Light / Dark) side by side with radio circles below,
// plus an 自动 (Automatic) row with a UISwitch. The preview cards are
// built natively: a plain "北京" text label (system font, blue — NOT the
// calligraphic wordmark/logo) + a simple line diagram drawn with
// CAShapeLayer + a "配线查询" label. The view's own background follows the
// current appearance (.systemBackground); the two preview cards are FIXED
// light (#fff) and dark (#000) so they show what each mode looks like.
final class AppearanceView: UIView {

    var onThemeChange: ((String) -> Void)?

    private var autoMode: Bool = true
    private var selectedKey: String = "dark"

    private let titleLabel = UILabel()
    private let cardView = UIView()
    private let lightColumn = UIView()
    private let darkColumn = UIView()
    private let lightPreview = PreviewCardView(dark: false)
    private let darkPreview = PreviewCardView(dark: true)
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
        cardView.layer.cornerRadius = 28
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
            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 64),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),

            cardView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

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

// One Light/Dark preview card: fixed background, a plain "北京" text
// label, a simple line diagram, "配线查询" and a small English caption.
final class PreviewCardView: UIView {
    private let dark: Bool
    private let cityLabel = UILabel()
    private let diagram: PreviewDiagramView
    private let queryLabel = UILabel()
    private let captionLabel = UILabel()

    init(dark: Bool) {
        self.dark = dark
        self.diagram = PreviewDiagramView(dark: dark)
        super.init(frame: .zero)
        backgroundColor = dark ? .black : .white
        layer.cornerRadius = 20
        clipsToBounds = true

        cityLabel.text = "北京"
        cityLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        cityLabel.textColor = UIColor(red: 0.05, green: 0.32, blue: 0.72, alpha: 1)
        cityLabel.textAlignment = .center

        queryLabel.text = "配线查询"
        queryLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        queryLabel.textColor = dark ? .white : .black
        queryLabel.textAlignment = .center

        captionLabel.text = "BEIJING SUBWAY · TRACK LAYOUT LOOKUP"
        captionLabel.font = UIFont.systemFont(ofSize: 6.5, weight: .regular)
        captionLabel.textColor = .systemGray
        captionLabel.textAlignment = .center
        captionLabel.adjustsFontSizeToFitWidth = true
        captionLabel.minimumScaleFactor = 0.7

        for v in [cityLabel, diagram, queryLabel, captionLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            cityLabel.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            cityLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            cityLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            diagram.topAnchor.constraint(equalTo: cityLabel.bottomAnchor, constant: 10),
            diagram.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            diagram.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            diagram.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.45),

            queryLabel.topAnchor.constraint(equalTo: diagram.bottomAnchor, constant: 10),
            queryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            queryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            captionLabel.topAnchor.constraint(equalTo: queryLabel.bottomAnchor, constant: 6),
            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            captionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            captionLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// Simple line diagram: a thin circle with a red polyline + end dots,
// drawn to the view's bounds in layoutSubviews.
fileprivate final class PreviewDiagramView: UIView {
    private let dark: Bool
    private let circleLayer = CAShapeLayer()
    private let lineLayer = CAShapeLayer()
    private let startDot = CAShapeLayer()
    private let endDot = CAShapeLayer()

    init(dark: Bool) {
        self.dark = dark
        super.init(frame: .zero)
        backgroundColor = .clear
        circleLayer.fillColor = UIColor.clear.cgColor
        circleLayer.strokeColor = (dark ? UIColor.systemGray : UIColor.systemGray4).cgColor
        circleLayer.lineWidth = 1
        lineLayer.fillColor = UIColor.clear.cgColor
        lineLayer.strokeColor = UIColor(red: 0.89, green: 0.0, blue: 0.10, alpha: 1).cgColor
        lineLayer.lineWidth = 1.5
        lineLayer.lineJoin = .round
        lineLayer.lineCap = .round
        startDot.fillColor = lineLayer.strokeColor
        endDot.fillColor = lineLayer.strokeColor
        layer.addSublayer(circleLayer)
        layer.addSublayer(lineLayer)
        layer.addSublayer(startDot)
        layer.addSublayer(endDot)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return }
        let cx = w / 2
        let cy = h / 2
        let r = min(w, h) * 0.42
        circleLayer.frame = bounds
        circleLayer.path = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        let p1 = CGPoint(x: w * 0.12, y: h * 0.40)
        let p2 = CGPoint(x: w * 0.32, y: h * 0.60)
        let p3 = CGPoint(x: w * 0.88, y: h * 0.60)
        let line = UIBezierPath()
        line.move(to: p1)
        line.addLine(to: p2)
        line.addLine(to: p3)
        lineLayer.frame = bounds
        lineLayer.path = line.cgPath
        startDot.frame = bounds
        startDot.path = UIBezierPath(arcCenter: p1, radius: 2.5, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        endDot.frame = bounds
        endDot.path = UIBezierPath(arcCenter: p3, radius: 2.5, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
    }
}
