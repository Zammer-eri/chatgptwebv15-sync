import UIKit

final class LightSessionSettingsViewController: UIViewController, UITextFieldDelegate {
    var onSave: ((LightSessionSettings) -> Void)?

    private let enabledSwitch = UISwitch()
    private let keepField = UITextField()
    private let keepTitleLabel = UILabel()
    private let keepHintLabel = UILabel()
    private var settings: LightSessionSettings

    init(settings: LightSessionSettings) {
        self.settings = settings.sanitized
        super.init(nibName: nil, bundle: nil)
        title = "Light Session"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureNavigation()
        configureControls()
        layoutInterface()
        applyState()
    }

    private func configureNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Save",
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
    }

    private func configureControls() {
        enabledSwitch.isOn = settings.enabled
        enabledSwitch.addTarget(self, action: #selector(enabledChanged), for: .valueChanged)

        keepField.borderStyle = .roundedRect
        keepField.keyboardType = .numberPad
        keepField.textAlignment = .right
        keepField.text = "\(settings.keep)"
        keepField.placeholder = "\(LightSessionSettings.defaultKeep)"
        keepField.delegate = self

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(doneTapped)),
        ]
        keepField.inputAccessoryView = toolbar
    }

    private func layoutInterface() {
        let bodyLabel = UILabel()
        bodyLabel.text = "Trim long ChatGPT conversation payloads before the page renders them. This keeps older devices faster in large threads."
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0

        let enabledLabel = UILabel()
        enabledLabel.text = "Enable Light Session"
        enabledLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        keepTitleLabel.text = "Keep visible turns"
        keepTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        keepHintLabel.text = "\(LightSessionSettings.minimumKeep)-\(LightSessionSettings.maximumKeep)"
        keepHintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        keepHintLabel.textColor = .secondaryLabel

        let enabledRow = UIStackView(arrangedSubviews: [enabledLabel, UIView(), enabledSwitch])
        enabledRow.axis = .horizontal
        enabledRow.alignment = .center

        let keepHeaderRow = UIStackView(arrangedSubviews: [keepTitleLabel, UIView(), keepHintLabel])
        keepHeaderRow.axis = .horizontal
        keepHeaderRow.alignment = .center
        keepHeaderRow.spacing = 12

        keepField.translatesAutoresizingMaskIntoConstraints = false
        keepField.widthAnchor.constraint(equalToConstant: 96).isActive = true

        let stack = UIStackView(arrangedSubviews: [
            bodyLabel,
            enabledRow,
            keepHeaderRow,
            keepField,
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
        ])
    }

    private func applyState() {
        let enabled = enabledSwitch.isOn
        keepField.isEnabled = enabled
        keepField.alpha = enabled ? 1 : 0.55
        keepTitleLabel.textColor = enabled ? .label : .secondaryLabel
        keepHintLabel.alpha = enabled ? 1 : 0.55
    }

    private func parsedKeepValue() -> Int? {
        let value = keepField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Int(value)
    }

    @objc private func enabledChanged() {
        settings.enabled = enabledSwitch.isOn
        applyState()
    }

    @objc private func saveTapped() {
        view.endEditing(true)

        if enabledSwitch.isOn {
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

        settings.enabled = enabledSwitch.isOn
        onSave?(settings.sanitized)
        navigationController?.popViewController(animated: true)
    }

    @objc private func doneTapped() {
        view.endEditing(true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        view.endEditing(true)
        return true
    }
}
