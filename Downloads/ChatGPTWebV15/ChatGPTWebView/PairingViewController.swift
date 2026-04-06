import UIKit

final class PairingViewController: UIViewController {
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let hostField = UITextField()
    private let portField = UITextField()
    private let secretField = UITextField()
    private let connectButton = UIButton(type: .system)
    private let pasteButton = UIButton(type: .system)
    private let infoLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureLabels()
        configureFields()
        configureButtons()
        layoutInterface()
        applyExistingConfiguration()
    }

    private func configureLabels() {
        titleLabel.text = "Connect to your desktop helper"
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.numberOfLines = 0

        bodyLabel.text = "Run the helper on your PC, open its /pair page in Safari on this iPhone, or enter the host, port, and secret manually."
        bodyLabel.font = .systemFont(ofSize: 16, weight: .regular)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0

        infoLabel.text = "Hidden diagnostics later: two-finger long press near the top edge."
        infoLabel.font = .systemFont(ofSize: 13, weight: .medium)
        infoLabel.textColor = .secondaryLabel
        infoLabel.numberOfLines = 0
    }

    private func configureFields() {
        [hostField, portField, secretField].forEach {
            $0.borderStyle = .roundedRect
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }

        hostField.placeholder = "Host"
        hostField.keyboardType = .URL

        portField.placeholder = "Port"
        portField.keyboardType = .numberPad
        portField.text = "48713"

        secretField.placeholder = "Secret"
    }

    private func configureButtons() {
        connectButton.configuration = .filled()
        connectButton.configuration?.title = "Save connection"
        connectButton.addTarget(self, action: #selector(saveConfiguration), for: .touchUpInside)

        pasteButton.configuration = .plain()
        pasteButton.configuration?.title = "Paste pairing link"
        pasteButton.addTarget(self, action: #selector(importFromClipboard), for: .touchUpInside)
    }

    private func layoutInterface() {
        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            bodyLabel,
            hostField,
            portField,
            secretField,
            connectButton,
            pasteButton,
            infoLabel
        ])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func applyExistingConfiguration() {
        guard let configuration = HelperConfigurationStore.shared.configuration else {
            return
        }

        hostField.text = configuration.host
        portField.text = String(configuration.port)
        secretField.text = configuration.secret
    }

    @objc private func importFromClipboard() {
        guard let text = UIPasteboard.general.string,
              HelperConfigurationStore.shared.importConfiguration(from: text) else {
            presentAlert(title: "Pairing link missing", message: "Copy the helper pairing link or open the helper /pair page in Safari on this iPhone.")
            return
        }

        dismissOrReload()
    }

    @objc private func saveConfiguration() {
        guard
            let host = hostField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !host.isEmpty,
            let portText = portField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            let port = Int(portText),
            let secret = secretField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !secret.isEmpty
        else {
            presentAlert(title: "Missing values", message: "Enter the desktop helper host, port, and secret.")
            return
        }

        HelperConfigurationStore.shared.save(host: host, port: port, secret: secret)
        dismissOrReload()
    }

    private func dismissOrReload() {
        if presentingViewController != nil {
            dismiss(animated: true)
            return
        }

        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.window?.rootViewController = ViewController()
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
