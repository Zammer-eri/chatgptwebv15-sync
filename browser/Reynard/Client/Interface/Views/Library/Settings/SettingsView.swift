//
//  SettingsView.swift
//  Reynard
//
//  Created by Minh Ton on 9/3/26.
//

import UIKit

class SettingsTableViewController: UITableViewController {
    let preferences = BrowserPreferences.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.alwaysBounceVertical = true
        tableView.keyboardDismissMode = .interactive
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
    }
}

final class SettingsRootViewController: SettingsTableViewController {
    enum Section: Int, CaseIterable {
        case compatibility
    }
    
    var visibleSections: [Section] {
        Section.allCases
    }
    
    let androidUASwitch = UISwitch()
    
    init() {
        super.init(style: .insetGrouped)
        title = "Settings"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        androidUASwitch.addTarget(self, action: #selector(androidUASwitchChanged), for: .valueChanged)
        refreshControls()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshControls()
        tableView.reloadData()
    }
    
    func refreshControls() {
        androidUASwitch.isOn = preferences.useAndroidUserAgent
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard visibleSections.indices.contains(section) else { return 0 }
        switch visibleSections[section] {
        case .compatibility: return 1
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard visibleSections.indices.contains(indexPath.section) else { return UITableViewCell() }
        switch visibleSections[indexPath.section] {
        case .compatibility:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Use Android User Agent"
            cell.selectionStyle = .none
            cell.accessoryView = androidUASwitch
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard visibleSections.indices.contains(indexPath.section) else { return }
        switch visibleSections[indexPath.section] {
        case .compatibility:
            break
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard visibleSections.indices.contains(section) else { return nil }
        switch visibleSections[section] {
        case .compatibility: return "Compatibility"
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard visibleSections.indices.contains(section) else { return nil }
        switch visibleSections[section] {
        case .compatibility:
            return preferences.useAndroidUserAgent
            ? "ChatGPT will see Firefox for Android."
            : "ChatGPT will see Gecko's default iOS user agent."
        }
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        nil
    }
}

final class SettingsView: UIView {
    private weak var hostedViewController: SettingsRootViewController?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        embedViewControllerIfNeeded()
    }
    
    private func embedViewControllerIfNeeded() {
        guard hostedViewController == nil,
              let parentViewController = containingViewController else { return }
        let settingsVC = SettingsRootViewController()
        settingsVC.view.translatesAutoresizingMaskIntoConstraints = false
        settingsVC.view.backgroundColor = .clear
        parentViewController.addChild(settingsVC)
        addSubview(settingsVC.view)
        NSLayoutConstraint.activate([
            settingsVC.view.topAnchor.constraint(equalTo: topAnchor),
            settingsVC.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            settingsVC.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            settingsVC.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        settingsVC.didMove(toParent: parentViewController)
        hostedViewController = settingsVC
    }
}

extension SettingsRootViewController {
    func attachProgressView(_ progressView: UIProgressView, to alert: UIAlertController) {
        guard let messageText = alert.message,
              let messageLabel = alert.view.firstDescendantLabel(withText: messageText) else { return }
        alert.view.addSubview(progressView)
        let cancelAnchorView: UIView? = {
            if let button = alert.view.firstDescendantButton(withTitle: "Cancel") { return button }
            return alert.view.firstDescendantView(containingLabelText: "Cancel")
        }()
        var constraints = [
            progressView.widthAnchor.constraint(equalTo: messageLabel.widthAnchor),
            progressView.centerXAnchor.constraint(equalTo: messageLabel.centerXAnchor),
            progressView.topAnchor.constraint(greaterThanOrEqualTo: messageLabel.bottomAnchor, constant: 12),
        ]
        if let cancelAnchorView {
            let verticalGuide = UILayoutGuide()
            alert.view.addLayoutGuide(verticalGuide)
            constraints.append(contentsOf: [
                verticalGuide.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 16),
                verticalGuide.bottomAnchor.constraint(equalTo: cancelAnchorView.topAnchor, constant: -16),
                progressView.centerYAnchor.constraint(equalTo: verticalGuide.centerYAnchor),
            ])
        } else {
            constraints.append(progressView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 20))
        }
        NSLayoutConstraint.activate(constraints)
    }

    func dismissAlertIfPresented(_ alert: UIAlertController, completion: @escaping () -> Void) {
        guard presentedViewController === alert else { completion(); return }
        alert.dismiss(animated: true, completion: completion)
    }
}

extension UIViewController {
    func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension UIView {
    func firstDescendantLabel(withText text: String) -> UILabel? {
        if let label = self as? UILabel, label.text == text { return label }
        for subview in subviews {
            if let match = subview.firstDescendantLabel(withText: text) { return match }
        }
        return nil
    }
    
    func firstDescendantButton(withTitle title: String) -> UIButton? {
        if let button = self as? UIButton, button.currentTitle == title { return button }
        for subview in subviews {
            if let match = subview.firstDescendantButton(withTitle: title) { return match }
        }
        return nil
    }
    
    func firstDescendantView(containingLabelText text: String) -> UIView? {
        if subviews.contains(where: { ($0 as? UILabel)?.text == text }) { return self }
        for subview in subviews {
            if let match = subview.firstDescendantView(containingLabelText: text) { return match }
        }
        return nil
    }
}

private extension UIView {
    var containingViewController: UIViewController? {
        sequence(first: next, next: { $0?.next }).first(where: { $0 is UIViewController }) as? UIViewController
    }
}
