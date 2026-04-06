import UIKit

final class LightSessionSettingsViewController: UIViewController {
    var onSave: ((LightSessionSettings) -> Void)?

    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let enabledSwitch = UISwitch()
    private let enabledLabel = UILabel()
    private let keepTitleLabel = UILabel()
    private let keepValueLabel = UILabel()
    private let keepStepper = UIStepper()
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

        noteLabel.text = "Changes reload the current page so the fetch interceptor can apply cleanly."
        noteLabel.font = .systemFont(ofSize: 13, weight: .medium)
        noteLabel.textColor = .secondaryLabel
        noteLabel.numberOfLines = 0
    }

    private func configureControls() {
        enabledSwitch.isOn = settings.enabled
        enabledSwitch.addTarget(self, action: #selector(handleEnabledChanged), for: .valueChanged)

        keepStepper.minimumValue = Double(LightSessionSettings.minimumKeep)
        keepStepper.maximumValue = Double(LightSessionSettings.maximumKeep)
        keepStepper.stepValue = 1
        keepStepper.value = Double(settings.keep)
        keepStepper.addTarget(self, action: #selector(handleKeepChanged), for: .valueChanged)

        saveButton.configuration = .filled()
        saveButton.configuration?.title = "Save"
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        cancelButton.configuration = .plain()
        cancelButton.configuration?.title = "Cancel"
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    }

    private func layoutInterface() {
        let enabledRow = UIStackView(arrangedSubviews: [enabledLabel, UIView(), enabledSwitch])
        enabledRow.axis = .horizontal
        enabledRow.alignment = .center

        let keepRow = UIStackView(arrangedSubviews: [keepTitleLabel, UIView(), keepValueLabel, keepStepper])
        keepRow.axis = .horizontal
        keepRow.alignment = .center
        keepRow.spacing = 12

        let buttonRow = UIStackView(arrangedSubviews: [cancelButton, saveButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            bodyLabel,
            enabledRow,
            keepRow,
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

    private func applyState() {
        let sanitized = settings.sanitized
        keepValueLabel.text = "\(sanitized.keep)"
        keepValueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        keepValueLabel.textColor = .label

        keepStepper.value = Double(sanitized.keep)
        keepStepper.isEnabled = sanitized.enabled
        keepTitleLabel.textColor = sanitized.enabled ? .label : .secondaryLabel
        keepValueLabel.alpha = sanitized.enabled ? 1.0 : 0.55
    }

    @objc private func handleEnabledChanged() {
        settings.enabled = enabledSwitch.isOn
        applyState()
    }

    @objc private func handleKeepChanged() {
        settings.keep = Int(keepStepper.value)
        applyState()
    }

    @objc private func saveTapped() {
        onSave?(settings.sanitized)
        dismiss(animated: true)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}
