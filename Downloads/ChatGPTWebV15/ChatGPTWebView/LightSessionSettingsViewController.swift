import UIKit

final class LightSessionSettingsViewController: UIViewController, UITextFieldDelegate {
    var onSave: ((LightSessionSettings) -> Void)?

    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let enabledSwitch = UISwitch()
    private let enabledLabel = UILabel()
    private let keepTitleLabel = UILabel()
    private let keepField = UITextField()
    private let keepHintLabel = UILabel()
    private let ultraLeanSwitch = UISwitch()
    private let ultraLeanLabel = UILabel()
    private let ultraLeanHintLabel = UILabel()
    private let blurSwitch = UISwitch()
    private let shadowsSwitch = UISwitch()
    private let motionSwitch = UISwitch()
    private let containRowsSwitch = UISwitch()
    private let noteLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var settings: LightSessionSettings

    init(settings: LightSessionSettings) {
        self.settings = settings.sanitized
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureLabels()
        configureControls()
        configureKeyboardHandling()
        layoutInterface()
        applyState()
    }

    private func configureLabels() {
        titleLabel.text = "Performance"
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.numberOfLines = 0

        bodyLabel.text = "Light Session trims long ChatGPT conversations before the web app renders them. It keeps only the most recent visible turns in the UI to reduce lag."
        bodyLabel.font = .systemFont(ofSize: 16, weight: .regular)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0

        enabledLabel.text = "Enable Light Session"
        enabledLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        keepTitleLabel.text = "Keep visible turns"
        keepTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        keepHintLabel.text = "Range: \(LightSessionSettings.minimumKeep)-\(LightSessionSettings.maximumKeep)"
        keepHintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        keepHintLabel.textColor = .secondaryLabel

        ultraLeanLabel.text = "Ultra Lean"
        ultraLeanLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        ultraLeanHintLabel.text = "Subtle performance mode. Reduces blur, shadows, and motion without flattening the whole UI."
        ultraLeanHintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        ultraLeanHintLabel.textColor = .secondaryLabel
        ultraLeanHintLabel.numberOfLines = 0

        noteLabel.text = "Saving reloads the current page so the new trim limit applies immediately."
        noteLabel.font = .systemFont(ofSize: 13, weight: .medium)
        noteLabel.textColor = .secondaryLabel
        noteLabel.numberOfLines = 0
    }

    private func configureControls() {
        enabledSwitch.isOn = settings.enabled
        enabledSwitch.addTarget(self, action: #selector(handleEnabledChanged), for: .valueChanged)

        keepField.borderStyle = .roundedRect
        keepField.keyboardType = .numberPad
        keepField.textAlignment = .right
        keepField.text = "\(settings.keep)"
        keepField.placeholder = "\(LightSessionSettings.defaultKeep)"
        keepField.delegate = self

        ultraLeanSwitch.isOn = settings.ultraLean
        ultraLeanSwitch.addTarget(self, action: #selector(handleUltraLeanChanged), for: .valueChanged)

        blurSwitch.isOn = settings.reduceBlur
        blurSwitch.addTarget(self, action: #selector(handleReduceBlurChanged), for: .valueChanged)

        shadowsSwitch.isOn = settings.reduceShadows
        shadowsSwitch.addTarget(self, action: #selector(handleReduceShadowsChanged), for: .valueChanged)

        motionSwitch.isOn = settings.reduceMotion
        motionSwitch.addTarget(self, action: #selector(handleReduceMotionChanged), for: .valueChanged)

        containRowsSwitch.isOn = settings.containChatRows
        containRowsSwitch.addTarget(self, action: #selector(handleContainRowsChanged), for: .valueChanged)

        saveButton.configuration = .filled()
        saveButton.configuration?.title = "Save"
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        cancelButton.configuration = .plain()
        cancelButton.configuration?.title = "Cancel"
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    }

    private func configureKeyboardHandling() {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(handleKeyboardDone))
        ]
        keepField.inputAccessoryView = toolbar

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    private func layoutInterface() {
        let enabledRow = UIStackView(arrangedSubviews: [enabledLabel, UIView(), enabledSwitch])
        enabledRow.axis = .horizontal
        enabledRow.alignment = .center

        let keepHeaderRow = UIStackView(arrangedSubviews: [keepTitleLabel, UIView(), keepHintLabel])
        keepHeaderRow.axis = .horizontal
        keepHeaderRow.alignment = .center
        keepHeaderRow.spacing = 12

        let ultraLeanRow = UIStackView(arrangedSubviews: [ultraLeanLabel, UIView(), ultraLeanSwitch])
        ultraLeanRow.axis = .horizontal
        ultraLeanRow.alignment = .center

        let blurRow = makeToggleRow(title: "Reduce blur", toggle: blurSwitch)
        let shadowsRow = makeToggleRow(title: "Remove shadows", toggle: shadowsSwitch)
        let motionRow = makeToggleRow(title: "Reduce motion", toggle: motionSwitch)
        let containRowsRow = makeToggleRow(title: "Contain chat rows", toggle: containRowsSwitch)

        keepField.translatesAutoresizingMaskIntoConstraints = false
        keepField.widthAnchor.constraint(equalToConstant: 92).isActive = true

        let buttonRow = UIStackView(arrangedSubviews: [cancelButton, saveButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            bodyLabel,
            enabledRow,
            keepHeaderRow,
            keepField,
            ultraLeanRow,
            ultraLeanHintLabel,
            blurRow,
            shadowsRow,
            motionRow,
            containRowsRow,
            noteLabel,
            buttonRow
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func makeToggleRow(title: String, toggle: UISwitch) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.numberOfLines = 1

        let row = UIStackView(arrangedSubviews: [label, UIView(), toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        return row
    }

    private func applyState() {
        let sanitized = settings.sanitized
        keepField.text = "\(sanitized.keep)"
        keepField.isEnabled = sanitized.enabled
        keepTitleLabel.textColor = sanitized.enabled ? .label : .secondaryLabel
        keepField.alpha = sanitized.enabled ? 1.0 : 0.55
        keepHintLabel.alpha = sanitized.enabled ? 1.0 : 0.55
        ultraLeanSwitch.isOn = sanitized.ultraLean
        blurSwitch.isOn = sanitized.reduceBlur
        shadowsSwitch.isOn = sanitized.reduceShadows
        motionSwitch.isOn = sanitized.reduceMotion
        containRowsSwitch.isOn = sanitized.containChatRows
        let ultraLeanControlsEnabled = sanitized.ultraLean
        blurSwitch.isEnabled = ultraLeanControlsEnabled
        shadowsSwitch.isEnabled = ultraLeanControlsEnabled
        motionSwitch.isEnabled = ultraLeanControlsEnabled
        containRowsSwitch.isEnabled = ultraLeanControlsEnabled
    }

    @objc private func handleEnabledChanged() {
        settings.enabled = enabledSwitch.isOn
        applyState()
    }

    @objc private func handleUltraLeanChanged() {
        settings.ultraLean = ultraLeanSwitch.isOn
        applyState()
    }

    @objc private func handleReduceBlurChanged() {
        settings.reduceBlur = blurSwitch.isOn
        applyState()
    }

    @objc private func handleReduceShadowsChanged() {
        settings.reduceShadows = shadowsSwitch.isOn
        applyState()
    }

    @objc private func handleReduceMotionChanged() {
        settings.reduceMotion = motionSwitch.isOn
        applyState()
    }

    @objc private func handleContainRowsChanged() {
        settings.containChatRows = containRowsSwitch.isOn
        applyState()
    }

    private func parsedKeepValue() -> Int? {
        let rawValue = keepField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let keep = Int(rawValue) else {
            return nil
        }

        return keep
    }

    @objc private func saveTapped() {
        view.endEditing(true)

        if settings.enabled {
            guard let keep = parsedKeepValue() else {
                presentAlert(title: "Invalid value", message: "Enter a number between \(LightSessionSettings.minimumKeep) and \(LightSessionSettings.maximumKeep).")
                return
            }

            guard (LightSessionSettings.minimumKeep...LightSessionSettings.maximumKeep).contains(keep) else {
                presentAlert(title: "Out of range", message: "Choose a value between \(LightSessionSettings.minimumKeep) and \(LightSessionSettings.maximumKeep).")
                return
            }

            settings.keep = keep
        }

        onSave?(settings.sanitized)
        dismiss(animated: true)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func handleKeyboardDone() {
        view.endEditing(true)
    }

    @objc private func handleBackgroundTap() {
        view.endEditing(true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        view.endEditing(true)
        return true
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
